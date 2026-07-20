# ==============================================================================
# Secrets Manager - stores DB credentials so they can be injected into the
# ECS task definition as secrets (not plaintext environment variables).
# The task execution role (see iam.tf) is granted read-only access to this
# specific secret ARN only.
# ==============================================================================
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-db-credentials"
  description = "Postgres RDS master credentials for the Rails app"

  tags = {
    Name = "${var.project_name}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    RDS_HOSTNAME = aws_db_instance.main.address
    RDS_PORT     = tostring(aws_db_instance.main.port)
    RDS_DB_NAME  = var.db_name
    RDS_USERNAME = var.db_username
    RDS_PASSWORD = random_password.db_password.result
  })
}
