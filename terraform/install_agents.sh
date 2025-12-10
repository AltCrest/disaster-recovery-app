#!/bin/bash
# This script runs on the first boot of the EC2 instances.

# --- Update the system and install necessary packages ---
sudo yum update -y
sudo yum install -y ruby wget nginx python3-pip # Install Nginx, Python tools, and others

# --- Configure and start Nginx (for the frontend server) ---
# This is needed so the frontend server can serve the React app.
sudo systemctl start nginx
sudo systemctl enable nginx

# --- Install the AWS CodeDeploy Agent ---
# This agent is required for the CI/CD pipeline to deploy code to the instance.
cd /home/ec2-user
# Download the installer script for the correct region
wget https://aws-codedeploy-${region}.s3.${region}.amazonaws.com/latest/install
chmod +x ./install

# Run the installer
sudo ./install auto

# Start the CodeDeploy agent service and ensure it runs on boot
sudo systemctl start codedeploy-agent
sudo systemctl enable codedeploy-agent

# (Optional) Check the status to make sure it's running
sudo systemctl status codedeploy-agent