#!/bin/bash
# This script starts the application server.

cd /opt/app/backend

if [ -f .env ]; then
  echo "Loading environment variables from .env file..."
  export $(cat .env | sed 's/#.*//g' | xargs)
else
  echo "Warning: .env file not found. Application may not be configured correctly."
fi

# Start the Gunicorn server as a background process
echo "Starting Gunicorn server..."
gunicorn --bind 0.0.0.0:5000 --daemon app:app