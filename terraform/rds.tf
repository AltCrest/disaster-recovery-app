# --- Primary RDS Instance ---
resource "aws_db_instance" "primary_db" {
  provider             = aws.primary
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "17"
  instance_class       = "db.t3.micro"
  db_name              = "primarydb"
  username             = var.db_username
  password             = var.db_password
  skip_final_snapshot  = true
  publicly_accessible  = true # For simplicity; use private subnets in production
  backup_retention_period = 7
  # vpc_security_group_ids = [aws_security_group.rds_sg.id]
}
