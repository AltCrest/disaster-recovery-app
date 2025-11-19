from flask import Flask, jsonify
from flask_cors import CORS
import boto3

app = Flask(__name__)
CORS(app)

PRIMARY_REGION = 'us-east-1'
DR_REGION = 'us-west-2'

def get_db_status(region_name):
    """Gets the status of the RDS instance in a specific region."""
    try:
        rds_client = boto3.client('rds', region_name=region_name)
        instances = rds_client.describe_db_instances()['DBInstances']
        if not instances:
            return "Not Found"
        return instances[0]['DBInstanceStatus']
    except Exception as e:
        print(f"Error getting DB status in {region_name}: {e}")
        return "Error"

@app.route('/status', methods=['GET'])
def get_status():
    """Returns the health status of both primary and DR sites."""
    primary_db_status = get_db_status(PRIMARY_REGION)
    dr_db_status = get_db_status(DR_REGION)

    status = {
        "primarySite": {
            "region": PRIMARY_REGION,
            "databaseStatus": primary_db_status
        },
        "drSite": {
            "region": DR_REGION,
            "databaseStatus": dr_db_status
        }
    }
    return jsonify(status)

@app.route('/initiate-failover', methods=['POST'])
def initiate_failover():
    """Simulates the logic to initiate a failover."""
    print("FAILOVER INITIATED! (Simulation)")
    return jsonify({"message": "Failover process initiated successfully (simulation)."}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)