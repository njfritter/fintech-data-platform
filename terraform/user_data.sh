#!/bin/bash
set -e -x
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "/var/log/fincore-user-data.log"
}

log "=========================================="
log "FinCore Startup Script Started"
log "=========================================="

# Configuration (passed from Terraform)
ENVIRONMENT="${environment}"
GITHUB_REPO="${github_repo}"
GITHUB_BRANCH="${github_branch}"
ADMIN_PASSWORD="${admin_password}"

# Install Docker and dependencies
log "Installing Docker..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release git jq htop

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
log "Cloning FinCore repository..."
cd /home/ubuntu
sudo -u ubuntu git clone --branch "$GITHUB_BRANCH" "$GITHUB_REPO" fincore-data-platform

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

log "FinCore setup complete at $(date)"
log "Admin password: ${ADMIN_PASSWORD}"
log "=========================================="