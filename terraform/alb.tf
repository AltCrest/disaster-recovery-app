# --- Primary Region ALB ---

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

resource "aws_lb_target_group" "app_tg" {
  provider = aws.primary
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.primary.id
}

resource "aws_lb_listener" "app_listener" {
  provider          = aws.primary
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}


# --- DR Region ALB ---

resource "aws_lb" "app_alb_dr" {
  provider           = aws.dr
  name               = "dr-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg_dr.id]
  subnets            = [aws_subnet.dr_public_a.id, aws_subnet.dr_public_b.id]

  tags = {
    Name = "dr-app-lb"
  }
}

resource "aws_lb_target_group" "app_tg_dr" {
  provider = aws.dr
  name     = "app-tg-dr"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.dr.id
}

resource "aws_lb_listener" "app_listener_dr" {
  provider          = aws.dr
  load_balancer_arn = aws_lb.app_alb_dr.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg_dr.arn
  }
}