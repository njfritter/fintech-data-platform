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

log "Installing Airflow, setting DAGS folder and setting up systemd services..."

# Install uv + ensure it's available in the current session + install Airflow providers
log "Installing uv (Universal Virtual Environment)..."
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
source /root/.local/bin/env
uv venv
source .venv/bin/activate
uv pip install apache-airflow apache-airflow-providers-amazon apache-airflow-providers-sqlite "apache-airflow-providers-fab>=2.0.0" boto3

# Create Airflow directories
mkdir -p /home/ubuntu/airflow/dags /home/ubuntu/airflow/logs /home/ubuntu/airflow/plugins
export AIRFLOW_HOME=/home/ubuntu/airflow

# Migrate the Airflow database
airflow db migrate

# --- Generate a secure random secret key for Airflow API ---
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
log "Generated Airflow API secret key."

# Create the systemd service file for Airflow API server (formerly webserver)
sudo tee /etc/systemd/system/airflow-api-server.service > /dev/null <<EOF
[Unit]
Description=Airflow API server daemon
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=ubuntu
Environment="AIRFLOW_HOME=/home/ubuntu/airflow"
Environment="AIRFLOW__CORE__DAGS_FOLDER=/home/ubuntu/fintech-data-platform/dags"
Environment="AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@localhost:5432/airflow"
Environment="AIRFLOW__API__SECRET_KEY=$SECRET_KEY"
Environment="AIRFLOW__API__PORT=8793"
Environment="AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
ExecStart=/usr/local/bin/airflow api-server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create the systemd service file for Airflow scheduler
sudo tee /etc/systemd/system/airflow-scheduler.service > /dev/null <<EOF
[Unit]
Description=Airflow scheduler daemon
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=ubuntu
Environment="AIRFLOW_HOME=/home/ubuntu/airflow"
Environment="AIRFLOW__CORE__DAGS_FOLDER=/home/ubuntu/airflow/dags"
Environment="AIRFLOW__API__SECRET_KEY=$SECRET_KEY"
Environment="AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
ExecStart=/usr/local/bin/airflow scheduler
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create the systemd service file for Airflow DAG processor
sudo tee /etc/systemd/system/airflow-dag-processor.service > /dev/null <<EOF
[Unit]
Description=Airflow DAG Processor
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=ubuntu
Environment="AIRFLOW_HOME=/home/ubuntu/airflow"
Environment="AIRFLOW__API__SECRET_KEY=$SECRET_KEY"
Environment="AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
ExecStart=/usr/local/bin/airflow dag-processor
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create an admin user (non-interactive)
airflow users create \
  --username admin \
  --password admin \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com

# Enable the services to start on boot
sudo systemctl enable airflow-api-server.service airflow-scheduler.service airflow-dag-processor.service

# Now we can safely restart them
log "Restarting Airflow services..."
sudo systemctl daemon-reload
sudo systemctl restart airflow-api-server airflow-scheduler airflow-dag-processor

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