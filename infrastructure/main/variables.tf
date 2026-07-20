# ==============================================================================
# General
# ==============================================================================
variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag all resources"
  type        = string
  default     = "devops-assignment"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "dev"
}

# ==============================================================================
# Networking
# ==============================================================================
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to spread subnets across (2 is enough for HA without excess NAT Gateway cost)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ) - hosts the ALB only"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ) - hosts ECS tasks and RDS"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ==============================================================================
# Database
# ==============================================================================
variable "db_name" {
  description = "Postgres database name"
  type        = string
  default     = "rails"
}

variable "db_username" {
  description = "Postgres master username"
  type        = string
  default     = "postgres"
}

variable "db_instance_class" {
  description = "RDS instance class (db.t3.micro is free-tier eligible)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "Postgres engine version (13.23 is the latest RDS-supported patch of major version 13, matching the docker-compose.yml's postgres:13.3 image)"
  type        = string
  default     = "13.23"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20
}

# ==============================================================================
# ECS / Containers
# ==============================================================================
variable "rails_container_port" {
  description = "Port the Rails container listens on"
  type        = number
  default     = 3000
}

variable "nginx_container_port" {
  description = "Port the Nginx container listens on"
  type        = number
  default     = 80
}

variable "ecs_task_cpu" {
  description = "Fargate task-level CPU units (256 = 0.25 vCPU)"
  type        = string
  default     = "1024"
}

variable "ecs_task_memory" {
  description = "Fargate task-level memory in MB"
  type        = string
  default     = "3072"
}

variable "ecs_desired_count" {
  description = "Baseline number of running tasks (>=2 for availability across AZs)"
  type        = number
  default     = 2
}

variable "ecs_min_capacity" {
  description = "Minimum tasks for autoscaling"
  type        = number
  default     = 2
}

variable "ecs_max_capacity" {
  description = "Maximum tasks for autoscaling"
  type        = number
  default     = 4
}

# ==============================================================================
# Container Images
# ==============================================================================
# These default to :latest so `terraform apply` works before any image has
# been pushed, but in practice CI/CD should pass the specific git-SHA tag via
# -var so deployments are traceable and reproducible.
# ==============================================================================
variable "rails_image_tag" {
  description = "Tag of the Rails image in ECR to deploy"
  type        = string
  default     = "latest"
}

variable "nginx_image_tag" {
  description = "Tag of the Nginx image in ECR to deploy"
  type        = string
  default     = "latest"
}
