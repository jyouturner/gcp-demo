#!/bin/bash

# Load environment variables
source .env

CLUSTER_NAME="test123"
# Function to create cluster
create_cluster() {
    local zone=$1
    local zone_flag=""
    if [ -n "$zone" ]; then
        zone_flag="--zone=$zone"
    fi

    gcloud dataproc clusters create $CLUSTER_NAME \
        --project=$SERVICE_PROJECT_NAME \
        --region=$REGION \
        --subnet=projects/$HOST_PROJECT_NAME/regions/$REGION/subnetworks/$SHARED_SUBNET_NAME \
        --no-address \
        --master-machine-type=n1-standard-2 \
        --master-boot-disk-size=500GB \
        --num-workers=2 \
        --worker-machine-type=n1-standard-2 \
        --worker-boot-disk-size=500GB \
        --image-version=2.0-debian10 \
        $zone_flag
}

# Try creating cluster with Auto Zone
echo "Attempting to create cluster with Auto Zone..."
if create_cluster; then
    echo "Cluster created successfully with Auto Zone."
    exit 0
fi

# If Auto Zone fails, try specific zones
zones=("us-central1-a" "us-central1-c" "us-central1-f")
for zone in "${zones[@]}"; do
    echo "Attempting to create cluster in zone $zone..."
    if create_cluster $zone; then
        echo "Cluster created successfully in zone $zone."
        exit 0
    fi
done

echo "Failed to create cluster in any zone. Please try again later or check your project quotas."
exit 1