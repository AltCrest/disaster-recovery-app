#!/bin/bash
# This script runs before the new frontend files are copied.
# It cleans out the old website to ensure a clean deployment.
rm -rf /usr/share/nginx/html/*