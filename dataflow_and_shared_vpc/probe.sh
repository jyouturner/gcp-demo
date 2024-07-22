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

if [[ -z "$(gcloud config get-value project)" ]]; then
    gcloud auth login
fi

# print the current gcloud account
gcloud auth list

gcloud config set project $SERVICE_PROJECT --quiet

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

SERVICE_PROJECT_NUMBER=$(gcloud projects describe $SERVICE_PROJECT --format="value(projectNumber)")
echo "Service project number: $SERVICE_PROJECT_NUMBER"
COMPUTE_SA="${SERVICE_PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "Compute SA: $COMPUTE_SA"
DATAFLOW_AGENT_SA="service-${SERVICE_PROJECT_NUMBER}@dataflow-service-producer-prod.iam.gserviceaccount.com"
echo "Dataflow agent SA: $DATAFLOW_AGENT_SA"

# Function to check role for service account
check_role() {
    local project=$1
    local role=$2
    local sa=$3
    local resource_type=$4
    local resource_name=$5

    if [ "$resource_type" = "project" ]; then
        if gcloud projects get-iam-policy $project --format=json | jq -e '.bindings[] | select(.role=="'$role'") | .members[]' | grep -q $sa; then
            echo "PASSED: $role found for $sa on $resource_type $project"
        else
            echo "FAILED: $role not found for $sa on $resource_type $project"
        fi
    elif [ "$resource_type" = "subnet" ]; then
        if gcloud compute networks subnets get-iam-policy $resource_name --region=$REGION --project=$project --format=json | jq -e '.bindings[] | select(.role=="'$role'") | .members[]' | grep -q $sa; then
            echo "PASSED: $role found for $sa on $resource_type $resource_name"
        else
            echo "FAILED: $role not found for $sa on $resource_type $resource_name"
        fi
    fi
}

# Check roles on host project and subnet for all service accounts
for SA in $SA_EMAIL $COMPUTE_SA $DATAFLOW_AGENT_SA
do
    for ROLE in roles/dataflow.admin roles/dataflow.serviceAgent roles/compute.networkUser roles/storage.objectViewer
    do
        check_role $HOST_PROJECT $ROLE $SA "project" $HOST_PROJECT
    done
    check_role $HOST_PROJECT "roles/compute.networkUser" $SA "subnet" $SHARED_SUBNET_NAME
done

# Check dataflow.worker role on service project for SA_EMAIL and COMPUTE_SA
for SA in $SA_EMAIL $COMPUTE_SA
do
    check_role $SERVICE_PROJECT "roles/dataflow.worker" $SA "project" $SERVICE_PROJECT
done


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
