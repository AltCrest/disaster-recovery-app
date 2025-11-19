#!/bin/bash
# Update and install dependencies
sudo yum update -y
sudo yum install -y ruby wget nginx

sudo systemctl start nginx
sudo systemctl enable nginx

cd /home/ec2-user
wget https://aws-coddeploy-${region}.s3.${region}.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto
sudo service coddeploy-agent start
sudo service coddeploy-agent status