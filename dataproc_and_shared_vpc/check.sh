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

# Set your environment variables
source .env

if [[ -z "$(gcloud config get-value project)" ]]; then
    gcloud auth login
fi

# print the current gcloud account
gcloud auth list

# 1. Verify Dataproc Cluster Project Number
print_info "Verifying Dataproc Cluster Project Number..."
gcloud config set project $SERVICE_PROJECT_NAME >/dev/null 2>&1
PROJECT_NUMBER=$(gcloud projects describe $SERVICE_PROJECT_NAME --format="value(projectNumber)" 2>/dev/null)
print_status "Project number for $SERVICE_PROJECT_NAME: $PROJECT_NUMBER"

# 2. Verify Shared VPC Host Project Configuration
print_info "Verifying Shared VPC Host Project Configuration..."
gcloud config set project $HOST_PROJECT_NAME >/dev/null 2>&1
HOST_PROJECTS=$(gcloud compute shared-vpc organizations list-host-projects $ORG_ID 2>/dev/null)
if echo "$HOST_PROJECTS" | grep -q "$HOST_PROJECT_NAME"; then
    print_status "$HOST_PROJECT_NAME is a Shared VPC host project"
else
    print_status "$HOST_PROJECT_NAME is NOT a Shared VPC host project"
fi

# Check if Dataproc project is associated
ASSOCIATED_PROJECTS=$(gcloud compute shared-vpc associated-projects list --project=$HOST_PROJECT_NAME 2>/dev/null)
if echo "$ASSOCIATED_PROJECTS" | grep -q "$SERVICE_PROJECT_NAME"; then
    print_status "$SERVICE_PROJECT_NAME is associated with the host project"
else
    print_status "$SERVICE_PROJECT_NAME is NOT associated with the host project"
fi

# Function to check role for service account
check_role() {
    local project=$1
    local role=$2
    local sa=$3
    local resource_type=$4
    local resource_name=$5
    if [ "$resource_type" = "project" ]; then
        if gcloud projects get-iam-policy $project --format=json | jq -e '.bindings[] | select(.role=="'$role'") | .members[]' | grep -q $sa; then
            print_status "PASSED: $role found for $sa on $resource_type $project"
        else
            print_status "FAILED: $role not found for $sa on $resource_type $project"
        fi
    elif [ "$resource_type" = "subnet" ]; then
        if gcloud compute networks subnets get-iam-policy $resource_name --region=$REGION --project=$project --format=json | jq -e '.bindings[] | select(.role=="'$role'") | .members[]' | grep -q $sa; then
            print_status "PASSED: $role found for $sa on $resource_type $resource_name"
        else
            print_status "FAILED: $role not found for $sa on $resource_type $resource_name"
        fi
    fi
}

# 3. Check Service Account Permissions
print_info "Checking Service Account Permissions..."
DATAPROC_SA="serviceAccount:service-${PROJECT_NUMBER}@dataproc-accounts.iam.gserviceaccount.com"
GOOGLE_APIS_SA="serviceAccount:${PROJECT_NUMBER}@cloudservices.gserviceaccount.com"

check_role $HOST_PROJECT_NAME "roles/compute.networkUser" $DATAPROC_SA "project" $HOST_PROJECT_NAME
check_role $HOST_PROJECT_NAME "roles/compute.networkUser" $GOOGLE_APIS_SA "project" $HOST_PROJECT_NAME

# Check Dataproc Worker role
# check_role $SERVICE_PROJECT_NAME "roles/dataproc.worker" $DATAPROC_SA "project" $SERVICE_PROJECT_NAME
check_role $SERVICE_PROJECT_NAME "roles/dataproc.serviceAgent" $DATAPROC_SA "project" $SERVICE_PROJECT_NAME

check_api_enabled() {
    local project=$1
    local api=$2
    if gcloud services list --project=$project | grep -q $api; then
        print_status "PASSED: $api is enabled in project $project"
    else
        print_status "FAILED: $api is not enabled in project $project"
    fi
}

