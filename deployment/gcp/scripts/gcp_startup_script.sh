#!/bin/bash
# =============================================================================
# Fintech Data Platform - GCP Startup Script
# Version: 1.0
# Purpose: Automate deployment of Fintech Data Platform on GCP VM
# Compatible with: Ubuntu 22.04 LTS, Debian 11+
# =============================================================================

set -euo pipefail  # Exit on error, undefined variable, or pipe failure

# -----------------------------------------------------------------------------
# Configuration Variables (Customize these as needed)
# -----------------------------------------------------------------------------
REPO_URL="https://github.com/your-username/fintech-data-platform.git"
BRANCH="main"
DOCKER_COMPOSE_FILE="docker-compose.yml"
PROJECT_DIR="/opt/fintech"
LOG_FILE="/var/log/fintech-startup.log"
DATA_DIR="/mnt/fintech-data"

# -----------------------------------------------------------------------------
# Logging Function
# -----------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# System Optimization for Docker on GCP
# -----------------------------------------------------------------------------
optimize_system() {
    log "Optimizing system for Docker..."

    # Increase inotify limits (for file system watching, needed for some data apps)
    echo "fs.inotify.max_user_instances=8192" >> /etc/sysctl.conf
    echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf
    sysctl -p

    # Set vm.max_map_count (required for Elasticsearch-style services, good practice)
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    sysctl -p

    # Disable swap (recommended for Kubernetes and Spark, but optional for Docker)
    swapoff -a

    # Configure Docker daemon for better performance
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
EOF

    systemctl restart docker
    log "System optimization complete"
}

# -----------------------------------------------------------------------------
# Install Docker and Docker Compose
# -----------------------------------------------------------------------------
install_docker() {
    log "Installing Docker and dependencies..."

    # Update package list
    apt-get update

    # Install prerequisites
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        git \
        make \
        jq \
        htop

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Set up stable repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Add current user to docker group
    usermod -aG docker $USER

    # Install standalone docker-compose (fallback)
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    log "Docker installation complete"
    docker --version
    docker-compose --version
}

# -----------------------------------------------------------------------------
# Setup Data Directory and Clone Repository
# -----------------------------------------------------------------------------
setup_application() {
    log "Setting up application in $PROJECT_DIR"

    # Create data directory (persistent volume for MinIO/Delta Lake)
    mkdir -p "$DATA_DIR"
    chmod 755 "$DATA_DIR"

    # Clone or update repository
    if [ -d "$PROJECT_DIR/.git" ]; then
        log "Repository exists, pulling latest changes..."
        cd "$PROJECT_DIR"
        git checkout "$BRANCH"
        git pull origin "$BRANCH"
    else
        log "Cloning repository from $REPO_URL..."
        git clone --branch "$BRANCH" "$REPO_URL" "$PROJECT_DIR"
        cd "$PROJECT_DIR"
    fi

    # Create necessary subdirectories if missing
    mkdir -p dags scripts data logs plugins prometheus

    # Create symbolic link to persistent data volume
    if [ ! -L "$PROJECT_DIR/data" ]; then
        rm -rf "$PROJECT_DIR/data"
        ln -s "$DATA_DIR" "$PROJECT_DIR/data"
    fi

    log "Application setup complete at $PROJECT_DIR"
}

# -----------------------------------------------------------------------------
# Configure Environment Variables
# -----------------------------------------------------------------------------
configure_environment() {
    log "Configuring environment variables..."

    # Create .env file for Docker Compose
    cat > "$PROJECT_DIR/.env" <<EOF
# Environment Configuration
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
POSTGRES_PASSWORD=$(openssl rand -base64 24)
AIRFLOW_ADMIN_PASSWORD=$(openssl rand -base64 12)
MINIO_ROOT_PASSWORD=$(openssl rand -base64 24)
GRAFANA_ADMIN_PASSWORD=admin
DATA_LAKE_BUCKET=bronze
DELTA_LAKE_PATH=s3a://bronze/
EOF

    # Source the environment file
    set -a
    source "$PROJECT_DIR/.env"
    set +a

    log "Environment configuration complete"
}

# -----------------------------------------------------------------------------
# Pull Docker Images and Start Stack
# -----------------------------------------------------------------------------
start_stack() {
    log "Starting Fintech Data Platform Docker stack..."

    cd "$PROJECT_DIR"

    # Pull all images first (to avoid timeouts)
    log "Pulling Docker images (this may take 5-10 minutes)..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" pull

    # Start the stack
    log "Launching containers..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d

    # Wait for services to be healthy
    log "Waiting for services to become healthy..."
    sleep 30

    # Check status
    docker-compose -f "$DOCKER_COMPOSE_FILE" ps

    log "Stack startup complete"
}

# -----------------------------------------------------------------------------
# Create Health Check Script for Monitoring
# -----------------------------------------------------------------------------
create_health_script() {
    cat > "$PROJECT_DIR/health-check.sh" <<'EOF'
#!/bin/bash
# Health check script for Fintech Data Platform stack

cd /opt/fintech-data-platform
docker-compose ps --format json | jq -r '.[] | select(.Health != "healthy") | .Service' > /tmp/unhealthy.txt

if [ -s /tmp/unhealthy.txt ]; then
    echo "WARNING: Unhealthy services: $(cat /tmp/unhealthy.txt)"
    exit 1
else
    echo "All services healthy"
    exit 0
fi
EOF

    chmod +x "$PROJECT_DIR/health-check.sh"
    log "Health check script created at $PROJECT_DIR/health-check.sh"
}

# -----------------------------------------------------------------------------
# Setup Automatic Backups (Optional)
# -----------------------------------------------------------------------------
setup_backups() {
    log "Setting up automated backups..."

    cat > /etc/cron.daily/fintech-backup <<EOF
#!/bin/bash
# Daily backup of volumes
BACKUP_DIR="/backups/fintech"
mkdir -p \$BACKUP_DIR
docker run --rm -v fintech_minio_data:/data -v \$BACKUP_DIR:/backup alpine tar czf /backup/minio-\$(date +%Y%m%d).tar.gz -C /data .
find \$BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
EOF

    chmod +x /etc/cron.daily/fintech-backup
    log "Backup script configured (daily at 2 AM)"
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
    log "=========================================="
    log "Fintech Data Platform GCP Startup Script Initiated"
    log "=========================================="

    install_docker
    optimize_system
    setup_application
    configure_environment
    create_health_script
    start_stack
    # setup_backups  # Uncomment if backups are desired

    log "=========================================="
    log "Fintech Data Platform stack deployed successfully!"
    log "Access services at:"
    log "  - Airflow: http://$(curl -s ifconfig.me):8083 (admin/password in .env)"
    log "  - Spark Master: http://$(curl -s ifconfig.me):8080"
    log "  - MinIO Console: http://$(curl -s ifconfig.me):9001 (minioadmin/minioadmin)"
    log "  - Grafana: http://$(curl -s ifconfig.me):3000 (admin/admin)"
    log "=========================================="
}

# Run main function
main "$@"