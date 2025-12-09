# terraform/step-function.tf

# --- IAM Role for Lambda Functions ---
resource "aws_iam_role" "failover_lambda_role" {
  provider = aws.primary
  name     = "FailoverLambdaExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  provider   = aws.primary
  role       = aws_iam_role.failover_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
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

# --- Zip the Lambda Code ---
data "archive_file" "failover_lambda_zip" {
  type        = "zip"
  # CHANGE THIS LINE to go up one directory from the current module path
  source_dir  = "${path.module}/../lambda" 
  # CHANGE THIS LINE as well
  output_path = "${path.module}/../lambda.zip" 
}
# --- Create the Lambda Functions ---
resource "aws_lambda_function" "provision_rds_lambda" { # CORRECTED NAME
  provider      = aws.primary
  filename      = data.archive_file.failover_lambda_zip.output_path
  function_name = "provision-new-rds-instance"
  role          = aws_iam_role.failover_lambda_role.arn
  handler       = "failover_orchestrator.provision_new_rds" # CORRECTED HANDLER
  runtime       = "python3.9"
  timeout       = 30
  # NO ENVIRONMENT BLOCK NEEDED
}

resource "aws_lambda_function" "check_rds_status_lambda" {
  provider      = aws.primary
  filename      = data.archive_file.failover_lambda_zip.output_path
  function_name = "check-rds-status"
  role          = aws_iam_role.failover_lambda_role.arn
  handler       = "failover_orchestrator.check_rds_status"
  runtime       = "python3.9"
  timeout       = 30
  environment {
    variables = {
      # This should be the name you expect the restored DB to have.
      DR_RDS_INSTANCE_NAME = "restored-primary-db"
    }
  }
}

resource "aws_lambda_function" "update_dns_lambda" {
  provider      = aws.primary
  filename      = data.archive_file.failover_lambda_zip.output_path
  function_name = "update-dns-record"
  role          = aws_iam_role.failover_lambda_role.arn
  handler       = "failover_orchestrator.update_dns_record"
  runtime       = "python3.9"
  timeout       = 30
  environment {
    variables = {
      ROUTE53_HOSTED_ZONE_ID = "YOUR_HOSTED_ZONE_ID" # Replace with your real Hosted Zone ID
      DNS_RECORD_NAME        = "app.yourdomain.com"     # Replace with your real domain
      DR_ALB_DNS_NAME        = aws_lb.app_alb_dr.dns_name
      DR_ALB_ZONE_ID         = aws_lb.app_alb_dr.zone_id
    }
  }
}

# --- IAM Role for Step Function ---
resource "aws_iam_role" "step_function_role" {
  provider = aws.primary
  name     = "FailoverStepFunctionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "step_function_policy" {
  provider = aws.primary
  name     = "FailoverStepFunctionPolicy"
  role     = aws_iam_role.step_function_role.id
  policy   = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action   = "lambda:InvokeFunction",
      Effect   = "Allow",
      Resource = [
        # Ensure all three lambdas are listed here with their correct names
        aws_lambda_function.provision_rds_lambda.arn,
        aws_lambda_function.check_rds_status_lambda.arn,
        aws_lambda_function.update_dns_lambda.arn
      ]
    }]
  })
}

# --- The Step Function State Machine Definition ---
resource "aws_sfn_state_machine" "failover_state_machine" {
  provider     = aws.primary
  name         = "FailoverOrchestrator"
  role_arn     = aws_iam_role.step_function_role.arn
  definition   = jsonencode({
    Comment = "A state machine to orchestrate DR failover."
    StartAt = "ProvisionNewRds" # CORRECTED START STATE
    States = {
      ProvisionNewRds = {
        Type     = "Task"
        Resource = aws_lambda_function.provision_rds_lambda.arn # CORRECTED RESOURCE
        Next     = "WaitForRdsAvailable"
      },
      WaitForRdsAvailable = {
        Type     = "Wait"
        Seconds  = 30
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
            Variable = "$.status"
            StringEquals = "AVAILABLE"
            Next = "UpdateDnsRecord"
          }
        ]
        Default = "WaitForRdsAvailable"
      },
      UpdateDnsRecord = {
        Type     = "Task"
        Resource = aws_lambda_function.update_dns_lambda.arn # CORRECTED RESOURCE
        End      = true
      }
    }
  })
}

# --- Output the ARN to configure the backend ---
output "failover_state_machine_arn" {
  description = "The ARN of the failover Step Function state machine."
  value       = aws_sfn_state_machine.failover_state_machine.id
}