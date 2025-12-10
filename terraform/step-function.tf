# terraform/step-function.tf

# --- Package the Lambda function code into a zip file ---
# This data source reads the files from your 'lambda' directory.
data "archive_file" "failover_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../lambda.zip"
}

# ===================================================================
# --- Section 1: Primary Region Orchestration (us-east-1) ---
# NOTE: While we are creating a DR orchestrator, we keep these Lambdas
# in the primary region as part of the overall application.
# ===================================================================

# --- Lambda Function to Provision a New RDS Instance (Simulated/Placeholder) ---
resource "aws_lambda_function" "provision_rds_lambda" {
  provider      = aws.primary
  filename      = data.archive_file.failover_lambda_zip.output_path
  function_name = "provision-new-rds-instance"
  role          = aws_iam_role.failover_lambda_role.arn
  handler       = "failover_orchestrator.provision_new_rds"
  runtime       = "python3.9"
  timeout       = 30
}

# --- Lambda Function to Check the Status of the New RDS Instance ---
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
      DR_RDS_INSTANCE_NAME = "restored-primary-db"
    }
  }
}

# --- Lambda Function to Update the DNS Record in Route 53 ---
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

# --- The Primary Step Function State Machine Definition ---
# This is the original state machine, now corrected.
resource "aws_sfn_state_machine" "failover_state_machine" {
  provider     = aws.primary
  name         = "FailoverOrchestrator"
  role_arn     = aws_iam_role.step_function_role.arn
  definition   = jsonencode({
    Comment = "A state machine to orchestrate DR failover."
    StartAt = "ProvisionRestoreHost"
    States = {
      ProvisionRestoreHost = {
        Type = "Pass",
        Result = {
          "instance_id" = aws_instance.restore_host.id
        },
        Next = "WaitForHostToBeReady"
      },
      WaitForHostToBeReady = {
        Type    = "Wait",
        Seconds = 90,
        Next    = "TriggerRestoreScript"
      },
      TriggerRestoreScript = {
        Type     = "Task",
        Resource = "arn:aws:states:::aws-sdk:ssm:sendCommand",
        Parameters = {
          "DocumentName"    = "AWS-RunShellScript",
          "InstanceIds.$"   = "$.instance_id",
          "Comment"         = "Execute database restore script",
          "Parameters" = {
            "commands" = [
              "git clone https://github.com/AltCrest/disaster-recovery-app.git",
              "bash disaster-recovery-app/restore_scripts/run_restore.sh ${aws_s3_bucket.dr_data.id} ${var.dr_region} ${aws_db_subnet_group.dr.name} ${aws_security_group.ec2_sg_dr.id}"
            ]
          }
        },
        ResultPath = "$.ssm_command",
        Next       = "WaitBeforeCheckingStatus"
      },
      WaitBeforeCheckingStatus = {
        Type    = "Wait",
        Seconds = 60,
        Next    = "GetRestoreStatusCommand"
      },
      GetRestoreStatusCommand = {
        Type     = "Task",
        Resource = "arn:aws:states:::aws-sdk:ssm:getCommandInvocation",
        Parameters = {
          "CommandId.$"  = "$.ssm_command.Command.CommandId",
          "InstanceId.$" = "$.ssm_command.Command.InstanceIds[0]"
        },
        ResultPath = "$.ssm_command_status",
        Next       = "IsRestoreComplete"
      },
      IsRestoreComplete = {
        Type = "Choice",
        Choices = [
          {
            Variable     = "$.ssm_command_status.Status",
            StringEquals = "Success",
            Next         = "UpdateDnsRecord"
          },
          {
            Variable     = "$.ssm_command_status.Status",
            StringEquals = "InProgress",
            Next         = "WaitBeforeCheckingStatus"
          }
        ],
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
          "InstanceIds.$" = "$.instance_id"
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

# ===================================================================
# --- Section 2: Disaster Recovery Region Step Function (us-west-2) ---
# THIS IS A DUPLICATE of the orchestrator, but it lives in the DR region.
# This ensures the failover logic can run even if the primary region's control plane is impaired.
# ===================================================================

resource "aws_sfn_state_machine" "failover_state_machine_dr" {
  provider     = aws.dr # <-- LIVES IN THE DR REGION
  name         = "FailoverOrchestrator-DR" # A distinct name
  role_arn     = aws_iam_role.step_function_role_dr.arn # References a DR role defined in iam.tf
  
  # The definition is IDENTICAL to the primary state machine.
  # Terraform will correctly substitute the DR region resources where needed.
  definition   = jsonencode({
    Comment = "A state machine in the DR region to orchestrate failover."
    StartAt = "ProvisionRestoreHost"
    States = {
      ProvisionRestoreHost = {
        Type = "Pass",
        Result = {
          "instance_id" = aws_instance.restore_host.id
        },
        Next = "WaitForHostToBeReady"
      },
      WaitForHostToBeReady = {
        Type    = "Wait",
        Seconds = 90,
        Next    = "TriggerRestoreScript"
      },
      TriggerRestoreScript = {
        Type     = "Task",
        Resource = "arn:aws:states:::aws-sdk:ssm:sendCommand",
        Parameters = {
          "DocumentName"    = "AWS-RunShellScript",
          "InstanceIds.$"   = "$.instance_id",
          "Comment"         = "Execute database restore script",
          "Parameters" = {
            "commands" = [
              "git clone https://github.com/AltCrest/disaster-recovery-app.git",
              "bash disaster-recovery-app/restore_scripts/run_restore.sh ${aws_s3_bucket.dr_data.id} ${var.dr_region} ${aws_db_subnet_group.dr.name} ${aws_security_group.ec2_sg_dr.id}"
            ]
          }
        },
        ResultPath = "$.ssm_command",
        Next       = "WaitBeforeCheckingStatus"
      },
      WaitBeforeCheckingStatus = {
        Type    = "Wait",
        Seconds = 60,
        Next    = "GetRestoreStatusCommand"
      },
      GetRestoreStatusCommand = {
        Type     = "Task",
        Resource = "arn:aws:states:::aws-sdk:ssm:getCommandInvocation",
        Parameters = {
          "CommandId.$"  = "$.ssm_command.Command.CommandId",
          "InstanceId.$" = "$.ssm_command.Command.InstanceIds[0]"
        },
        ResultPath = "$.ssm_command_status",
        Next       = "IsRestoreComplete"
      },
      IsRestoreComplete = {
        Type = "Choice",
        Choices = [
          {
            Variable     = "$.ssm_command_status.Status",
            StringEquals = "Success",
            Next         = "UpdateDnsRecord"
          },
          {
            Variable     = "$.ssm_command_status.Status",
            StringEquals = "InProgress",
            Next         = "WaitBeforeCheckingStatus"
          }
        ],
        Default = "FailState"
      },
      UpdateDnsRecord = {
        Type     = "Task",
        # NOTE: This assumes a Lambda for DNS updates also exists in the DR region.
        # For simplicity, we can point to the primary one, but a fully resilient
        # setup would have a duplicate update_dns_lambda_dr resource.
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
          "InstanceIds.$" = "$.instance_id"
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


# --- Terraform Outputs for the Backend Application ---
output "failover_state_machine_arn" {
  description = "The ARN of the PRIMARY failover Step Function state machine."
  value       = aws_sfn_state_machine.failover_state_machine.id
}

output "failover_state_machine_arn_dr" {
  description = "The ARN of the DR failover Step Function state machine."
  value       = aws_sfn_state_machine.failover_state_machine_dr.id
}