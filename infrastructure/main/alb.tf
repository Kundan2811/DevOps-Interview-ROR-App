# ==============================================================================
# Application Load Balancer - the ONLY internet-facing resource in this stack
# ==============================================================================
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Protects against a common cost/security footgun where an idle ALB
  # is accidentally deleted; can be set to true post-assignment.
  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# ==============================================================================
# Target Group - the ECS service registers its running tasks here
# ==============================================================================
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.nginx_container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # required for Fargate (vs. "instance" for EC2 launch type)

  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

# ==============================================================================
# Listener - accepts HTTP on port 80 and forwards to the target group
# ==============================================================================
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
