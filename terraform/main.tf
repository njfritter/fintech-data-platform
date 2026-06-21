# -----------------------------------------------------------------------------
# VPC and Networking
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-vpc"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 4)
  availability_zone = var.availability_zones[count.index]
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-private-${count.index + 1}"
    Type = "Private"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-public-${count.index + 1}"
    Type = "Public"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-nat"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-nat-eip"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
resource "aws_security_group" "fintech-data-platform" {
  name        = "fintech-data-platform-${var.environment}-sg"
  description = "Security group for fintech data platform"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }
  
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Spark Master UI"
  }
  
  ingress {
    from_port   = 8083
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Airflow UI"
  }
  
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Grafana"
  }
  
  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Metabase"
  }
  
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "MinIO API"
  }
  
  ingress {
    from_port   = 9001
    to_port     = 9001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "MinIO Console"
  }
  
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Prometheus"
  }
  
  # Intra-cluster communication (allow all internal traffic)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-sg"
  }
}

# -----------------------------------------------------------------------------
# IAM Roles and Policies
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ec2_role" {
  name = "fintech-data-platform-${var.environment}-ec2-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "fintech-data-platform-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_s3" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "ec2_ecr" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# -----------------------------------------------------------------------------
# Launch Template for EC2 Instances
# -----------------------------------------------------------------------------
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "random_password" "airflow_admin" {
  length  = 16
  special = false
}

resource "aws_launch_template" "fintech-data-platform" {
  name_prefix   = "fintech-data-platform-${var.environment}-"
  image_id      = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type = var.ec2_instance_type
  
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
  
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.fintech-data-platform.id]
  }
  
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 200
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    environment    = var.environment
    github_repo    = var.github_repo_url
    github_branch  = var.github_branch
    admin_password = random_password.airflow_admin.result
  }))
  
  monitoring {
    enabled = true
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "fintech-data-platform-${var.environment}-instance"
      AutoStop    = "true"
      Environment = var.environment
    }
  }
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-launch-template"
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group
# -----------------------------------------------------------------------------
resource "aws_autoscaling_group" "fintech-data-platform" {
  name                = "fintech-data-platform-${var.environment}-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = []  # Add ALB target group ARN if using load balancer
  health_check_type   = "EC2"
  health_check_grace_period = 300
  
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity
  
  launch_template {
    id      = aws_launch_template.fintech-data-platform.id
    version = "$Latest"
  }
  
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }
  
  termination_policies = ["OldestInstance", "Default"]
  
  tag {
    key                 = "Name"
    value               = "fintech-data-platform-${var.environment}-asg-instance"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "AutoStop"
    value               = "true"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
  
  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Policies (CPU-based scaling)
# -----------------------------------------------------------------------------
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "fintech-data-platform-${var.environment}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.fintech-data-platform.name
}

resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name          = "fintech-data-platform-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.scale_up_cpu_threshold
  alarm_description   = "Scale up when CPU exceeds threshold"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.fintech-data-platform.name
  }
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "fintech-data-platform-${var.environment}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 600  # Longer cooldown to avoid oscillation
  autoscaling_group_name = aws_autoscaling_group.fintech-data-platform.name
}

resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  alarm_name          = "fintech-data-platform-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.scale_down_cpu_threshold
  alarm_description   = "Scale down when CPU drops below threshold"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.fintech-data-platform.name
  }
}

# -----------------------------------------------------------------------------
# MSK (Kafka) for Streaming - Serverless for high throughput
# -----------------------------------------------------------------------------
resource "aws_msk_cluster" "fintech-data-platform" {
  cluster_name           = "fintech-data-platform-${var.environment}"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = var.kafka_broker_count
  
  broker_node_group_info {
    instance_type = var.kafka_instance_type
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.fintech-data-platform.id]
    
    storage_info {
      ebs_storage_info {
        volume_size = 1000
      }
    }
  }
  
  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }
  
  client_authentication {
    sasl {
      iam = true
    }
  }
  
  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_broker.name
      }
    }
  }
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-msk"
  }
}

resource "aws_kms_key" "msk" {
  description             = "KMS key for MSK encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_cloudwatch_log_group" "msk_broker" {
  name              = "/aws/msk/fintech-data-platform-${var.environment}/broker"
  retention_in_days = 30
}

# -----------------------------------------------------------------------------
# EMR Serverless for Spark Processing (High-volume data processing)
# -----------------------------------------------------------------------------
resource "aws_emrserverless_application" "spark" {
  name          = "fintech-data-platform-${var.environment}-spark"
  release_label = var.emr_release_label
  type          = "SPARK"
  
  initial_capacity {
    initial_capacity_type = "Driver"
    initial_capacity_config {
        worker_count = 1
        worker_configuration {
        cpu    = "4 vCPU"
        memory = "16 GB"
        }
    }
  }
  
  maximum_capacity {
    cpu    = "64 vCPU"
    memory = "256 GB"
  }
  
  auto_start_configuration {
    enabled = true
  }
  
  auto_stop_configuration {
    enabled = true
    idle_timeout_minutes    = 15  # minutes of inactivity before auto-stop
  }
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-emr-serverless"
  }
}

# -----------------------------------------------------------------------------
# S3 Buckets for Data Lake
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "data_lake" {
  bucket = "fintech-data-platform-${var.environment}-datalake-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Name = "Fintech Data Platform Data Lake"
  }
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  
  rule {
    id     = "transition-to-glacier"
    status = "Enabled"
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
  
  rule {
    id     = "delete-old-logs"
    status = "Enabled"
    
    expiration {
      days = 365
    }
    
    filter {
      prefix = "logs/"
    }
  }
}

