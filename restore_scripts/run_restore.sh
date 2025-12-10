#!/bin/bash

# This script runs on a temporary EC2 "Restore Host"
# It will be executed by AWS Systems Manager Run Command

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration (these will be passed as parameters) ---
DR_S3_BUCKET="$1"
DR_REGION="$2"
DB_SUBNET_GROUP_NAME="$3"
DB_SECURITY_GROUP_ID="$4"
DB_INSTANCE_IDENTIFIER="restored-primary-db"
DB_USER="adminuser"
DB_PASSWORD="YourSecurePassword123" # In production, get this from Secrets Manager

# --- 1. Install necessary tools ---
echo "Installing PostgreSQL client..."
sudo yum update -y
sudo yum install -y postgresql15

# --- 2. Find the latest backup file in the DR S3 bucket ---
echo "Finding latest backup in bucket ${DR_S3_BUCKET}..."
LATEST_BACKUP=$(aws s3 ls "s3://${DR_S3_BUCKET}/" --region "${DR_REGION}" | sort | tail -n 1 | awk '{print $4}')
if [ -z "$LATEST_BACKUP" ]; then
    echo "CRITICAL ERROR: No backup files found in S3 bucket ${DR_S3_BUCKET}."
    exit 1
fi
echo "Latest backup found: ${LATEST_BACKUP}"

# --- 3. Create a new RDS instance ---
echo "Creating new RDS instance: ${DB_INSTANCE_IDENTIFIER}..."
aws rds create-db-instance \
    --db-instance-identifier "${DB_INSTANCE_IDENTIFIER}" \
    --db-instance-class "db.t3.micro" \
    --engine "postgres" \
    --engine-version "17" \
    --master-username "${DB_USER}" \
    --master-user-password "${DB_PASSWORD}" \
    --allocated-storage 20 \
    --db-subnet-group-name "${DB_SUBNET_GROUP_NAME}" \
    --vpc-security-group-ids "${DB_SECURITY_GROUP_ID}" \
    --publicly-accessible \
    --region "${DR_REGION}"

# --- 4. Wait for the new RDS instance to become available ---
echo "Waiting for RDS instance to become available... This will take several minutes."
aws rds wait db-instance-available --db-instance-identifier "${DB_INSTANCE_IDENTIFIER}" --region "${DR_REGION}"
echo "RDS instance is now available."

# --- 5. Get the endpoint address of the new RDS instance ---
DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "${DB_INSTANCE_IDENTIFIER}" --query 'DBInstances[0].Endpoint.Address' --output text --region "${DR_REGION}")
if [ "$DB_ENDPOINT" == "None" ]; then
    echo "CRITICAL ERROR: Could not retrieve endpoint for new RDS instance."
    exit 1
fi
echo "RDS endpoint is: ${DB_ENDPOINT}"

# --- 6. Download the backup file and restore it ---
echo "Downloading backup file s3://${DR_S3_BUCKET}/${LATEST_BACKUP}..."
aws s3 cp "s3://${DR_S3_BUCKET}/${LATEST_BACKUP}" "/tmp/latest_backup.sql" --region "${DR_REGION}"

echo "Restoring database... This may take some time."
PGPASSWORD="${DB_PASSWORD}" psql --host="${DB_ENDPOINT}" --username="${DB_USER}" --dbname="postgres" --file="/tmp/latest_backup.sql"

echo "DATABASE RESTORE COMPLETE!"