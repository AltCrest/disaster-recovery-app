# terraform/rds-dr.tf

# --- DB Subnet Group for the DR Region ---
# This tells RDS which subnets it is allowed to use in the DR region.
resource "aws_db_subnet_group" "dr" {
  provider   = aws.dr
  name       = "dr-db-subnet-group"
  subnet_ids = [aws_subnet.dr_private_a.id, aws_subnet.dr_private_b.id]

  tags = {
    Name = "DR DB Subnet Group"
  }
}

# --- Security Group for the DR Database and Restore Host ---
# This acts as the firewall for our temporary restore environment.
resource "aws_security_group" "ec2_sg_dr" {
  provider    = aws.dr
  name        = "ec2-sg-dr"
  description = "Allow DB and SSH traffic for DR restore"
  vpc_id      = aws_vpc.dr.id

  # Rule 1: Allow the Restore Host to connect to the new RDS database.
  # This is a self-referencing rule: resources within this SG can talk to each other.
  ingress {
    description = "Allow PostgreSQL traffic from within the same SG"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true # Allows resources in this SG to communicate with each other
  }

  # Rule 2 (Optional but recommended): Allow SSH into the Restore Host for debugging.
  # IMPORTANT: Change the cidr_blocks to your own IP address for security.
  ingress {
    description = "Allow SSH for debugging"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # WARNING: This is insecure. Replace with your IP.
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-sg-dr"
  }
}

# In terraform/rds-dr.tf

# ===================================================================
# --- Section 2: DR Restore Host ---
# This EC2 instance is launched in the DR region to orchestrate the database restore.
# ===================================================================

# --- Find the latest Amazon Linux 2023 AMI in the DR Region ---
data "aws_ami" "amazon_linux_2023_dr" {
  provider    = aws.dr
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

# --- IAM Role and Instance Profile for the Restore Host ---
# This role allows the EC2 instance to be managed by AWS Systems Manager (SSM).
resource "aws_iam_role" "restore_host_role" {
  provider           = aws.dr
  name               = "RestoreHostRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach the AWS-managed policy that allows SSM to connect to the instance.
resource "aws_iam_role_policy_attachment" "restore_host_ssm_policy" {
  provider   = aws.dr
  role       = aws_iam_role.restore_host_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# (Add other policy attachments here if the restore script needs them, e.g., for RDS or S3)

# The instance profile is what links the role to the EC2 instance.
resource "aws_iam_instance_profile" "restore_host_profile" {
  provider = aws.dr
  name     = "RestoreHostInstanceProfile"
  role     = aws_iam_role.restore_host_role.name
}

# --- The Restore Host EC2 Instance Itself ---
resource "aws_instance" "restore_host" {
  provider               = aws.dr
  ami                    = data.aws_ami.amazon_linux_2023_dr.id
  instance_type          = "t2.micro"
  iam_instance_profile   = aws_iam_instance_profile.restore_host_profile.name
  
  # Place the instance in a public subnet so it can access the internet
  subnet_id              = aws_subnet.dr_public_a.id
  vpc_security_group_ids = [aws_security_group.ec2_sg_dr.id]

  # IMPORTANT: Ensure the 'disaster-recovery-key' key pair exists in your DR region (us-west-2)
  key_name               = "barrios-key-pair"

  tags = {
    Name = "Restore-Host"
  }
}

# --- Terraform Output for the Instance ID ---
# This makes it easy to find the instance ID for your Step Function.
output "restore_host_instance_id" {
  description = "The ID of the EC2 instance used for database restoration."
  value       = aws_instance.restore_host.id
}