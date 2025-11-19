#!/bin/bash
cd /opt/app/backend
gunicorn --bind 0.0.0.0:5000 --daemon app:app