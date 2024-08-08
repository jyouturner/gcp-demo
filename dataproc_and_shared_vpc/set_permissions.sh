#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} $1"
    else
        echo -e "${RED}[FAIL]${NC} $1"
    fi
}

# Function to print info
print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Load environment variables
source .env

# Ensure required variables are set
required_vars=(SERVICE_PROJECT_NAME HOST_PROJECT_NAME REGION SHARED_SUBNET_NAME SHARED_VPC_NAME)
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set in .env file"
        exit 1
    fi
done

# Get project numbers
SERVICE_PROJECT_NUMBER=$(gcloud projects describe $SERVICE_PROJECT_NAME --format="value(projectNumber)")
HOST_PROJECT_NUMBER=$(gcloud projects describe $HOST_PROJECT_NAME --format="value(projectNumber)")

# Service account email addresses
DATAPROC_SA="service-${SERVICE_PROJECT_NUMBER}@dataproc-accounts.iam.gserviceaccount.com"
COMPUTE_SA="${SERVICE_PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
GOOGLE_APIS_SA="${SERVICE_PROJECT_NUMBER}@cloudservices.gserviceaccount.com"

print_info "Enabling necessary APIs..."
apis=(
    "compute.googleapis.com"
    "dataproc.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "servicenetworking.googleapis.com"
)

for api in "${apis[@]}"; do
    gcloud services enable $api --project=$SERVICE_PROJECT_NAME
    print_status "Enabled $api in $SERVICE_PROJECT_NAME"
done

print_info "Granting permissions on the host project..."
gcloud projects add-iam-policy-binding $HOST_PROJECT_NAME \
    --member="serviceAccount:${DATAPROC_SA}" \
    --role="roles/compute.networkUser"
print_status "Granted compute.networkUser to Dataproc SA on host project"

gcloud projects add-iam-policy-binding $HOST_PROJECT_NAME \
    --member="serviceAccount:${GOOGLE_APIS_SA}" \
    --role="roles/compute.networkUser"
print_status "Granted compute.networkUser to Google APIs SA on host project"

print_info "Granting permissions on the service project..."
gcloud projects add-iam-policy-binding $SERVICE_PROJECT_NAME \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/dataproc.worker"
print_status "Granted dataproc.worker to Compute SA on service project"

gcloud projects add-iam-policy-binding $SERVICE_PROJECT_NAME \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/dataproc.serviceAgent"
print_status "Granted dataproc.serviceAgent to Compute SA on service project"

print_info "Granting permissions on the shared subnet..."
gcloud compute networks subnets add-iam-policy-binding $SHARED_SUBNET_NAME \
    --project=$HOST_PROJECT_NAME \
    --region=$REGION \
    --member="serviceAccount:${DATAPROC_SA}" \
    --role="roles/compute.networkUser"
print_status "Granted compute.networkUser to Dataproc SA on shared subnet"

gcloud compute networks subnets add-iam-policy-binding $SHARED_SUBNET_NAME \
    --project=$HOST_PROJECT_NAME \
    --region=$REGION \
    --member="serviceAccount:${GOOGLE_APIS_SA}" \
    --role="roles/compute.networkUser"
print_status "Granted compute.networkUser to Google APIs SA on shared subnet"

print_info "Enabling Private Google Access on the shared subnet..."
if gcloud compute networks subnets update $SHARED_SUBNET_NAME \
    --region=$REGION \
    --project=$HOST_PROJECT_NAME \
    --enable-private-ip-google-access 2>/dev/null; then
    print_status "Command to enable Private Google Access executed successfully"
else
    print_status "Failed to execute command to enable Private Google Access"
fi

# Verify Private Google Access is enabled
PRIVATE_ACCESS=$(gcloud compute networks subnets describe $SHARED_SUBNET_NAME --region=$REGION --project=$HOST_PROJECT_NAME --format="get(privateIpGoogleAccess)")
if [ "$PRIVATE_ACCESS" = "true" ]; then
    print_status "Verified: Private Google Access is enabled on subnet $SHARED_SUBNET_NAME"
else
    print_status "Error: Private Google Access is NOT enabled on subnet $SHARED_SUBNET_NAME"
    print_info "Current Private Google Access status: $PRIVATE_ACCESS"
fi

# Additional debugging information
print_info "Subnet details:"
gcloud compute networks subnets describe $SHARED_SUBNET_NAME --region=$REGION --project=$HOST_PROJECT_NAME --format="yaml(privateIpGoogleAccess)"

# Verify Private Google Access is enabled
PRIVATE_ACCESS=$(gcloud compute networks subnets describe $SHARED_SUBNET_NAME --region=$REGION --project=$HOST_PROJECT_NAME --format="get(privateIpGoogleAccess)")
if [ "$PRIVATE_ACCESS" = "true" ]; then
    print_status "Verified: Private Google Access is enabled on subnet $SHARED_SUBNET_NAME"
else
    print_status "Error: Failed to enable Private Google Access on subnet $SHARED_SUBNET_NAME"
fi

print_info "Creating firewall rule for Redis..."
gcloud compute firewall-rules create allow-dataproc-to-redis \
    --project=$HOST_PROJECT_NAME \
    --network=$SHARED_VPC_NAME \
    --direction=INGRESS \
    --priority=1000 \
    --source-ranges=$SUBNET_RANGE \
    --action=ALLOW \
    --rules=tcp:6379 \
    --target-tags=redis
print_status "Created firewall rule for Redis"

print_info "Setup complete. Please run the check script to verify all permissions."