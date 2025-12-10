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
DR_RDS_INSTANCE_NAME = os.environ.get('DR_RDS_INSTANCE_NAME', 'dr-replica-db') # A unique name for the new primary
SOURCE_REPLICA_ARN = os.environ.get('SOURCE_REPLICA_ARN')
ROUTE53_HOSTED_ZONE_ID = os.environ.get('ROUTE53_HOSTED_ZONE_ID')
DNS_RECORD_NAME = os.environ.get('DNS_RECORD_NAME') # e.g., 'app.yourdomain.com'
DR_ALB_DNS_NAME = os.environ.get('DR_ALB_DNS_NAME')
DR_ALB_ZONE_ID = os.environ.get('DR_ALB_ZONE_ID') 


def provision_new_rds(event, context):
    """
    State 1: Starts the process of provisioning a new RDS instance in the DR region.
    For a fully automated setup, this Lambda would use boto3 to create the RDS instance.
    For this capstone, we will simulate this by returning the expected name.
    """
    dr_db_identifier = os.environ.get('DR_RDS_INSTANCE_NAME', 'restored-primary-db')
    logger.info(f"Initiating provisioning for new RDS instance: {dr_db_identifier}")

    # In a real-world scenario, you would add:
    # rds_client.create_db_instance(...)
    
    logger.info("Simulation: Provisioning signal sent. The instance will be created via other means or manually for this exercise.")
    
    # We return the identifier so the next step knows which DB to check on.
    return {'dr_db_identifier': dr_db_identifier, 'status': 'PROVISIONING_STARTED'}

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