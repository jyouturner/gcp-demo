#!/bin/bash

# Script to check Shared VPC and Dataflow settings

# Function to check command success and report
check_command() {
    if ! $@; then
        echo "FAILED: $1"
        return 1
    else
        echo "PASSED: $1"
        return 0
    fi
}

# Set your environment variables
echo "Please enter the following details:"
read -p "Host Project ID: " HOST_PROJECT
read -p "Service Project ID: " SERVICE_PROJECT
read -p "Shared VPC Name: " SHARED_VPC_NAME
read -p "Shared Subnet Name: " SHARED_SUBNET_NAME
read -p "Region: " REGION
read -p "Dataflow Service Account Email: " SA_EMAIL

echo "Checking Shared VPC setup and permissions..."

# Check if Shared VPC is enabled on host project
echo "Checking if Shared VPC is enabled on host project..."
check_command gcloud compute shared-vpc get-host-project $HOST_PROJECT --quiet

# Check if service project is associated with host project
echo "Checking if service project is associated with host project..."
check_command gcloud compute shared-vpc associated-projects list $HOST_PROJECT --quiet | grep -q $SERVICE_PROJECT

# Check network and subnet existence
echo "Checking if Shared VPC network exists..."
check_command gcloud compute networks describe $SHARED_VPC_NAME --project=$HOST_PROJECT --quiet

echo "Checking if subnet exists..."
check_command gcloud compute networks subnets describe $SHARED_SUBNET_NAME --region=$REGION --project=$HOST_PROJECT --quiet

# Check firewall rules
echo "Checking firewall rules..."
if gcloud compute firewall-rules list --filter="network:$SHARED_VPC_NAME" --project=$HOST_PROJECT --quiet | grep -q .; then
    echo "PASSED: Firewall rules exist for the Shared VPC"
else
    echo "FAILED: No firewall rules found for the Shared VPC"
fi

# Check IAM permissions
echo "Checking IAM permissions..."

for ROLE in roles/dataflow.admin roles/dataflow.serviceAgent roles/compute.networkUser roles/storage.objectViewer
do
    echo "Checking $ROLE on host project..."
    if gcloud projects get-iam-policy $HOST_PROJECT --format=json | jq -e '.bindings[] | select(.role=="'$ROLE'") | .members[]' | grep -q $SA_EMAIL; then
        echo "PASSED: $ROLE found for $SA_EMAIL on host project"
    else
        echo "FAILED: $ROLE not found for $SA_EMAIL on host project"
    fi
done

echo "Checking compute.networkUser role on subnet..."
if gcloud compute networks subnets get-iam-policy $SHARED_SUBNET_NAME --region=$REGION --project=$HOST_PROJECT --format=json | jq -e '.bindings[] | select(.role=="roles/compute.networkUser") | .members[]' | grep -q $SA_EMAIL; then
    echo "PASSED: compute.networkUser role found for $SA_EMAIL on subnet"
else
    echo "FAILED: compute.networkUser role not found for $SA_EMAIL on subnet"
fi

echo "Checking dataflow.worker role on service project..."
if gcloud projects get-iam-policy $SERVICE_PROJECT --format=json | jq -e '.bindings[] | select(.role=="roles/dataflow.worker") | .members[]' | grep -q $SA_EMAIL; then
    echo "PASSED: dataflow.worker role found for $SA_EMAIL on service project"
else
    echo "FAILED: dataflow.worker role not found for $SA_EMAIL on service project"
fi

# Check APIs enabled
echo "Checking if necessary APIs are enabled..."
for API in compute.googleapis.com redis.googleapis.com servicenetworking.googleapis.com
do
    if gcloud services list --project=$HOST_PROJECT --quiet | grep -q $API; then
        echo "PASSED: $API is enabled on host project"
    else
        echo "FAILED: $API is not enabled on host project"
    fi
done

for API in compute.googleapis.com dataflow.googleapis.com
do
    if gcloud services list --project=$SERVICE_PROJECT --quiet | grep -q $API; then
        echo "PASSED: $API is enabled on service project"
    else
        echo "FAILED: $API is not enabled on service project"
    fi
done

# Check for GCS bucket
echo "Checking for GCS bucket..."
if gsutil ls -p $SERVICE_PROJECT | grep -q "$SERVICE_PROJECT-temp-$REGION"; then
    echo "PASSED: GCS bucket found"
else
    echo "FAILED: GCS bucket not found"
fi

# Check for Redis instance
echo "Checking for Redis instance..."
if gcloud redis instances list --region=$REGION --project=$HOST_PROJECT --quiet | grep -q .; then
    echo "PASSED: Redis instance found"
else
    echo "FAILED: No Redis instance found"
fi

echo "Check complete. Please review the output for any failed configurations or permissions."
