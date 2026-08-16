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
ADMIN_PASSWORD="${admin_password}"
RDS_PASSWORD="${rds_password}"
AURORA_CLUSTER_ENDPOINT="${aurora_cluster_endpoint}"
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
uv pip install apache-airflow apache-airflow-providers-amazon apache-airflow-providers-sqlite "apache-airflow-providers-fab>=2.0.0" boto3 psycopg2-binary asyncpg

# Create Airflow directories in the home directory of the ubuntu user
export UBUNTU_HOME=/home/ubuntu
export AIRFLOW_HOME=$UBUNTU_HOME/airflow
sudo -u ubuntu mkdir -p $AIRFLOW_HOME $AIRFLOW_HOME/dags $AIRFLOW_HOME/logs $AIRFLOW_HOME/plugins

# Get SSL certificate for RDS/Aurora
curl -o /home/ubuntu/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# --- Generate a secure random secret key for Airflow API ---
# This is a Flask secret key for signing session cookies
API_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
log "Generated Airflow API secret key."

# --- Generate a secure random secret key for Airflow API ---
# This is used to encode and decode the JWT (JSON Web Token) used for authentication between internal components, such as the scheduler and workers
API_JWT_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
log "Generated Airflow API JWT secret key."

# --- Generate a secure random secret key for Airflow Fernet ---
# This is used to encrypt sensitive data in the Airflow metadata database, such as connection passwords
FERNET_KEY=$(python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
log "Generated Airflow Fernet key."

# --- Generate a secure random secret key for Airflow internal API authentication ---
# This is used to authenticate internal API requests between Airflow components, such as the scheduler and workers
INTERNAL_API_AUTH_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
log "Generated Airflow internal API authentication key."

# Overwrite the default airflow.cfg with our custom configuration
cat > $AIRFLOW_HOME/airflow.cfg <<EOF
[core]
dags_folder = $UBUNTU_HOME/fintech-data-platform/dags
load_examples = False
# Explicitly set the auth manager to FabAuthManager
auth_manager = airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager
dagbag_import_timeout = 60
execution_api_server_url = http://localhost:8793/execution/

[scheduler]
task_queued_timeout = 600

[worker]
dag_processor_timeout = 120

[dag_processor]
dag_file_processor_timeout = 120

[database]
sql_alchemy_conn = postgresql+psycopg2://rds_admin:$RDS_PASSWORD@$AURORA_CLUSTER_ENDPOINT:5432/airflow?sslmode=verify-full&sslrootcert=/home/ubuntu/global-bundle.pem

[celery]
broker_url = redis://localhost:6379/0
result_backend = db+postgresql://rds_admin:$RDS_PASSWORD@$AURORA_CLUSTER_ENDPOINT:5432/airflow

[api]
auth_backends = airflow.api.auth.backend.basic_auth
host = 0.0.0.0
port = 8793

[api_auth]
jwt_secret = $API_JWT_SECRET_KEY
jwt_algorithm = HS256
access_token_expire_minutes = 30

[webserver]
cookie_samesite = Lax
cookie_secure = False
session_lifetime_days = 30
rbac = True

[fab]
# Flask-AppBuilder (FAB) specific settings for the UI
# This is required for the FabAuthManager to work properly
auth_type = AUTH_DB
auth_role_public = Public
auth_role_admin = Admin
auth_role_public_remove = False
auth_user_registration = False
auth_user_registration_role = Public
auth_oidc_group_field = groups
auth_oidc_role_field = role

[logging]
logging_level = INFO
fab_logging_level = WARNING

[metrics]
statsd_on = False
statsd_host = localhost
statsd_port = 8125
statsd_prefix = airflow
EOF

# Migrate the Airflow database (needs DB environment variable set for Aurora RDS)
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://rds_admin:$RDS_PASSWORD@$AURORA_CLUSTER_ENDPOINT:5432/airflow?sslmode=verify-full&sslrootcert=/home/ubuntu/global-bundle.pem"
airflow db migrate

# Create the Airflow API server wrapper script
log "Creating Airflow API server wrapper script..."
sudo tee /usr/local/bin/start_airflow_api.sh > /dev/null <<'EOF'
#!/bin/bash
set -e

# Kill any process using port 8793
echo "Cleaning up port 8793..."
sudo fuser -k 8793/tcp 2>/dev/null || true

# Sleep a moment to allow the port to be released
sleep 2

# Start the actual Airflow API server
exec /home/ubuntu/.venv/bin/airflow api-server
EOF

# Make the wrapper script executable
sudo chmod +x /usr/local/bin/start_airflow_api.sh

# Create the systemd service file for Airflow API server (formerly webserver)
sudo tee /etc/systemd/system/airflow-api-server.service > /dev/null <<EOF
[Unit]
Description=Airflow API server daemon
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=ubuntu
Environment="AIRFLOW_HOME=$AIRFLOW_HOME"
Environment="AIRFLOW__CORE__DAGS_FOLDER=$UBUNTU_HOME/fintech-data-platform/dags"
Environment="AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://rds_admin:$RDS_PASSWORD@$AURORA_CLUSTER_ENDPOINT:5432/airflow?sslmode=verify-full&sslrootcert=/home/ubuntu/global-bundle.pem"
Environment="AIRFLOW__API__SECRET_KEY=$API_SECRET_KEY"
Environment="AIRFLOW__CORE__FERNET_KEY=$FERNET_KEY"
Environment="AIRFLOW__CORE__INTERNAL_API_SECRET_KEY=$INTERNAL_API_AUTH_KEY"
Environment="AIRFLOW__API_AUTH__JWT_SECRET=$API_JWT_SECRET_KEY"
Environment="AIRFLOW__API_AUTH__JWT_ALGORITHM=HS256"
Environment="AIRFLOW__API_AUTH__ACCESS_TOKEN_EXPIRE_MINUTES=30"
Environment="AIRFLOW__API__PORT=8793"
Environment="AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
ExecStart=/usr/local/bin/start_airflow_api.sh
Restart=always
RestartSec=5
KillMode=mixed
TimeoutStopSec=30

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
Environment="AIRFLOW_HOME=$AIRFLOW_HOME"
Environment="AIRFLOW__CORE__DAGS_FOLDER=$UBUNTU_HOME/fintech-data-platform/dags"
Environment="AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://rds_admin:$RDS_PASSWORD@$AURORA_CLUSTER_ENDPOINT:5432/airflow?sslmode=verify-full&sslrootcert=/home/ubuntu/global-bundle.pem"
Environment="AIRFLOW__API__SECRET_KEY=$API_SECRET_KEY"
Environment="AIRFLOW__CORE__FERNET_KEY=$FERNET_KEY"
Environment="AIRFLOW__CORE__INTERNAL_API_SECRET_KEY=$INTERNAL_API_AUTH_KEY"
Environment="AIRFLOW__API_AUTH__JWT_SECRET=$API_JWT_SECRET_KEY"
Environment="AIRFLOW__API_AUTH__JWT_ALGORITHM=HS256"
Environment="AIRFLOW__API_AUTH__ACCESS_TOKEN_EXPIRE_MINUTES=30"
Environment="AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
ExecStart=/home/ubuntu/.venv/bin/airflow scheduler
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
Environment="AIRFLOW_HOME=$AIRFLOW_HOME"
Environment="AIRFLOW__CORE__DAGS_FOLDER=$UBUNTU_HOME/fintech-data-platform/dags"
Environment="AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://rds_admin:$RDS_PASSWORD@$AURORA_CLUSTER_ENDPOINT:5432/airflow?sslmode=verify-full&sslrootcert=/home/ubuntu/global-bundle.pem"
Environment="AIRFLOW__API__SECRET_KEY=$API_SECRET_KEY"
Environment="AIRFLOW__CORE__FERNET_KEY=$FERNET_KEY"
Environment="AIRFLOW__CORE__INTERNAL_API_SECRET_KEY=$INTERNAL_API_AUTH_KEY"
Environment="AIRFLOW__API_AUTH__JWT_SECRET=$API_JWT_SECRET_KEY"
Environment="AIRFLOW__API_AUTH__JWT_ALGORITHM=HS256"
Environment="AIRFLOW__API_AUTH__ACCESS_TOKEN_EXPIRE_MINUTES=30"
Environment="AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
ExecStart=/home/ubuntu/.venv/bin/airflow dag-processor
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create an admin user (non-interactive)
log "Creating Airflow admin user..."
airflow users create \
  --username Admin \
  --password $ADMIN_PASSWORD \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com

# Create all the Airflow connections needed for the DAGs
log "Creating EMR Serverless connection in Airflow..."
airflow connections add 'emr_serverless_default' \
    --conn-type 'aws' \
    --conn-extra '{"region_name": "us-east-1", "role_arn": "arn:aws:iam::891377165210:role/emr-serverless-job-role"}' || true

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
log "DAGs folder: $UBUNTU_HOME/fintech-data-platform/dags"
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