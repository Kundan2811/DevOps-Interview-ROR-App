# ==============================================================================
# ECS Cluster
# ==============================================================================
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled" # gives CPU/memory/network metrics per service in CloudWatch
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# ==============================================================================
# CloudWatch Log Group - both containers ship logs here
# ==============================================================================
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-ecs-logs"
  }
}

# ==============================================================================
# ECS Task Definition - both containers (rails_app + nginx) in one task,
# matching the docker-compose.yml pairing used locally
# ==============================================================================
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # required for Fargate
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "rails_app"
      image     = "${aws_ecr_repository.rails_app.repository_url}:${var.rails_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.rails_container_port
          protocol      = "tcp"
        }
      ]

      # Plain (non-secret) environment variables
      environment = [
        { name = "S3_BUCKET_NAME", value = aws_s3_bucket.app_storage.bucket },
        { name = "S3_REGION_NAME", value = var.aws_region },
        { name = "LB_ENDPOINT", value = aws_lb.main.dns_name }
      ]

      # Secrets pulled from Secrets Manager at container startup - never
      # appear in plaintext in the task definition or console
      secrets = [
        { name = "RDS_HOSTNAME", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:RDS_HOSTNAME::" },
        { name = "RDS_PORT", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:RDS_PORT::" },
        { name = "RDS_DB_NAME", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:RDS_DB_NAME::" },
        { name = "RDS_USERNAME", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:RDS_USERNAME::" },
        { name = "RDS_PASSWORD", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:RDS_PASSWORD::" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "rails"
        }
      }
    },
    {
      name      = "nginx"
      image     = "${aws_ecr_repository.nginx.repository_url}:${var.nginx_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.nginx_container_port
          protocol      = "tcp"
        }
      ]

      # nginx.conf proxies to "rails_app:3000" - within a single Fargate task,
      # containers share a network namespace and reach each other via
      # localhost, but ECS also supports the container-name DNS alias used
      # here (matching the same config file used in docker-compose.yml
      # locally, so no nginx config changes were needed for this deployment).
      dependsOn = [
        { containerName = "rails_app", condition = "START" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "nginx"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-task"
  }
}

# ==============================================================================
# ECS Service - keeps the desired number of tasks running, registered behind
# the ALB, spread across the private subnets/AZs
# ==============================================================================
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false # tasks live in private subnets, reach internet only via NAT
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "nginx"
    container_port   = var.nginx_container_port
  }

  # Ensures the ALB listener exists before ECS tries to register targets
  depends_on = [aws_lb_listener.http]

  tags = {
    Name = "${var.project_name}-service"
  }
}

# ==============================================================================
# Auto Scaling - scales task count based on CPU utilization
# ==============================================================================
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
