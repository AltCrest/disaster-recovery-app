# terraform/step-function.tf

# --- Package the Lambda function code into a zip file ---
# This data source reads the files from your 'lambda' directory.
data "archive_file" "failover_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../lambda.zip"
}


# --- Lambda Function to Provision a New RDS Instance (Simulated) ---
resource "aws_lambda_function" "provision_rds_lambda" {
  provider      = aws.primary
  filename      = data.archive_file.failover_lambda_zip.output_path
  function_name = "provision-new-rds-instance"
  role          = aws_iam_role.failover_lambda_role.arn # References the role from iam.tf
  handler       = "failover_orchestrator.provision_new_rds"
  runtime       = "python3.9"
  timeout       = 30
}

# --- Lambda Function to Check the Status of the New RDS Instance ---
resource "aws_lambda_function" "check_rds_status_lambda" {
  provider      = aws.primary
  filename      = data.archive_file.failover_lambda_zip.output_path
  function_name = "check-rds-status"
  role          = aws_iam_role.failover_lambda_role.arn # References the role from iam.tf
  handler       = "failover_orchestrator.check_rds_status"
  runtime       = "python3.9"
  timeout       = 30
  environment {
    variables = {
      # The name you expect the restored DB to have during a failover
      DR_RDS_INSTANCE_NAME = "restored-primary-db"
    }
  }
}

# --- Lambda Function to Update the DNS Record in Route 53 ---
resource "aws_lambda_function" "update_dns_lambda" {
  provider      = aws.primary
  filename      = data.archive_file.failover_lambda_zip.output_path
  function_name = "update-dns-record"
  role          = aws_iam_role.failover_lambda_role.arn # References the role from iam.tf
  handler       = "failover_orchestrator.update_dns_record"
  runtime       = "python3.9"
  timeout       = 30
  environment {
    variables = {
      # IMPORTANT: You MUST replace these placeholder values with your real domain info
      ROUTE53_HOSTED_ZONE_ID = "YOUR_HOSTED_ZONE_ID" # e.g., Z0123456789ABCDEFGHIJ
      DNS_RECORD_NAME        = "app.yourdomain.com"
      DR_ALB_DNS_NAME        = aws_lb.app_alb_dr.dns_name
      DR_ALB_ZONE_ID         = aws_lb.app_alb_dr.zone_id
    }
  }
}


# --- The Step Function State Machine Definition ---
# This orchestrates the Lambda functions in the correct order.
resource "aws_sfn_state_machine" "failover_state_machine" {
  provider     = aws.primary
  name         = "FailoverOrchestrator"
  role_arn     = aws_iam_role.step_function_role.arn # References the role from iam.tf
  definition   = jsonencode({
    Comment = "A state machine to orchestrate DR failover."
    StartAt = "ProvisionNewRds"
    States = {
      ProvisionNewRds = {
        Type     = "Task"
        Resource = aws_lambda_function.provision_rds_lambda.arn
        Next     = "WaitForRdsAvailable"
      },
      WaitForRdsAvailable = {
        Type     = "Wait"
        Seconds  = 30 # Wait for 30 seconds between checks
        Next     = "CheckRdsStatus"
      },
      CheckRdsStatus = {
        Type     = "Task"
        Resource = aws_lambda_function.check_rds_status_lambda.arn
        Next     = "IsRdsAvailable"
      },
      IsRdsAvailable = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.status"
            StringEquals = "AVAILABLE"
            Next         = "UpdateDnsRecord"
          }
        ]
        Default = "WaitForRdsAvailable"
      },
      UpdateDnsRecord = {
        Type     = "Task"
        Resource = aws_lambda_function.update_dns_lambda.arn
        End      = true
      }
    }
  })
}

# --- Terraform Output for the Backend Application ---
# This makes it easy to get the ARN to configure the backend .env file.
output "failover_state_machine_arn" {
  description = "The ARN of the failover Step Function state machine."
  value       = aws_sfn_state_machine.failover_state_machine.id
}