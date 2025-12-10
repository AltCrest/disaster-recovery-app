# terraform/iam.tf
# This file contains all IAM Roles and Security Groups for the project.

# ===================================================================
# --- Section 1: Security Groups (Network Firewalls) ---
# ===================================================================

# --- Security Group for the Primary ALB (us-east-1) ---
# Allows public web traffic on port 80.
resource "aws_security_group" "alb_sg_primary" {
  provider    = aws.primary
  name        = "alb-sg-primary"
  description = "Allow HTTP inbound traffic for primary ALB"
  vpc_id      = aws_vpc.primary.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg-primary"
  }
}

# --- Security Group for the Primary EC2 Instances (us-east-1) ---
# Allows traffic ONLY from the primary ALB on ports 80 and 5000.
resource "aws_security_group" "ec2_sg_primary" {
  provider    = aws.primary
  name        = "ec2-sg-primary"
  description = "Allow traffic from ALB"
  vpc_id      = aws_vpc.primary.id

  # Allow frontend traffic from the ALB
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg_primary.id]
  }

  # Allow backend traffic from the ALB
  ingress {
    description     = "App traffic on port 5000 from ALB"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg_primary.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-sg-primary"
  }
}

# --- Security Group for the DR ALB (us-west-2) ---
resource "aws_security_group" "alb_sg_dr" {
  provider    = aws.dr
  name        = "alb-sg-dr"
  description = "Allow HTTP inbound traffic for DR ALB"
  vpc_id      = aws_vpc.dr.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg-dr"
  }
}

# (Note: A complete setup would also have an ec2_sg_dr for the DR instances)

# ===================================================================
# --- Section 2: IAM Roles (Permissions) ---
# ===================================================================

# --- IAM Role for the CodeDeploy Service ---
# Allows CodeDeploy to interact with EC2 and other services.
resource "aws_iam_role" "codedeploy_service_role" {
  provider           = aws.primary
  name               = "CodeDeployServiceRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
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

# --- IAM Role and Profile for EC2 Instances ---
# Attached to the EC2 instances to grant permissions to the CodeDeploy agent and the application.
resource "aws_iam_role" "ec2_codedeploy_role" {
  provider           = aws.primary
  name               = "EC2CodeDeployRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attachment for CodeDeploy agent permissions
resource "aws_iam_role_policy_attachment" "codedeploy_access" {
  provider   = aws.primary
  role       = aws_iam_role.ec2_codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}

# The instance profile that links this role to the EC2 instances
resource "aws_iam_instance_profile" "ec2_codedeploy_profile" {
  provider = aws.primary
  name     = "EC2CodeDeployInstanceProfile"
  role     = aws_iam_role.ec2_codedeploy_role.name
}

# Custom policy to allow the backend application to read from the S3 data bucket
resource "aws_iam_policy" "s3_dashboard_read_policy" {
  provider = aws.primary
  name     = "S3DashboardReadPolicy"
  policy   = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Permissions for the bucket itself
      {
        Action   = ["s3:GetBucketReplicationConfiguration", "s3:ListBucket"],
        Effect   = "Allow",
        Resource = aws_s3_bucket.primary_data.arn
      },
      # Permissions for the objects inside the bucket
      {
        Action   = ["s3:GetObject"],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.primary_data.arn}/*"
      }
    ]
  })
}

# Attaches the S3 read policy to the EC2 role
resource "aws_iam_role_policy_attachment" "s3_read_access" {
  provider   = aws.primary
  role       = aws_iam_role.ec2_codedeploy_role.name
  policy_arn = aws_iam_policy.s3_dashboard_read_policy.arn
}

# --- IAM Role for the Failover Lambda Functions ---
# Allows Lambda to manage RDS and Route 53 during a failover.
resource "aws_iam_role" "failover_lambda_role" {
  provider           = aws.primary
  name               = "FailoverLambdaExecutionRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Policy for basic Lambda logging to CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  provider   = aws.primary
  role       = aws_iam_role.failover_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# NOTE: These policies are overly permissive for production but are fine for a capstone.
resource "aws_iam_role_policy_attachment" "lambda_rds_access" {
  provider   = aws.primary
  role       = aws_iam_role.failover_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_route53_access" {
  provider   = aws.primary
  role       = aws_iam_role.failover_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
}

# --- IAM Role for the Failover Step Function ---
# Allows the Step Function to invoke the Lambda functions.
resource "aws_iam_role" "step_function_role" {
  provider           = aws.primary
  name               = "FailoverStepFunctionRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

# A specific, inline policy is more secure than an AWS managed policy here.
resource "aws_iam_role_policy" "step_function_policy" {
  provider = aws.primary
  name     = "FailoverStepFunctionPolicy"
  role     = aws_iam_role.step_function_role.id
  policy   = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action   = "lambda:InvokeFunction",
      Effect   = "Allow",
      # This policy is scoped to only allow invoking our specific failover Lambdas
      Resource = [
        aws_lambda_function.provision_rds_lambda.arn,
        aws_lambda_function.check_rds_status_lambda.arn,
        aws_lambda_function.update_dns_lambda.arn
      ]
    }]
  })
}