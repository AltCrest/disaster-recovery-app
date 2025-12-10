# terraform/alb.tf

# ===================================================================
# --- Primary Region (us-east-1) ---
# ===================================================================

# --- Primary Application Load Balancer ---
resource "aws_lb" "app_alb" {
  provider           = aws.primary
  name               = "primary-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg_primary.id]
  subnets            = [aws_subnet.primary_public_a.id, aws_subnet.primary_public_b.id]

  tags = {
    Name = "primary-app-lb"
  }
}

# --- Target Group for the Frontend (Nginx on port 80) ---
resource "aws_lb_target_group" "app_tg_frontend" {
  provider = aws.primary
  name     = "app-tg-frontend"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.primary.id
  
  health_check {
    path = "/" # Check the root path for a 200 OK response
  }
}

# --- Target Group for the Backend (Flask/Gunicorn on port 5000) ---
resource "aws_lb_target_group" "app_tg_backend" {
  provider = aws.primary
  name     = "app-tg-backend"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.primary.id

  health_check {
    path = "/" # Check the "Hello World" route for a 200 OK response
  }
}

# --- Main Listener on Port 80 ---
# This listens for all incoming web traffic.
resource "aws_lb_listener" "app_listener" {
  provider          = aws.primary
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  # The DEFAULT action is to send all traffic to the frontend.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg_frontend.arn
  }
}

# --- Listener Rule for the API ---
# This rule creates an exception: IF the path is /api/*, send it to the backend instead.
resource "aws_lb_listener_rule" "api_rule" {
  provider     = aws.primary
  listener_arn = aws_lb_listener.app_listener.arn
  priority     = 100 # A lower number gives it higher priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg_backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}


# ===================================================================
# --- Disaster Recovery Region (us-west-2) ---
# We create a parallel setup in the DR region.
# ===================================================================

# --- DR Application Load Balancer ---
resource "aws_lb" "app_alb_dr" {
  provider           = aws.dr
  name               = "dr-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg_dr.id] # Assumes this exists in iam.tf
  subnets            = [aws_subnet.dr_public_a.id, aws_subnet.dr_public_b.id]

  tags = {
    Name = "dr-app-lb"
  }
}

# --- Target Group for the DR Frontend ---
resource "aws_lb_target_group" "app_tg_frontend_dr" {
  provider = aws.dr
  name     = "app-tg-frontend-dr"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.dr.id
  
  health_check {
    path = "/"
  }
}

# --- Target Group for the DR Backend ---
resource "aws_lb_target_group" "app_tg_backend_dr" {
  provider = aws.dr
  name     = "app-tg-backend-dr"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.dr.id

  health_check {
    path = "/"
  }
}

# --- Main Listener for the DR ALB ---
resource "aws_lb_listener" "app_listener_dr" {
  provider          = aws.dr
  load_balancer_arn = aws_lb.app_alb_dr.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg_frontend_dr.arn
  }
}

# --- Listener Rule for the DR API ---
resource "aws_lb_listener_rule" "api_rule_dr" {
  provider     = aws.dr
  listener_arn = aws_lb_listener.app_listener_dr.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg_backend_dr.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}