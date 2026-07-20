# ==============================================================================
# ECS Task Execution Role
# ==============================================================================
# Used by the ECS agent itself (not your app code) to: pull images from ECR,
# write logs to CloudWatch, and fetch secrets from Secrets Manager to inject
# into the container at startup.
# ==============================================================================
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.project_name}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Grants the execution role permission to read the specific DB credentials
# secret, so it can inject it into the container as an env var at launch.
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.project_name}-ecs-exec-secrets-access"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.db_credentials.arn]
      }
    ]
  })
}

# ==============================================================================
# ECS Task Role
# ==============================================================================
# Used by the application code itself (inside the Rails container) to talk to
# AWS services at runtime. This is the role that satisfies the assignment's
# requirement: "integrate with S3 using IAM role authentication, not
# AccessKey/SecretKey".
# ==============================================================================
resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

# Scoped S3 policy - read/write access ONLY to this app's specific bucket,
# not all S3 buckets in the account (least-privilege).
resource "aws_iam_role_policy" "ecs_task_s3_access" {
  name = "${var.project_name}-ecs-task-s3-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.app_storage.arn]
      },
      {
        Sid    = "ReadWriteObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = ["${aws_s3_bucket.app_storage.arn}/*"]
      }
    ]
  })
}
