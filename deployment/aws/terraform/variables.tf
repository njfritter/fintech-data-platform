variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "ec2_instance_type" {
  description = "EC2 instance type for the data platform"
  type        = string
  default     = "r6i.2xlarge"  # 8 vCPU, 64 GB RAM - optimized for memory-intensive workloads
}

variable "asg_min_size" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 2
}

variable "scale_up_cpu_threshold" {
  description = "CPU utilization percentage to trigger scale up"
  type        = number
  default     = 70
}

variable "scale_down_cpu_threshold" {
  description = "CPU utilization percentage to trigger scale down"
  type        = number
  default     = 30
}

variable "start_schedule" {
  description = "Cron schedule for starting instances (UTC)"
  type        = string
  default     = "cron(0 9 ? * MON-FRI *)"  # 9 AM UTC (~5 AM US Eastern)
}

variable "stop_schedule" {
  description = "Cron schedule for stopping instances (UTC)"
  type        = string
  default     = "cron(0 1 ? * MON-FRI *)"  # 1 AM UTC (~9 PM US Eastern)
}

variable "kafka_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.m5.large"
}

variable "kafka_broker_count" {
  description = "Number of Kafka brokers"
  type        = number
  default     = 3
}

variable "emr_release_label" {
  description = "EMR release label for Spark processing"
  type        = string
  default     = "emr-7.0.0"
}

variable "github_repo_url" {
  description = "GitHub repository URL for Fintech Data Platform code"
  type        = string
  default     = "https://github.com/your-username/fintech-data-platform.git"
}

variable "github_branch" {
  description = "Git branch to deploy"
  type        = string
  default     = "main"
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}