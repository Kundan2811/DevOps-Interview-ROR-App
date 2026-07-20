# ==============================================================================
# RDS Subnet Group - tells RDS which (private) subnets it's allowed to launch in
# ==============================================================================
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ==============================================================================
# Random password for the DB master user - generated once, stored in
# Secrets Manager (see secrets.tf), never hardcoded or committed to git
# ==============================================================================
resource "random_password" "db_password" {
  length  = 24
  special = false # avoids characters that can break connection strings / URL-encoding issues
}

# ==============================================================================
# RDS Postgres Instance
# ==============================================================================
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  storage_type           = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Not reachable from the public internet under any circumstance
  publicly_accessible = false

  # Backups + maintenance - reasonable defaults for a dev/assignment environment
  # NOTE: backup_retention_period capped at 1 day here to stay within AWS
  # Free Tier limits; a paid account could safely use 7+ days in production.
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window       = "mon:04:30-mon:05:30"

  # Set to true for a real assignment submission so the DB isn't accidentally
  # destroyed; set to false only if you need fast iteration and don't mind
  # losing data on `terraform destroy`.
  deletion_protection = false
  skip_final_snapshot = true # simplifies teardown for this assignment; a production DB would set this false

  tags = {
    Name = "${var.project_name}-postgres"
  }
}
