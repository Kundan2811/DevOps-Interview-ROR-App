# ==============================================================================
# Bootstrap: Terraform Remote State Backend
# ==============================================================================
# This creates the S3 bucket + DynamoDB table used by the MAIN infrastructure's
# Terraform state. It must be applied ONCE, separately, before the main
# infrastructure is initialized - since a backend can't create itself.
#
# Usage:
#   cd infrastructure/bootstrap
#   terraform init
#   terraform apply
#
# After this succeeds, note the bucket name in the output and use it in
# infrastructure/backend.tf
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region for the backend resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as a prefix for backend resource names"
  type        = string
  default     = "ror-devops-assignment"
}

# --------------------------------------------------------------------------
# S3 bucket to store Terraform state files
# --------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  # Bucket names must be globally unique across ALL of AWS, so we append
  # the account ID to avoid collisions with other users of this same code.
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental deletion of this bucket via terraform destroy,
  # since it holds the state for everything else.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "${var.project_name}-tfstate"
    Purpose = "Terraform remote state storage"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --------------------------------------------------------------------------
# DynamoDB table for state locking
# --------------------------------------------------------------------------
# Prevents two people (or two CI runs) from running terraform apply at the
# same time and corrupting the state file.
# --------------------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-tfstate-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "${var.project_name}-tfstate-locks"
    Purpose = "Terraform state locking"
  }
}

# --------------------------------------------------------------------------
# Outputs - you'll need these values for infrastructure/backend.tf
# --------------------------------------------------------------------------
output "state_bucket_name" {
  description = "Name of the S3 bucket created for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table created for state locking"
  value       = aws_dynamodb_table.terraform_locks.id
}
