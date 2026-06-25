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

# Update and install dependencies
apt-get update -y
apt-get install -y python3-pip python3-venv git

# Install Kafka tools
log "Installing Kafka tools..."
cd /opt
wget https://downloads.apache.org/kafka/3.6.0/kafka.tgz -O /tmp/kafka.tgz
tar -xzf /tmp/kafka.tgz -C /opt/
mv /opt/kafka_2.13-3.6.0 /opt/kafka
export PATH=$PATH:/opt/kafka/bin

# Get MSK bootstrap brokers
BOOTSTRAP=$(aws kafka get-bootstrap-brokers \
  --cluster-arn $MSK_CLUSTER_ARN \
  --region ${aws_region} \
  --query 'BootstrapBrokerStringSaslIam' \
  --output text)

log "Bootstrapping with: $BOOTSTRAP"

# Create Kafka topic (wait for MSK to be ready first)
log "Waiting for MSK to be ready..."
sleep 90

log "Creating Kafka topic: $KAFKA_TOPIC..."
kafka-topics.sh --bootstrap-server $BOOTSTRAP \
  --create \
  --topic $KAFKA_TOPIC \
  --partitions 3 \
  --replication-factor 3 2>/dev/null || echo "Topic already exists or creation failed"

# Clone the repository (or copy the script)
cd /home/ubuntu
sudo -u ubuntu git clone --branch "$GITHUB_BRANCH" "$GITHUB_REPO" fintech-data-platform
cd fintech-data-platform

# Create a virtual environment and install dependencies
python3 -m venv venv
source venv/bin/activate
pip install boto3 pandas numpy faker kafka-python pyarrow msk-iam-sasl-signer

# Run the AWS mock data generator script
python3 scripts/generate_aws_mock_data.py \
  --s3-bucket ${s3_bucket} \
  --s3-prefix bronze/ \
  --kafka-bootstrap ${msk_bootstrap} \
  --kafka-topic $KAFKA_TOPIC \
  --stream-count ${stream_count} \
  --aws-region ${aws_region}

# Log completion and shut down the instance
log "Mock data generation complete. Shutting down instance."
shutdown -h now