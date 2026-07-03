terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  
  backend "s3" {
    # Configure your backend here or use -backend-config
    key            = "fintech-data-platform/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "Fintech Data Platform"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = "DataPlatform"
    }
  }
}