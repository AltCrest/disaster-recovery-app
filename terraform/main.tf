provider "aws" {
  region = var.primary_region
  alias  = "primary"
}

provider "aws" {
  region = var.dr_region
  alias  = "dr"
}

# Add outputs to display important information after provisioning
output "primary_alb_dns" {
  description = "DNS name of the Application Load Balancer in the primary region."
  value       = aws_lb.app_alb.dns_name
}

output "dr_alb_dns" {
  description = "DNS name of the Application Load Balancer in the DR region."
  value       = aws_lb.app_alb_dr.dns_name
}