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
# In step-function.tf, replace the state machine resource

# Replace your existing aws_sfn_state_machine with this one

# In terraform/step-function.tf

resource "aws_sfn_state_machine" "failover_state_machine" {
  provider = aws.primary
  name     = "RealFailoverOrchestrator"
  role_arn = aws_iam_role.step_function_role.arn

  definition = jsonencode({
    Comment = "A state machine to orchestrate a real DR failover by restoring from S3."
    StartAt = "ProvisionRestoreHost"
    States = {
      ProvisionRestoreHost = {
        Type = "Pass",
        Result = {
          "instance_id" = aws_instance.restore_host.id
        },
        Next = "TriggerRestoreScript"
      },
      # This state STARTS the command but does not wait for it.
      TriggerRestoreScript = {
        Type     = "Task",
        Resource = "arn:aws:states:::aws-sdk:ssm:sendCommand", # REMOVED .sync
        Parameters = {
          "DocumentName"    = "AWS-RunShellScript",
          "InstanceIds"     = [aws_instance.restore_host.id],
          "Comment"         = "Execute database restore script",
          "Parameters" = {
            "commands" = [
              "git clone https://github.com/AltCrest/disaster-recovery-app.git",
              "bash disaster-recovery-app/restore_scripts/run_restore.sh ${aws_s3_bucket.dr_data.id} ${var.dr_region} ${aws_db_subnet_group.dr.name} ${aws_security_group.ec2_sg_dr.id}"
            ]
          }
        },
        ResultPath = "$.ssm_command", # Save the output of this command
        Next       = "WaitBeforeCheckingStatus"
      },
      # This state pauses the workflow for a while.
      WaitBeforeCheckingStatus = {
        Type    = "Wait",
        Seconds = 60, # Wait for 1 minute before checking the command's status
        Next    = "GetRestoreStatusCommand"
      },
      # This state checks the status of the command we just started.
      GetRestoreStatusCommand = {
        Type     = "Task",
        Resource = "arn:aws:states:::aws-sdk:ssm:getCommandInvocation",
        Parameters = {
          # Get the CommandId and InstanceId from the output of the 'TriggerRestoreScript' step
          "CommandId.$"  = "$.ssm_command.Command.CommandId",
          "InstanceId.$" = "$.ssm_command.Command.InstanceIds[0]"
        },
        ResultPath = "$.ssm_command_status", # Save the output of this status check
        Next       = "IsRestoreComplete"
      },
      # This state checks the result and decides whether to loop or continue.
      IsRestoreComplete = {
        Type = "Choice",
        Choices = [
          {
            # If the status is "Success", we can move on.
            Variable     = "$.ssm_command_status.Status",
            StringEquals = "Success",
            Next         = "UpdateDnsRecord"
          },
          {
            # If the status is still "InProgress", loop back to the wait state.
            Variable     = "$.ssm_command_status.Status",
            StringEquals = "InProgress",
            Next         = "WaitBeforeCheckingStatus"
          }
        ],
        # If the status is anything else (Failed, Cancelled, etc.), fail the whole workflow.
        Default = "FailState"
      },
      UpdateDnsRecord = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          FunctionName = aws_lambda_function.update_dns_lambda.function_name,
          "Payload.$"  = "$"
        },
        Next = "TerminateRestoreHost"
      },
      TerminateRestoreHost = {
        Type     = "Task",
        Resource = "arn:aws:states:::aws-sdk:ec2:terminateInstances",
        Parameters = {
          "InstanceIds.$" = "$.[instance_id]"
        },
        End = true
      },
      FailState = {
        Type  = "Fail",
        Error = "RestoreScriptFailed",
        Cause = "The SSM Run Command did not complete successfully."
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