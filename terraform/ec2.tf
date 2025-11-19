# terraform/ec2.tf

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-x86_64"] # Filter for AL2023
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "backend_server" {
  provider      = aws.primary
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"
  key_name      = "barrios-key-pair"
  iam_instance_profile = aws_iam_instance_profile.ec2_codedeploy_profile.name
  user_data = templatefile("${path.module}/install_codedeploy.sh", {
  region = var.primary_region
  })

  tags = {
    Name = "Backend-Server"
  }
}

resource "aws_instance" "frontend_server" {
  provider      = aws.primary
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"
  key_name      = "barrios-key-pair" 
  iam_instance_profile = aws_iam_instance_profile.ec2_codedeploy_profile.name
  user_data = templatefile("${path.module}/install_codedeploy.sh", {
  region = var.primary_region
  })

  tags = {
    Name = "Frontend-Server"
  }
}

# Add outputs to get the public IP addresses
output "backend_server_ip" {
  value = aws_instance.backend_server.public_ip
}

output "frontend_server_ip" {
  value = aws_instance.frontend_server.public_ip
}