check_compute_sa_permissions() {
    local project=$1
    local sa="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
    check_role $project "roles/dataproc.worker" $sa "project" $project
    check_role $project "roles/dataproc.serviceAgent" $sa "project" $project
}

print_info "Checking if Cloud Resource Manager API is enabled..."
check_api_enabled $SERVICE_PROJECT_NAME "cloudresourcemanager.googleapis.com"

print_info "Checking Compute Engine default service account permissions..."
check_compute_sa_permissions $SERVICE_PROJECT_NAME

# 4. Verify VPC Network Configuration
print_info "Verifying VPC Network Configuration..."
check_role $HOST_PROJECT_NAME "roles/compute.networkUser" $DATAPROC_SA "subnet" $SHARED_SUBNET_NAME
check_role $HOST_PROJECT_NAME "roles/compute.networkUser" $GOOGLE_APIS_SA "subnet" $SHARED_SUBNET_NAME

# Check Private Google Access
# Verify Private Google Access is enabled
PRIVATE_ACCESS=$(gcloud compute networks subnets describe $SHARED_SUBNET_NAME --region=$REGION --project=$HOST_PROJECT_NAME --format="get(privateIpGoogleAccess)")
if [ "$PRIVATE_ACCESS" = "true" ]; then
    print_status "Verified: Private Google Access is enabled on subnet $SHARED_SUBNET_NAME"
elif [ "$PRIVATE_ACCESS" = "True" ]; then
    print_status "Verified: Private Google Access is enabled on subnet $SHARED_SUBNET_NAME (capitalized 'True')"
else
    print_status "Error: Private Google Access is NOT enabled on subnet $SHARED_SUBNET_NAME"
    print_info "Current Private Google Access status: $PRIVATE_ACCESS"
fi

# Additional debugging information
print_info "Subnet details:"
gcloud compute networks subnets describe $SHARED_SUBNET_NAME --region=$REGION --project=$HOST_PROJECT_NAME --format="yaml(privateIpGoogleAccess)"

# 5. Check Firewall Rules
print_info "Checking Firewall Rules..."
FIREWALL_RULES=$(gcloud compute firewall-rules list --project=$HOST_PROJECT_NAME 2>/dev/null)
if echo "$FIREWALL_RULES" | grep -q "allow.*tcp:6379"; then
    print_status "PASSED: Firewall rule allowing traffic to Redis port 6379 exists"
else
    print_status "FAILED: No firewall rule found allowing traffic to Redis port 6379"
fi

# 6. Verify MemoryStore Instance Configuration
#print_info "Verifying MemoryStore Instance Configuration..."
#REDIS_INSTANCES=$(gcloud redis instances list --region=$REGION --project=$HOST_PROJECT_NAME 2>/dev/null)
#if [ -z "$REDIS_INSTANCES" ]; then
#    print_status "FAILED: No Redis instances found in $HOST_PROJECT_NAME in region $REGION"
#else
#    print_info "Redis instances found. Please verify manually that they are configured with the correct network: $SHARED_VPC_NAME"
#    echo "$REDIS_INSTANCES"
#fi

# 7. Check VPC Peering for Redis
print_info "Checking VPC Peering for Redis..."
VPC_PEERINGS=$(gcloud compute networks peerings list --network=$SHARED_VPC_NAME --project=$HOST_PROJECT_NAME)
if echo "$VPC_PEERINGS" | grep -q "servicenetworking-googleapis-com"; then
    print_status "PASSED: VPC peering for Redis exists"
else
    print_status "FAILED: VPC peering for Redis not found"
fi

# 8. Check Dataproc API enabled
print_info "Checking if Dataproc API is enabled..."
if gcloud services list --project=$SERVICE_PROJECT_NAME | grep -q dataproc.googleapis.com; then
    print_status "PASSED: Dataproc API is enabled"
else
    print_status "FAILED: Dataproc API is not enabled"
fi

print_info "Verification complete. Please review the results above for any configuration issues."