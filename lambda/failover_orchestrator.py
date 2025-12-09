# lambda/failover_orchestrator.py
import boto3
import os
import logging
import time

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize boto3 clients
rds_client = boto3.client('rds')
route53_client = boto3.client('route53')

# --- Configuration from Environment Variables ---
# These will be set in your Terraform configuration
DR_RDS_INSTANCE_NAME = os.environ.get('DR_RDS_INSTANCE_NAME', 'dr-replica-db') # A unique name for the new primary
SOURCE_REPLICA_ARN = os.environ.get('SOURCE_REPLICA_ARN')
ROUTE53_HOSTED_ZONE_ID = os.environ.get('ROUTE53_HOSTED_ZONE_ID')
DNS_RECORD_NAME = os.environ.get('DNS_RECORD_NAME') # e.g., 'app.yourdomain.com'
DR_ALB_DNS_NAME = os.environ.get('DR_ALB_DNS_NAME')
DR_ALB_ZONE_ID = os.environ.get('DR_ALB_ZONE_ID') # Canonical hosted zone ID for the DR ALB


def promote_rds_replica(event, context):
    """
    State 1: Promotes the RDS Read Replica to a standalone instance.
    This is the first step in the failover process.
    """
    logger.info(f"Attempting to promote read replica: {SOURCE_REPLICA_ARN}")
    if not SOURCE_REPLICA_ARN:
        raise ValueError("SOURCE_REPLICA_ARN environment variable not set.")

    try:
        # Note: We can't use promote_read_replica across regions.
        # The correct action is to create a new instance from a final snapshot.
        # For this example, we'll assume a manual promotion or a different strategy.
        # A more robust solution might involve deleting the replica and creating a new DB from its last snapshot.
        # Let's simulate this by simply checking the instance status.
        
        # This is a placeholder for a more complex promotion logic.
        # In a real cross-region failover, you would likely delete the replica link
        # and manage the DB independently. For now, we'll just return the name.
        logger.info("Simulating RDS promotion. In a real scenario, this would involve snapshot/restore or DMS.")
        
        # Return the identifier for the next step
        return {'dr_db_identifier': DR_RDS_INSTANCE_NAME, 'status': 'PROMOTION_STARTED'}

    except Exception as e:
        logger.error(f"Error promoting RDS replica: {e}")
        raise

def check_rds_status(event, context):
    """
    State 2: Waits until the newly promoted RDS instance is in the 'available' state.
    """
    db_identifier = event['dr_db_identifier']
    logger.info(f"Checking status for RDS instance: {db_identifier}")

    try:
        # We will use the DR replica's ARN to find its identifier
        # This is a simplified approach.
        replica_details = rds_client.describe_db_instances(DBInstanceIdentifier=DR_RDS_INSTANCE_NAME)
        instance_status = replica_details['DBInstances'][0]['DBInstanceStatus']
        
        logger.info(f"Current status of {db_identifier} is: {instance_status}")

        if instance_status == 'available':
            return {'status': 'AVAILABLE'}
        else:
            # This will cause the Step Function's "wait" state to continue waiting
            return {'status': 'PROMOTING'}

    except Exception as e:
        logger.error(f"Error checking RDS status: {e}")
        raise


def update_dns_record(event, context):
    """
    State 3: Updates the Route 53 DNS record to point to the DR Application Load Balancer.
    This is the final step to redirect user traffic.
    """
    logger.info(f"Attempting to update DNS record {DNS_RECORD_NAME} to point to {DR_ALB_DNS_NAME}")

    if not all([ROUTE53_HOSTED_ZONE_ID, DNS_RECORD_NAME, DR_ALB_DNS_NAME, DR_ALB_ZONE_ID]):
        raise ValueError("One or more DNS-related environment variables are not set.")

    try:
        response = route53_client.change_resource_record_sets(
            HostedZoneId=ROUTE53_HOSTED_ZONE_ID,
            ChangeBatch={
                'Comment': 'Automated DR Failover',
                'Changes': [
                    {
                        'Action': 'UPSERT', # Creates the record if it doesn't exist, updates it if it does
                        'ResourceRecordSet': {
                            'Name': DNS_RECORD_NAME,
                            'Type': 'A',
                            'AliasTarget': {
                                'HostedZoneId': DR_ALB_ZONE_ID,
                                'DNSName': DR_ALB_DNS_NAME,
                                'EvaluateTargetHealth': False
                            }
                        }
                    }
                ]
            }
        )
        logger.info(f"DNS update submitted successfully. Change ID: {response['ChangeInfo']['Id']}")
        return {'status': 'DNS_UPDATE_SUCCESSFUL'}

    except Exception as e:
        logger.error(f"Error updating DNS record: {e}")
        raise