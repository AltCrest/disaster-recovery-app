# terraform/codedeploy.tf

# --- IAM Role for CodeDeploy Service ---
# CodeDeploy needs permission to interact with EC2 and other services.
resource "aws_iam_role" "codedeploy_service_role" {
  provider = aws.primary
  name     = "CodeDeployServiceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "codedeploy.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_service_policy" {
  provider   = aws.primary
  role       = aws_iam_role.codedeploy_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}


# --- Backend CodeDeploy Application ---
resource "aws_codedeploy_app" "backend_app" {
  provider        = aws.primary
  compute_platform = "Server"
  name             = "App-Backend" # This name MUST match your GitHub Actions workflow
}

resource "aws_codedeploy_deployment_group" "backend_dg" {
  provider           = aws.primary
  app_name           = aws_codedeploy_app.backend_app.name
  deployment_group_name = "Backend-Servers-Group" # This name MUST match
  service_role_arn   = aws_iam_role.codedeploy_service_role.arn

  ec2_tag_filter {
    key   = "Name"
    type  = "KEY_AND_VALUE"
    value = "Backend-Server" # Finds EC2 instances with this tag
  }

  # Standard deployment configuration
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.app_tg_backend.name # Use the new backend name
    }
  }
}


# --- Frontend CodeDeploy Application ---
resource "aws_codedeploy_app" "frontend_app" {
  provider        = aws.primary
  compute_platform = "Server"
  name             = "App-Frontend" # This name MUST match your GitHub Actions workflow
}

resource "aws_codedeploy_deployment_group" "frontend_dg" {
  provider           = aws.primary
  app_name           = aws_codedeploy_app.frontend_app.name
  deployment_group_name = "Frontend-Servers-Group" # This name MUST match
  service_role_arn   = aws_iam_role.codedeploy_service_role.arn

  ec2_tag_filter {
    key   = "Name"
    type  = "KEY_AND_VALUE"
    value = "Frontend-Server" # Finds EC2 instances with this tag
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.app_tg_frontend.name # Use the new frontend name
    }
  }
}