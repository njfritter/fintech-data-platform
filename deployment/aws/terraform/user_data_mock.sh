#!/bin/bash
set -e -x
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "/var/log/mock-data-user-data.log"
}

log "=========================================="
log "Mock Data Generator Startup Script Started"
log "=========================================="

# Configuration (passed from Terraform)
ENVIRONMENT="${environment}"
GITHUB_REPO="${github_repo}"
GITHUB_BRANCH="${github_branch}"
KAFKA_TOPIC="${kafka_topic}"
MSK_CLUSTER_ARN="${msk_cluster_arn}"
KAFKA_REPLICATION_FACTOR="${kafka_replication_factor}"
KAFKA_PARTITIONS_COUNT="${kafka_partition_count}"

# Update and install dependencies
apt-get update -y
apt-get install -y python3-pip python3-venv git default-jre-headless unzip curl

# --- Install AWS CLI v2 ---
log "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp/
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws
export PATH=$PATH:/usr/local/bin
aws --version

# Install Kafka tools (using version 3.9.2)
log "Installing Kafka tools..."
cd /opt
wget https://downloads.apache.org/kafka/3.9.2/kafka_2.13-3.9.2.tgz -O /tmp/kafka.tgz
tar -xzf /tmp/kafka.tgz -C /opt/
mv /opt/kafka_2.13-3.9.2 /opt/kafka
export PATH=$PATH:/opt/kafka/bin

# Download AWS MSK IAM JAR (for IAM authentication)
log "Downloading AWS MSK IAM JAR..."
wget https://github.com/aws/aws-msk-iam-auth/releases/download/v1.1.9/aws-msk-iam-auth-1.1.9-all.jar -O /opt/kafka/libs/aws-msk-iam-auth-1.1.9-all.jar

# Get MSK bootstrap brokers
BOOTSTRAP=$(aws kafka get-bootstrap-brokers \
  --cluster-arn $MSK_CLUSTER_ARN \
  --region ${aws_region} \
  --query 'BootstrapBrokerStringSaslIam' \
  --output text)

log "Bootstrapping with: $BOOTSTRAP"

# Create client properties for IAM authentication
log "Creating client properties for IAM authentication..."
cat > /tmp/client.properties << 'EOF'
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
EOF

# Create Kafka topic (wait for MSK to be ready first)
log "Waiting for MSK to be ready..."
sleep 90

log "Creating Kafka topic: $KAFKA_TOPIC..."
kafka-topics.sh --bootstrap-server $BOOTSTRAP \
  --create \
  --topic ${kafka_topic} \
  --partitions ${kafka_partition_count} \
  --replication-factor ${kafka_replication_factor} \
  --command-config /tmp/client.properties 2>&1 || echo "Topic creation failed or already exists"

# Clone the repository (or copy the script)
cd /home/ubuntu
sudo -u ubuntu git clone --branch "$GITHUB_BRANCH" "$GITHUB_REPO" fintech-data-platform
cd fintech-data-platform

# Create a virtual environment and install dependencies
python3 -m venv venv
source venv/bin/activate
pip install boto3 pandas numpy faker kafka-python pyarrow aws-msk-iam-sasl-signer-python

# Run the AWS mock data generator script
python3 scripts/aws/generate_aws_mock_data.py \
  --s3-bucket ${s3_bucket} \
  --s3-prefix bronze/ \
  --kafka-bootstrap ${msk_bootstrap} \
  --kafka-topic $KAFKA_TOPIC \
  --stream-count ${stream_count} \
  --aws-region ${aws_region}

# Log completion and shut down the instance
log "Mock data generation complete. Shutting down instance."
shutdown -h now