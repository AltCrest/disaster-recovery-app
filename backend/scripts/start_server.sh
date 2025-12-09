#!/bin/bash
# This script starts the application server.

# Change to the application directory
cd /opt/app/backend

# Load the environment variables from the .env file
if [ -f .env ]; then
  export $(echo $(cat .env | sed 's/#.*//g'| xargs) | envsubst)
fi

# Start the Gunicorn server in the background
gunicorn --bind 0.0.0.0:5000 --daemon app:app