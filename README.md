# fintech-data-platform
A complete FinTech data platform designed to cover batch and streaming ETL, self service analytics, sensitive data and audit compliance and more for use cases such as lending, transactions and fraud detection.

## Project Rationale

Modern data platforms aren't built overnight and are not just about transforming data and loading it into a warehouse. Many factors must be taken into consideration: ensuring the data is accurate and modeled in a sustainable way, that the pipelines can be rerun to backfill historical data, the platform can scale to accomodate an order of magnitude of increased growth (i.e. 10x), and much more.

In this project I will be implementing a full fledged end to end data "fintech" (Financial Technology) data platform, supporting stakeholders such as Data Analysts, Data Scientists, Product Engineers and Compliance Analysts.

**NOTE: All business scenarios and data in this project are synthetic and are solely for the purpose of experimenting and learning.**

## Project Scope and Trajectory

Similar to how real world data systems evolve over time, this project will be built gradually with each stage building on the work of the previous stages.

Because this project uses synthetic data, there will need to be tools built out to help generate the data required for this project. There's no data platforms without data!

## High Level Architecture

Once the data generation functionality is built out, the rest of the platform will follow:
1. Extensible configuration based data ingestion layer
2. Staging data layer for raw, immutable data from source systems
3. Intermediate data layer for cleansed, deduplicated data
4. Business facing data layer with highly optimized tables for analysis and model training
5. Self service tooling layer for dashboarding, feature backfills and more
6. Observability stack encompassing metrics tracking, data lineage, oncall alerting, notifications and compliance logging 

A more detailed design doc can be found [here](docs/design_doc.md). A simplified architecture diagram can be seen below (design doc holds the more in depth architecture diagram):

![BankingBuddy Architecture Simplified](./docs/diagrams/bankingbuddy_architecture_simplified.png)

## High Level Platform Features

- Batch and streaming ETL use case support
- Configuration driven data ingestion from a wide variety of data sources and formats (and onboarding new sources)
- Clear data models that can scale to accommodate future analytical use cases
- Self service tools to allow for faster insights and experimentation
- Implements data auditability, sensitive data access controls and clear data usage distinctions
- Metrics tracking and on-call alerting for platform engineers
- Dashboards for executives and business leaders

## Setup Options

### 1. Local Setup

**Requirements:**
- 4 CPU minimum (8 CPU or more for more cushion) 
- 16GB RAM minimum (24GB RAM or more for more cushion)

If your local machine does not meet these requirements, proceed to the [Cloud Deployment](#2-deploy-to-the-cloud) section below.

#### Spinning Up the Stack

```bash
## Install brew and related packages
sh mac_quickstart.sh

## Start Colima (used for more memory efficient VM management)
colima start --memory 16 --cpu 4

# Create necessary directories
mkdir -p data logs

# Initialize Databases
sudo docker compose up airflow-init -d
sudo docker compose up metabase-init -d

## Start up rest of the fintech data platform stack
docker compose up -d

## Run some test commands to confirm the stack spun up successfully
docker exec -it fintech-data-platform-airflow-scheduler-1 airflow version # Should show 3.2.1

docker exec -it fintech-data-platform-spark-worker-1 spark-submit --version # Should show 4.1.0

docker exec -it fintech-data-platform-spark-master-1 cat /opt/spark/conf/spark-env.sh # Verify RTM is enabled
```

### 2. Deploy to the Cloud 

If you are constrained by memory on your local machine, you will need to deploy this stack remotely onto a machine with more compute power.

The classic option is the cloud, and both AWS and GCP are demonstrated below.

#### 2.1 AWS

Follow these instructions to set up an AWS account. Then when ready:

1. Upload the script to S3 either via the console or the AWS CLI as such:

```bash
aws s3 cp scripts/cloud/aws_user_data_script.sh s3://your-bucket-name/scripts
```

2. Launch an EC2 instance with the following configurations:
    - AMI: `Ubuntu Server 24.04 LTS`
        - Architecture: `x86`
    - Instance Type: `t3.2xlarge`
        - 8 vCPUs / 32 GiB RAM to run the full stack comfortably
        - 4 vCPUs / 24 GiB RAM would be enough to run the full stack
    - Create a new key pair for SSH access (make sure the .pem file downloads to your local machine)
    - Create a new security group for the EC2 instance
        - Configure access from your IP ("My IP")
    - Configure 24 GB gp3 storage (free tier eligible)
    - In the Advanced Details section, paste this into the User data text box:
```bash
Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -e -x
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "===== Starting AWS CLI installation at $(date) ====="

# Update and install prerequisites
apt-get update -y
apt-get install -y curl unzip

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp/
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# Verify installation
aws --version

# Download your script from S3 (REPLACE THIS WITH YOUR ACTUAL S3 PATH)
aws s3 cp s3://your-bucket-name/aws_user_data_script.sh /tmp/aws_user_data_script.sh

# Make it executable and run
chmod +x /tmp/aws_user_data_script.sh
/tmp/aws_user_data_script.sh

echo "===== AWS CLI setup complete at $(date) ====="

--==BOUNDARY==--
```

3. Configure Security Group to allow ports 8080, 8083, 3000, 9000, 9001 for your stack

4. After a few minutes, SSH onto your instance to confirm everything has been set up properly:

a. Open a terminal
b. Run this command, if necessary, to ensure your key is not publicly viewable: `chmod 400 "YOUR-KEY-PAIR.pem"`
c. Connect to your instance using its Public DNS:
- Example instance name: `ec2-32-198-81-130.compute-1.amazonaws.com`
- Example ssh command:
`ssh -i "YOUR-KEY-PAIR.pem" ubuntu@ec2-32-198-81-130.compute-1.amazonaws.com`
```

5. While on your instance, after a few minutes check the status of each of the services:

```bash
sudo docker compose ps # Show each container and their status

sudo docker exec -it fintech-data-platform-airflow-scheduler-1 airflow version # Should show 3.2.1

sudo docker exec -it fintech-data-platform-spark-worker-1 spark-submit --version # Should show 4.1.0

sudo docker exec -it fintech-data-platform-spark-master-1 cat /opt/spark/conf/spark-env.sh # Verify RTM is enabled
```

#### 2.2 GCP

INSERT INSTRUCTIONS


### Generating User Data

You can use the script `scripts/generate_mock_data.py` to generate the required data for the fintech data platform:

```bash
### Generate User Data for 10000 Users (default)
### Users, Statements, Payments, Transactions, Loan Applications
pipenv run scripts/generate_mock_data.py

### Generate User Data for 100000 Users
### Users, Statements, Payments, Transactions, Loan Applications
pipenv run scripts/generate_mock_data.py --users 100000

### Generate Streaming Data (default: 1000 events)
pipenv run scripts/generate_mock_data.py --stream

### Generate 100000 Streaming Events
pipenv run scripts/generate_mock_data.py --stream --stream-count 100000
```