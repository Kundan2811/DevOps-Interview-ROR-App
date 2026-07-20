output "alb_dns_name" {
  description = "Public DNS name of the ALB - open this in a browser to access the app"
  value       = aws_lb.main.dns_name
}

output "ecr_rails_app_repository_url" {
  description = "ECR repository URL for the Rails image - used by CI/CD to push builds"
  value       = aws_ecr_repository.rails_app.repository_url
}

output "ecr_nginx_repository_url" {
  description = "ECR repository URL for the Nginx image - used by CI/CD to push builds"
  value       = aws_ecr_repository.nginx.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service - used by CI/CD to trigger new deployments"
  value       = aws_ecs_service.app.name
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket used for app storage"
  value       = aws_s3_bucket.app_storage.bucket
}

output "rds_endpoint" {
  description = "RDS Postgres endpoint (private - only reachable from within the VPC)"
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}
