# backend/app.py

import os
import boto3
import json
from botocore.exceptions import ClientError
from flask import Flask, jsonify
from flask_cors import CORS
import logging
from datetime import datetime

# ===================================================================
# --- Configuration ---
# Uses environment variables for flexibility in different environments.
# ===================================================================
PRIMARY_REGION = os.getenv('PRIMARY_REGION', 'us-east-1')
DR_REGION = os.getenv('DR_REGION', 'us-west-2')
PRIMARY_BUCKET_NAME = os.getenv('PRIMARY_BUCKET_NAME')
DR_STATE_MACHINE_ARN = os.getenv('DR_STATE_MACHINE_ARN') # The ARN of the Step Function in the DR region

# ===================================================================
# --- Logging Setup ---
# ===================================================================
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# ===================================================================
# --- Flask App Initialization ---
# ===================================================================
app = Flask(__name__)
CORS(app) # Enable Cross-Origin Resource Sharing for the frontend

# ===================================================================
# --- Boto3 Clients ---
# Initialize clients once for reuse across requests.
# ===================================================================
# S3 client for checking the primary bucket status
s3_client_primary = boto3.client('s3', region_name=PRIMARY_REGION)

# Step Functions client SPECIFICALLY for the DR region
step_functions_client_dr = boto3.client('stepfunctions', region_name=DR_REGION)


# ===================================================================
# --- Helper Functions for Status Checks ---
# ===================================================================
def get_s3_replication_status(bucket_name):
    """Checks the replication status for a given S3 bucket."""
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
    """Finds the last object uploaded to the S3 bucket, assuming it's a backup."""
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

# ===================================================================
# --- API Routes ---
# ===================================================================
@app.route("/")
def hello():
    """A simple health check endpoint that the ALB can hit."""
    return "Hello, the backend is running!", 200

@app.route('/api/status', methods=['GET'])
def get_status():
    """Main endpoint to get the overall system and DR status."""
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
#step_functions_client = boto3.client('stepfunctions', region_name=PRIMARY_REGION)
@app.route('/api/initiate-failover', methods=['POST'])
def initiate_failover():
    """Triggers the AWS Step Functions state machine for failover."""
    logging.warning("REAL FAILOVER TRIGGERED!")
    if not DR_STATE_MACHINE_ARN:
        logging.error("DR_STATE_MACHINE_ARN environment variable is not set.")
        return jsonify({"message": "Failover process is not configured correctly on the server."}), 500

    try:
        execution_input = json.dumps({"trigger_method": "manual_dashboard"})
        
        response = step_functions_client_dr.start_execution(
            stateMachineArn=DR_STATE_MACHINE_ARN,
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

# ===================================================================
# --- Main Execution Block ---
# This allows running the app directly with `python app.py` for local dev.
# ===================================================================
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)