# terraform/codedeploy.tf

# --- Backend CodeDeploy Application ---
resource "aws_codedeploy_app" "backend_app" {
  provider         = aws.primary
  compute_platform = "Server"
  name             = "App-Backend" # This name MUST match your GitHub Actions workflow
}

# --- Backend Deployment Group ---
resource "aws_codedeploy_deployment_group" "backend_dg" {
  provider              = aws.primary
  app_name              = aws_codedeploy_app.backend_app.name
  deployment_group_name = "Backend-Servers-Group" # This name MUST match your workflow
  service_role_arn      = aws_iam_role.codedeploy_service_role.arn # References the role from iam.tf

  # Finds the EC2 instances with the correct tag to deploy to
  ec2_tag_filter {
    key   = "Name"
    type  = "KEY_AND_VALUE"
    value = "Backend-Server"
  }

  # Specifies an in-place deployment strategy
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  # Associates the deployment group with the ALB's backend target group
  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.app_tg_backend.name # References the target group from alb.tf
    }
  }
}


# --- Frontend CodeDeploy Application ---
resource "aws_codedeploy_app" "frontend_app" {
  provider         = aws.primary
  compute_platform = "Server"
  name             = "App-Frontend" # This name MUST match your GitHub Actions workflow
}

# --- Frontend Deployment Group ---
resource "aws_codedeploy_deployment_group" "frontend_dg" {
  provider              = aws.primary
  app_name              = aws_codedeploy_app.frontend_app.name
  deployment_group_name = "Frontend-Servers-Group" # This name MUST match your workflow
  service_role_arn      = aws_iam_role.codedeploy_service_role.arn # References the role from iam.tf

  # Finds the EC2 instances with the correct tag to deploy to
  ec2_tag_filter {
    key   = "Name"
    type  = "KEY_AND_VALUE"
    value = "Frontend-Server"
  }

  # Specifies an in-place deployment strategy
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  # Associates the deployment group with the ALB's frontend target group
  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.app_tg_frontend.name # References the target group from alb.tf
    }
  }
}