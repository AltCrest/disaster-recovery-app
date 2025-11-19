variable "primary_region" {
  description = "The primary AWS region for production."
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "The disaster recovery AWS region."
  type        = string
  default     = "us-west-2"
}

variable "db_username" {
  description = "Username for the RDS database."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Password for the RDS database."
  type        = string
  sensitive   = true
  default     = "Password123"
}