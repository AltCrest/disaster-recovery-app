#!/bin/bash
# This script starts the application server.

# Navigate to the application directory where the files were deployed
cd /opt/app/backend

if [ -f .env ]; then
  echo "Loading environment variables from .env file..."
  # This command exports the variables so Gunicorn can see them
  export $(cat .env | sed 's/#.*//g' | xargs)
else
  echo "Warning: .env file not found. Application may not be configured correctly."
fi

# Start the Gunicorn server as a background process
echo "Starting Gunicorn server..."
gunicorn --bind 0.0.0.0:5000 --daemon app:app