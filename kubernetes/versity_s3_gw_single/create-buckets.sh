#!/usr/bin/env bash

# 
# curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
# unzip awscliv2.zip
# sudo ./aws/install
# aws configure

# Define connection credentials (matches default values in the helm-values.yaml or versitygw.yaml)
export AWS_ACCESS_KEY_ID="admin"
export AWS_SECRET_ACCESS_KEY="password"
ENDPOINT="http://localhost:7070"

# List of buckets to create
BUCKETS=("backup" "velero" "ai")

echo "======================================"
echo "Creating Buckets in Versity S3 Gateway"
echo "======================================"

# Try a basic healthcheck on the port
if ! curl -s "$ENDPOINT/_/health" >/dev/null; then
    echo "Warning: Cannot connect to $ENDPOINT"
    echo "Make sure you run port-forwarding first in another terminal or adapt the ENDPOINT if running inside the cluster."
    echo "Example: kubectl port-forward -n versitygw svc/versitygw 7070:7070"
    exit 1
fi

for bucket in "${BUCKETS[@]}"; do
    echo -n "Attempting to create bucket '$bucket'... "
    # Run AWS CLI tool
    # Using awscli locally, we point it to custom endpoint
    if aws s3api create-bucket --bucket "$bucket" --endpoint-url "$ENDPOINT" --region us-east-1 >/dev/null; then
        echo "SUCCESS"
    else
        echo "FAILED"
    fi
done

echo
echo "Current buckets:"
aws s3api list-buckets --endpoint-url "$ENDPOINT" --region us-east-1 --query 'Buckets[*].Name' --output text | tr '\t' '\n'
