# ==============================================================================
# ECR Repositories
# ==============================================================================
# One repository per container image (Rails and Nginx) - keeps lifecycle
# policies, scanning results, and access control separate per image, which
# is the recommended pattern over bundling multiple app images into one repo.
# ==============================================================================

resource "aws_ecr_repository" "rails_app" {
  name                 = "${var.project_name}-rails-app"
  image_tag_mutability = "IMMUTABLE" # prevents overwriting a tag once pushed - traceability best practice

  image_scanning_configuration {
    scan_on_push = true # automatic vulnerability scanning, matches your Snyk/SonarQube pipeline habits
  }

  tags = {
    Name = "${var.project_name}-rails-app"
  }
}

resource "aws_ecr_repository" "nginx" {
  name                 = "${var.project_name}-nginx"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-nginx"
  }
}

# ==============================================================================
# Lifecycle Policies - automatically expire old untagged images to control
# storage cost, while keeping the last N tagged (deployed) images
# ==============================================================================
resource "aws_ecr_lifecycle_policy" "rails_app" {
  repository = aws_ecr_repository.rails_app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 10 tagged images"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["main-"]
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "nginx" {
  repository = aws_ecr_repository.nginx.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["main-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