resource "aws_s3_bucket" "emr_logs" {
  bucket = "fintech-data-platform-${var.environment}-emr-logs-${data.aws_caller_identity.current.account_id}"
}

# -----------------------------------------------------------------------------
# RDS Aurora for Metadata (High-performance, scalable)
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "aurora" {
  name        = "fintech-data-platform-${var.environment}-aurora-subnet"
  description = "Subnet group for Aurora cluster"
  subnet_ids  = aws_subnet.private[*].id
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "fintech-data-platform-${var.environment}-aurora"
  engine             = "aurora-mysql"
  engine_version     = "8.0.mysql_aurora.3.04.0"
  
  database_name           = "airflow"
  master_username         = "admin"
  master_password         = random_password.rds_master.result
  backup_retention_period = 30
  preferred_backup_window = "03:00-05:00"
  
  vpc_security_group_ids = [aws_security_group.fintech-data-platform.id]
  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  
  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 16
  }
  
  skip_final_snapshot = var.environment != "prod"
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-aurora"
  }
}

resource "random_password" "rds_master" {
  length  = 24
  special = false
}

resource "aws_rds_cluster_instance" "aurora_writer" {
  cluster_identifier = aws_rds_cluster.aurora.id
  identifier         = "fintech-data-platform-${var.environment}-aurora-writer"
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  publicly_accessible = false
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-aurora-writer"
  }
}

resource "aws_rds_cluster_instance" "aurora_reader" {
  cluster_identifier = aws_rds_cluster.aurora.id
  identifier         = "fintech-data-platform-${var.environment}-aurora-reader"
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  publicly_accessible = false
  
  tags = {
    Name = "fintech-data-platform-${var.environment}-aurora-reader"
  }
}

# -----------------------------------------------------------------------------
# Lambda Functions for Scheduled Start/Stop (Cost Optimization)
# -----------------------------------------------------------------------------
data "archive_file" "lambda_start" {
  type        = "zip"
  output_path = "${path.module}/lambda/start_package.zip"
  source {
    filename = "lambda_function.py"
    content  = file("${path.module}/lambda/start_instances.py")
  }
}

data "archive_file" "lambda_stop" {
  type        = "zip"
  output_path = "${path.module}/lambda/stop_package.zip"
  source {
    filename = "lambda_function.py"
    content  = file("${path.module}/lambda/stop_instances.py")
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "fintech-data-platform-${var.environment}-lambda-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_ec2" {
  name = "fintech-data-platform-${var.environment}-lambda-ec2-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:UpdateAutoScalingGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ec2" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_ec2.arn
}

resource "aws_lambda_function" "start_instances" {
  filename         = data.archive_file.lambda_start.output_path
  function_name    = "fintech-data-platform-${var.environment}-start-instances"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 256
  
  environment {
    variables = {
      ASG_NAME = aws_autoscaling_group.fintech-data-platform.name
      REGION   = var.aws_region
    }
  }
  
  tags = {
    Name = "fintech-data-platform-start-instances"
  }
}

resource "aws_lambda_function" "stop_instances" {
  filename         = data.archive_file.lambda_stop.output_path
  function_name    = "fintech-data-platform-${var.environment}-stop-instances"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 256
  
  environment {
    variables = {
      ASG_NAME = aws_autoscaling_group.fintech-data-platform.name
      REGION   = var.aws_region
    }
  }
  
  tags = {
    Name = "fintech-data-platform-stop-instances"
  }
}

# -----------------------------------------------------------------------------
# EventBridge Rules for Scheduled Start/Stop
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "start_schedule" {
  name                = "fintech-data-platform-${var.environment}-start-schedule"
  description         = "Schedule to start Fintech Data Platform instances"
  schedule_expression = var.start_schedule
}

resource "aws_cloudwatch_event_rule" "stop_schedule" {
  name                = "fintech-data-platform-${var.environment}-stop-schedule"
  description         = "Schedule to stop Fintech Data Platform instances"
  schedule_expression = var.stop_schedule
}

resource "aws_cloudwatch_event_target" "start_target" {
  rule      = aws_cloudwatch_event_rule.start_schedule.name
  target_id = "StartInstances"
  arn       = aws_lambda_function.start_instances.arn
}

resource "aws_cloudwatch_event_target" "stop_target" {
  rule      = aws_cloudwatch_event_rule.stop_schedule.name
  target_id = "StopInstances"
  arn       = aws_lambda_function.stop_instances.arn
}

resource "aws_lambda_permission" "allow_start_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_instances.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_schedule.arn
}

resource "aws_lambda_permission" "allow_stop_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_instances.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_schedule.arn
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# CloudWatch Dashboard
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "fintech-data-platform" {
  dashboard_name = "fintech-data-platform-${var.environment}-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average" }],
            ["AWS/EC2", "MemoryUtilization", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EC2 Instance Metrics"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Kafka", "BytesInPerSec", { stat = "Sum" }],
            ["AWS/Kafka", "BytesOutPerSec", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "MSK Throughput"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EMRServerless", "RunningJobs", { stat = "Sum" }],
            ["AWS/EMRServerless", "MemoryAllocatedMB", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EMR Serverless Metrics"
        }
      }
    ]
  })
}