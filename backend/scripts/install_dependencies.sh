#!/bin/bash
yum install -y python3-pip
pip3 install gunicorn
pip3 install -r /opt/app/backend/requirements.txt