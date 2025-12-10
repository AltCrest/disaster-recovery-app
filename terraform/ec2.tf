# terraform/ec2.tf

# Find the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Backend EC2 Instance ---
resource "aws_instance" "backend_server" {
  provider             = aws.primary
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t2.micro"
  key_name             = "barrios-key-pair" # Make sure this key exists in your AWS account
  iam_instance_profile = aws_iam_instance_profile.ec2_codedeploy_profile.name

  # CRITICAL: This places the instance in your VPC and assigns the correct firewall rules
  subnet_id              = aws_subnet.primary_public_a.id
  vpc_security_group_ids = [aws_security_group.ec2_sg_primary.id]
  
  user_data = templatefile("${path.module}/install_agents.sh", {
    region = var.primary_region
  })

  tags = {
    Name = "Backend-Server"
  }
}

# --- Frontend EC2 Instance ---
resource "aws_instance" "frontend_server" {
  provider             = aws.primary
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t2.micro"
  key_name             = "barrios-key-pair" # Make sure this key exists in your AWS account
  iam_instance_profile = aws_iam_instance_profile.ec2_codedeploy_profile.name
  
  subnet_id              = aws_subnet.primary_public_b.id # Using the second AZ for availability
  vpc_security_group_ids = [aws_security_group.ec2_sg_primary.id]

  user_data = templatefile("${path.module}/install_agents.sh", {
    region = var.primary_region
  })

  tags = {
    Name = "Frontend-Server"
  }
}

# --- Target Group Attachments ---
# This "glues" the instances to the load balancer target groups.
resource "aws_lb_target_group_attachment" "backend_attachment" {
  provider         = aws.primary
  target_group_arn = aws_lb_target_group.app_tg_backend.arn
  target_id        = aws_instance.backend_server.id
  port             = 5000
}

resource "aws_lb_target_group_attachment" "frontend_attachment" {
  provider         = aws.primary
  target_group_arn = aws_lb_target_group.app_tg_frontend.arn
  target_id        = aws_instance.frontend_server.id
  port             = 80
}


# --- Terraform Outputs ---
output "backend_server_ip" {
  value = aws_instance.backend_server.public_ip
}

output "frontend_server_ip" {
  value = aws_instance.frontend_server.public_ip
}