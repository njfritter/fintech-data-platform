#!/bin/bash
set -e -x
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "/var/log/fintech-data-platform-user-data.log"
}

log "=========================================="
log "Fintech Data Platform Startup Script Started"
log "=========================================="

# Configuration (passed from Terraform)
ENVIRONMENT="${environment}"
GITHUB_REPO="${github_repo}"
GITHUB_BRANCH="${github_branch}"
AWS_EMRSERVERLESS_APPLICATION_SPARK_ID="${aws_emrserverless_application_spark_id}"

# Install Docker and dependencies
log "Installing Docker..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release git jq htop unzip

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# Install AWS CLI v2
log "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp/
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# Install CloudWatch Agent
log "Installing CloudWatch Agent..."
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# Clone repository
log "Cloning Fintech Data Platform repository..."
cd /home/ubuntu
sudo -u ubuntu git clone --branch "$GITHUB_BRANCH" "$GITHUB_REPO" fintech-data-platform

# --- Set up Airflow's DAGs folder ---
log "Configuring Airflow DAGs folder..."

# Set the environment variable in the Airflow service file
# This ensures Airflow always uses this folder, even after reboots
sudo mkdir -p /etc/systemd/system/airflow-webserver.service.d
sudo tee /etc/systemd/system/airflow-webserver.service.d/override.conf > /dev/null <<EOF
[Service]
Environment="AIRFLOW__CORE__DAGS_FOLDER=/home/ubuntu/fintech-data-platform/dags"
EOF

sudo mkdir -p /etc/systemd/system/airflow-scheduler.service.d
sudo tee /etc/systemd/system/airflow-scheduler.service.d/override.conf > /dev/null <<EOF
[Service]
Environment="AIRFLOW__CORE__DAGS_FOLDER=/home/ubuntu/fintech-data-platform/dags"
EOF

# Reload systemd and restart Airflow services
log "Restarting Airflow services..."
sudo systemctl daemon-reload
sudo systemctl restart airflow-webserver
sudo systemctl restart airflow-scheduler

# Install uv + ensure it's available in the current session + install Airflow providers
log "Installing uv (Universal Virtual Environment)..."
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv pip install apache-airflow-providers-amazon apache-airflow-providers-sqlite boto3

# --- Validate that DAGs are visible ---
log "Validating Airflow DAGs..."
sleep 10  # Give Airflow time to parse DAGs
airflow dags list | head -10

log "=========================================="
log "Airflow DAGs folder configuration complete!"
log "DAGs folder: /home/ubuntu/fintech-data-platform/dags"
log "=========================================="

# Set up CloudWatch Agent config
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'EOF'
{
  "metrics": {
    "metrics_collected": {
      "docker": {
        "metrics_collection_interval": 60,
        "docker_endpoint": "unix:///var/run/docker.sock"
      },
      "statsd": {
        "service_address": ":8125",
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF

systemctl restart amazon-cloudwatch-agent

echo "export EMR_SERVERLESS_APP_ID=$AWS_EMRSERVERLESS_APPLICATION_SPARK_ID" >> /etc/environment

log "Fintech Data Platform setup complete at $(date)"
log "=========================================="