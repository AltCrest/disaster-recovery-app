#!/bin/bash
# This script starts the application server.

# Define the application directory explicitly
APP_DIR="/opt/app/backend"

# Navigate to the application directory
cd "$APP_DIR"

# Check if a .env file exists AT THE ABSOLUTE PATH and load it
if [ -f "$APP_DIR/.env" ]; then
  echo "SUCCESS: Found .env file at $APP_DIR/.env. Loading variables..."
  # This command ensures variables are available to the gunicorn process
  set -o allexport
  source "$APP_DIR/.env"
  set +o allexport
else
  echo "CRITICAL ERROR: .env file not found at $APP_DIR/.env. Cannot start server."
  exit 1
fi

# Start the Gunicorn server as a background process
echo "Starting Gunicorn server..."
# Use an absolute path for the app module just to be safe
gunicorn --bind 0.0.0.0:5000 --daemon app:app

# Check immediately if the process started
# pgrep -f gunicorn
# if [ $? -ne 0 ]; then
#   echo "CRITICAL ERROR: Gunicorn process failed to start."
#   exit 1
# fi