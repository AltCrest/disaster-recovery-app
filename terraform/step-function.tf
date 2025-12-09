# terraform/step-function.tf

# --- IAM Role for Lambda Functions ---
# This role gives our Lambda functions permission to interact with RDS and Route 53.
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

# Attach the necessary policies for logging, RDS, and Route 53
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  provider   = aws.primary
  role       = aws_iam_role.failover_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "lambda_rds_access" {
  provider   = aws.primary
  role       = aws_iam_role.failover_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess" # For a real project, scope this down!
}
resource "aws_iam_role_policy_attachment" "lambda_route53_access" {
  provider   = aws.primary
  role       = aws_iam_role.failover_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess" # Scope this down!
}


# --- Zip the Lambda Code ---
data "archive_file" "failover_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/lambda"
  output_path = "${path.root}/lambda.zip"
}

# --- Create the Lambda Functions ---
resource "aws_lambda_function" "promote_rds_lambda" {
  provider      = aws.primary
  filename      = data.archive_file.failover_lambda_zip.output_path
  function_name = "promote-rds-replica"
  role          = aws_iam_role.failover_lambda_role.arn
  handler       = "failover_orchestrator.promote_rds_replica"
  runtime       = "python3.9"
  timeout       = 30
  
  environment {
    variables = {
      SOURCE_REPLICA_ARN = aws_db_instance.dr_replica_db.arn # Assuming you still have a replica for this logic
    }
  }
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
      DR_RDS_INSTANCE_NAME = "your-dr-replica-identifier" # You need to get this from your DR replica
    }
  }
}

resource "aws_lambda_function" "provision_rds_lambda" { # <-- RENAMED
  provider      = aws.primary
  filename      = data.archive_file.failover_lambda_zip.output_path
  function_name = "provision-new-rds-instance" # <-- RENAMED
  role          = aws_iam_role.failover_lambda_role.arn
  handler       = "failover_orchestrator.provision_new_rds" # <-- UPDATED HANDLER
  runtime       = "python3.9"
  timeout       = 30
  # The environment block with the invalid reference is now completely REMOVED.
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
        aws_lambda_function.promote_rds_lambda.arn,
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
    StartAt = "ProvisionNewRds" # <-- RENAMED START STATE
    States = {
      ProvisionNewRds = { # <-- RENAMED STATE
        Type     = "Task"
        Resource = aws_lambda_function.provision_rds_lambda.arn # <-- UPDATED RESOURCE
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
            Variable = "$.status"
            StringEquals = "AVAILABLE"
            Next = "UpdateDnsRecord"
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

# --- Output the ARN to configure the backend ---
output "failover_state_machine_arn" {
  description = "The ARN of the failover Step Function state machine."
  value       = aws_sfn_state_machine.failover_state_machine.id
}