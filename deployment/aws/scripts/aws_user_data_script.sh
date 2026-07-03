#!/bin/bash
# =============================================================================
# Fintech Data Platform - AWS EC2 User Data Script
# Version: 1.0 (AWS Adapted)
# Purpose: One-time setup of Fintech Data Platform stack on EC2 launch
# Compatible with: Ubuntu 24.04 LTS (same as GCP version)
# =============================================================================

set -e -x  # Exit on error, print every command
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# -----------------------------------------------------------------------------
# Configuration Variables (Customize these as needed)
# -----------------------------------------------------------------------------
REPO_URL="https://github.com/your-username/fintech-data-platform.git"
BRANCH="main"
PROJECT_DIR="/home/ubuntu/fintech-data-platform"
LOG_FILE="/var/log/fintech-user-data.log"
LOG_DIR="/home/ubuntu/fintech-data-platform/logs"
DATA_DIR="/home/ubuntu/fintech-data-platform/data"
# -----------------------------------------------------------------------------
# Logging Function
# -----------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
    log "=========================================="
    log "Fintech Data Platform AWS EC2 User Data Script Started"
    log "=========================================="

    # -------------------------------------------------------------------------
    # Phase 1: Update System & Install Prerequisites
    # -------------------------------------------------------------------------
    log "Phase 1: Updating system and installing prerequisites..."
    apt-get update -y
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        git \
        htop \
        jq

    # -------------------------------------------------------------------------
    # Phase 2: Install Docker (Official Method)
    # -------------------------------------------------------------------------
    log "Phase 2: Installing Docker from official repository..."

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker's official repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine, CLI, and Compose Plugin
    apt-get update -y
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    # Start Docker and enable on boot
    systemctl start docker
    systemctl enable docker

    log "Docker version: $(docker --version)"
    log "Docker Compose version: $(docker compose version)"

    # -------------------------------------------------------------------------
    # Phase 3: Clone Repository
    # -------------------------------------------------------------------------
    log "Phase 3: Cloning Fintech Data Platform repository..."

    cd /home/ubuntu
    if [ -d "$PROJECT_DIR" ]; then
        log "Repository already exists, pulling latest changes..."
        cd "$PROJECT_DIR"
        sudo -u ubuntu git pull origin "$BRANCH"
    else
        log "Cloning repository from $REPO_URL..."
        sudo -u ubuntu git clone --branch "$BRANCH" "$REPO_URL" "$PROJECT_DIR"
        cd "$PROJECT_DIR"
    fi

    # Create necessary directories
    mkdir -p "$DATA_DIR" "$LOG_DIR"

    # -------------------------------------------------------------------------
    # Phase 4: Initialize Databases
    # -------------------------------------------------------------------------
    log "Phase 4: Starting Airflow, Postgres, Redis and Metabase Containers..."

    sudo docker compose up airflow-init -d
    sudo docker compose up metabase-init -d

    # -------------------------------------------------------------------------
    # Phase 5: Start Docker Stack
    # -------------------------------------------------------------------------
    log "Phase 5: Starting remaining Fintech Data Platform Docker stack..."

    sudo docker compose up -d

    # -------------------------------------------------------------------------
    # Phase 6: Health Check
    # -------------------------------------------------------------------------
    log "Phase 5: Verifying stack health..."
    sleep 10
    sudo docker compose ps

    # -------------------------------------------------------------------------
    # Phase 7: Print Access Information
    # -------------------------------------------------------------------------
    log "=========================================="
    log "Fintech Data Platform stack deployed successfully!"
    log "=========================================="
    log "Access services at:"
    log "  - Airflow: http://$(curl -s ifconfig.me):8083 (admin/admin)"
    log "  - Spark Master: http://$(curl -s ifconfig.me):8080"
    log "  - MinIO Console: http://$(curl -s ifconfig.me):9001 (minioadmin/minioadmin)"
    log "  - Grafana: http://$(curl -s ifconfig.me):3000 (admin/admin)"
    log "  - Metabase: http://$(curl -s ifconfig.me):3001"
    log "=========================================="
    log "Fintech Data Platform setup completed at $(date)"
}

# Run the main function
main "$@"