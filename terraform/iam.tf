# --- Primary Region Security Group for ALB ---
resource "aws_security_group" "alb_sg_primary" {
  provider = aws.primary
  name        = "alb-sg-primary"
  description = "Allow HTTP inbound traffic for primary ALB"
  vpc_id      = aws_vpc.primary.id

  ingress {
    description      = "HTTP from anywhere"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg-primary"
  }
}

# --- DR Region Security Group for ALB ---
resource "aws_security_group" "alb_sg_dr" {
  provider = aws.dr
  name        = "alb-sg-dr"
  description = "Allow HTTP inbound traffic for DR ALB"
  vpc_id      = aws_vpc.dr.id

  ingress {
    description      = "HTTP from anywhere"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg-dr"
  }
}

resource "aws_iam_role" "ec2_codedeploy_role" {
  name = "EC2CodeDeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_access" {
  role       = aws_iam_role.ec2_codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}

resource "aws_iam_instance_profile" "ec2_codedeploy_profile" {
  name = "EC2CodeDeployInstanceProfile"
  role = aws_iam_role.ec2_codedeploy_role.name
}