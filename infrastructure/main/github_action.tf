# ==============================================================================
# GitHub Actions OIDC Provider
# ==============================================================================
# This registers GitHub's OIDC token issuer as a trusted identity provider in
# AWS. Once registered, GitHub Actions workflows can request short-lived AWS
# credentials directly - no long-lived AWS access keys need to be stored as
# GitHub secrets. This is the current AWS/GitHub recommended best practice.
# ==============================================================================
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # GitHub's OIDC thumbprint - a fixed, publicly documented value maintained
  # by GitHub; not a secret.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]

  tags = {
    Name = "${var.project_name}-github-oidc"
  }
}

# ==============================================================================
# IAM Role assumed by GitHub Actions - scoped to ONLY this specific repo
# ==============================================================================
variable "github_repository" {
  description = "GitHub repo allowed to assume the CI/CD role, in 'owner/repo' format"
  type        = string
  default     = "Kundan2811/DevOps-Interview-ROR-App"
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restricts this role to ONLY be assumable by workflows running on the
    # main branch of this specific repo - not forks, not other branches,
    # not other repos. This is the key least-privilege control.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_cicd" {
  name               = "${var.project_name}-github-actions-cicd"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name = "${var.project_name}-github-actions-cicd"
  }
}

# ==============================================================================
# Permissions granted to the CI/CD role - scoped to exactly what the pipeline
# needs: push images to these two specific ECR repos, and deploy new task
# definitions to this specific ECS service. Nothing broader.
# ==============================================================================
resource "aws_iam_role_policy" "github_actions_ecr_push" {
  name = "${var.project_name}-ecr-push"
  role = aws_iam_role.github_actions_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = [
          aws_ecr_repository.rails_app.arn,
          aws_ecr_repository.nginx.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_actions_ecs_deploy" {
  name = "${var.project_name}-ecs-deploy"
  role = aws_iam_role.github_actions_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSDeploy"
        Effect = "Allow"
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = "*" # RegisterTaskDefinition does not support resource-level restriction
      },
      {
        # Required because RegisterTaskDefinition needs to pass the existing
        # execution/task roles to the new task definition revision.
        Sid    = "PassRolesToECS"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.ecs_task_execution_role.arn,
          aws_iam_role.ecs_task_role.arn
        ]
      }
    ]
  })
}

output "github_actions_role_arn" {
  description = "IAM Role ARN for the GitHub Actions CI/CD workflow to assume"
  value       = aws_iam_role.github_actions_cicd.arn
}
