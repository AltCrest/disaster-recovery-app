# backend/app.py

import os
import boto3
from botocore.exceptions import ClientError
from flask import Flask, jsonify
from flask_cors import CORS
import logging
from datetime import datetime
import json

# --- Configuration ---
PRIMARY_REGION = os.getenv('PRIMARY_REGION', 'us-east-1')
DR_REGION = os.getenv('DR_REGION', 'us-west-2')
PRIMARY_BUCKET_NAME = os.getenv('PRIMARY_BUCKET_NAME')

# --- Logging Setup ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Flask App Initialization ---
app = Flask(__name__)
CORS(app)

# --- Boto3 Clients ---
s3_client_primary = boto3.client('s3', region_name=PRIMARY_REGION)

# --- Add these new components ---
step_functions_client = boto3.client('stepfunctions', region_name=PRIMARY_REGION)
# The ARN you copied from the terraform output
STATE_MACHINE_ARN = os.getenv('STATE_MACHINE_ARN')

# --- Helper Functions ---
def get_s3_replication_status(bucket_name):
    if not bucket_name:
        return {"status": "CONFIG_ERROR", "details": "PRIMARY_BUCKET_NAME not set."}
    try:
        replication_config = s3_client_primary.get_bucket_replication(Bucket=bucket_name)
        rule = replication_config['ReplicationConfiguration']['Rules'][0]
        return {
            "status": "OPERATIONAL" if rule['Status'] == 'Enabled' else "ERROR",
            "details": f"Replication rule '{rule['ID']}' is {rule['Status']}."
        }
    except ClientError as e:
        if e.response['Error']['Code'] == 'ReplicationConfigurationNotFoundError':
            logging.warning(f"No replication configuration found for bucket {bucket_name}.")
            return {"status": "DEGRADED", "details": "No replication configured."}
        logging.error(f"Error getting replication status for {bucket_name}: {e}")
        return {"status": "ERROR", "details": str(e)}
    except (KeyError, IndexError):
        logging.error(f"Could not parse replication rules for bucket {bucket_name}.")
        return {"status": "ERROR", "details": "Could not parse replication rules."}


def get_last_backup_info(bucket_name):
    if not bucket_name:
        return {"last_backup_file": "N/A", "last_backup_time": "N/A", "freshness_status": "CONFIG_ERROR"}
    try:
        response = s3_client_primary.list_objects_v2(Bucket=bucket_name)
        if 'Contents' not in response or not response['Contents']:
            return {"last_backup_file": "None found", "last_backup_time": "N/A", "freshness_status": "DEGRADED"}

        latest_object = sorted(response['Contents'], key=lambda obj: obj['LastModified'], reverse=True)[0]
        last_modified_time = latest_object['LastModified']
        time_diff = datetime.now(last_modified_time.tzinfo) - last_modified_time
        freshness = "OPERATIONAL"
        if time_diff.days > 1:
            freshness = "DEGRADED"
        if time_diff.days > 3:
            freshness = "ERROR"
        return {
            "last_backup_file": latest_object['Key'],
            "last_backup_time": last_modified_time.strftime('%Y-%m-%d %H:%M:%S %Z'),
            "freshness_status": freshness
        }
    except ClientError as e:
        logging.error(f"Error listing objects for bucket {bucket_name}: {e}")
        return {"last_backup_file": "Error", "last_backup_time": "Error", "freshness_status": "ERROR"}

# --- API Routes ---
@app.route('/api/status', methods=['GET'])
def get_status():
    logging.info("Status request received for /api/status.")
    replication = get_s3_replication_status(PRIMARY_BUCKET_NAME)
    backup_info = get_last_backup_info(PRIMARY_BUCKET_NAME)
    statuses = [replication['status'], backup_info['freshness_status']]
    overall_status = "OPERATIONAL"
    if "DEGRADED" in statuses:
        overall_status = "DEGRADED"
    if "ERROR" in statuses or "CONFIG_ERROR" in statuses:
        overall_status = "ERROR"
    return jsonify({
        "overallStatus": overall_status,
        "lastChecked": datetime.now().isoformat(),
        "primarySite": {
            "region": PRIMARY_REGION,
            "bucketName": PRIMARY_BUCKET_NAME or "Not Configured",
            "replicationStatus": replication,
        },
        "drSite": {
            "region": DR_REGION
        },
        "backupDetails": backup_info
    })

# --- Add these new components ---
step_functions_client = boto3.client('stepfunctions', region_name=PRIMARY_REGION)
# The ARN you copied from the terraform output
STATE_MACHINE_ARN = os.getenv('STATE_MACHINE_ARN')
@app.route('/api/initiate-failover', methods=['POST'])
def initiate_failover():
    """Triggers the AWS Step Functions state machine for failover."""
    logging.warning("REAL FAILOVER TRIGGERED!")
    
    if not STATE_MACHINE_ARN:
        logging.error("STATE_MACHINE_ARN environment variable is not set.")
        return jsonify({"message": "Failover process is not configured correctly on the server."}), 500

    try:
        execution_input = json.dumps({"trigger_method": "manual_dashboard"})
        
        response = step_functions_client.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            input=execution_input
        )
        
        execution_arn = response['executionArn']
        logging.info(f"Successfully started state machine execution: {execution_arn}")
        
        return jsonify({
            "message": "Failover process initiated successfully.",
            "executionArn": execution_arn 
        }), 200

    except Exception as e:
        logging.error(f"Failed to start Step Function execution: {e}")
        return jsonify({"message": "An error occurred while trying to initiate the failover."}), 500
    
@app.route("/")
def hello():
    """
    A simple health check endpoint that the ALB can hit.
    """
    return "Hello, the backend is running!", 200 # Return a 200 OK status

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)