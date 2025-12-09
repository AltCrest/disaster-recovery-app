#!/bin/bash
# This script installs the application dependencies.
yum install -y python3-pip
pip3 install gunicorn
pip3 install -r /opt/app/backend/requirements.txt