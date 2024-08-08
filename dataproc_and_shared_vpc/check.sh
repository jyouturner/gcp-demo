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
echo "Please enter the following details:"
read -p "Host Project ID: " HOST_PROJECT
read -p "Service Project ID: " DATAPROC_PROJECT
read -p "Shared Network Name: " NETWORK
read -p "Shared Subnet Name: " SUBNET
read -p "Region: " REGION

if [[ -z "$(gcloud config get-value project)" ]]; then
    gcloud auth login
fi

# print the current gcloud account
gcloud auth list


# 1. Verify Dataproc Cluster Project Number
print_info "Verifying Dataproc Cluster Project Number..."
gcloud config set project $DATAPROC_PROJECT >/dev/null 2>&1
PROJECT_NUMBER=$(gcloud projects describe $DATAPROC_PROJECT --format="value(projectNumber)" 2>/dev/null)
print_status "Project number for $DATAPROC_PROJECT: $PROJECT_NUMBER"

# 2. Verify Shared VPC Host Project Configuration
print_info "Verifying Shared VPC Host Project Configuration..."
gcloud config set project $HOST_PROJECT >/dev/null 2>&1
HOST_PROJECTS=$(gcloud compute shared-vpc organizations list-host-projects 2>/dev/null)
if echo "$HOST_PROJECTS" | grep -q "$HOST_PROJECT"; then
    print_status "$HOST_PROJECT is a Shared VPC host project"
else
    print_status "$HOST_PROJECT is NOT a Shared VPC host project"
fi

# Check if Dataproc project is associated
ASSOCIATED_PROJECTS=$(gcloud compute shared-vpc associated-projects list --host-project=$HOST_PROJECT 2>/dev/null)
if echo "$ASSOCIATED_PROJECTS" | grep -q "$DATAPROC_PROJECT"; then
    print_status "$DATAPROC_PROJECT is associated with the host project"
else
    print_status "$DATAPROC_PROJECT is NOT associated with the host project"
fi

# 3. Check Service Account Permissions
print_info "Checking Service Account Permissions..."
DATAPROC_SA="service-${PROJECT_NUMBER}@dataproc-accounts.iam.gserviceaccount.com"
GOOGLE_APIS_SA="${PROJECT_NUMBER}@cloudservices.gserviceaccount.com"

check_iam_binding() {
    local project=$1
    local member=$2
    local role=$3
    if gcloud projects get-iam-policy $project --flatten="bindings[].members" --format="table(bindings.role,bindings.members)" 2>/dev/null | grep -q "$member.*$role"; then
        print_status "$member has $role on $project"
    else
        print_status "$member does NOT have $role on $project"
    fi
}

check_iam_binding $HOST_PROJECT $DATAPROC_SA "roles/compute.networkUser"
check_iam_binding $HOST_PROJECT $GOOGLE_APIS_SA "roles/compute.networkUser"

# 4. Verify VPC Network Configuration
print_info "Verifying VPC Network Configuration..."
SUBNET_IAM=$(gcloud compute networks subnets get-iam-policy $SUBNET --region=$REGION --project=$HOST_PROJECT 2>/dev/null)
if echo "$SUBNET_IAM" | grep -q "$DATAPROC_SA.*roles/compute.networkUser"; then
    print_status "Dataproc service account has networkUser role on subnet $SUBNET"
else
    print_status "Dataproc service account does NOT have networkUser role on subnet $SUBNET"
fi
if echo "$SUBNET_IAM" | grep -q "$GOOGLE_APIS_SA.*roles/compute.networkUser"; then
    print_status "Google APIs service account has networkUser role on subnet $SUBNET"
else
    print_status "Google APIs service account does NOT have networkUser role on subnet $SUBNET"
fi

# 5. Check Firewall Rules
print_info "Checking Firewall Rules..."
FIREWALL_RULES=$(gcloud compute firewall-rules list --project=$HOST_PROJECT 2>/dev/null)
if echo "$FIREWALL_RULES" | grep -q "allow.*tcp:6379"; then
    print_status "Firewall rule allowing traffic to Redis port 6379 exists"
else
    print_status "No firewall rule found allowing traffic to Redis port 6379"
fi

# 6. Verify MemoryStore Instance Configuration
print_info "Verifying MemoryStore Instance Configuration..."
REDIS_INSTANCES=$(gcloud redis instances list --region=$REGION --project=$HOST_PROJECT 2>/dev/null)
if [ -z "$REDIS_INSTANCES" ]; then
    print_status "No Redis instances found in $HOST_PROJECT in region $REGION"
else
    print_info "Redis instances found. Please verify manually that they are configured with the correct network: $NETWORK"
    echo "$REDIS_INSTANCES"
fi

print_info "Verification complete. Please review the results above for any configuration issues."