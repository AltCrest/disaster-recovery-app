#!/bin/bash
# This script starts the application server.
cd /opt/app/backend
gunicorn --bind 0.0.0.0:5000 --daemon app:app