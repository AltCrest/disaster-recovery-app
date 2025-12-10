# terraform/backend.tf

terraform {
  backend "s3" {
    # --- Replace with your values ---
    bucket         = "capstone-tfstate-2025" # The S3 bucket name you just created
    key            = "global/terraform.tfstate"     # The path where the state file will live inside the bucket
    region         = "us-east-1"                    # The region where your S3 bucket and DynamoDB table live
    dynamodb_table = "terraform-state-lock"         # The name of the DynamoDB table you just created

    # --- Best Practices ---
    encrypt = true # Encrypt your state file at rest
  }
}