# GCP Dataproc To Access Resources in Shared VPC

In this experiement, we proceed to test dataproc job accessing a Memorystore (redis) through Shared VPC.

Most of the setups are same or similar to the step listed in dataflow_and_shared_vpc

## Create Projects, Shared VPC, And Share between Projects

refer to the README.md in ../dataflow_and_shared_vpc

## Create Redis Instance

refer to the README.md in ../dataflow_and_shared_vpc


## Dataproc Shared VPC Permissions

This section outlines the permissions and configurations set up for running Dataproc jobs in a shared VPC environment.

### Service Accounts

The following service accounts are used:

- Dataproc Service Account: `service-[SERVICE_PROJECT_NUMBER]@dataproc-accounts.iam.gserviceaccount.com`
- Compute Engine Default Service Account: `[SERVICE_PROJECT_NUMBER]-compute@developer.gserviceaccount.com`
- Google APIs Service Account: `[SERVICE_PROJECT_NUMBER]@cloudservices.gserviceaccount.com`

### API Enablement

The following APIs are enabled in the service project:

- Compute Engine API
- Dataproc API
- Cloud Resource Manager API
- Service Networking API

### IAM Permissions

#### Host Project

- Dataproc Service Account:
  - Role: `roles/compute.networkUser`

- Google APIs Service Account:
  - Role: `roles/compute.networkUser`

#### Service Project

- Compute Engine Default Service Account:
  - Roles: 
    - `roles/dataproc.worker`
    - `roles/dataproc.serviceAgent`

#### Shared Subnet

- Dataproc Service Account:
  - Role: `roles/compute.networkUser`

- Google APIs Service Account:
  - Role: `roles/compute.networkUser`

### Network Configurations

- Private Google Access is enabled on the shared subnet.
- A firewall rule is created to allow traffic from the Dataproc cluster to Redis on port 6379.

## Check Permissions

```sh
./check.sh
```

## Set Permissions

use the set_permission.sh for reference

```sh
./set_permissions.sh
```

## create dataproc cluster

```sh
CLUSTER_NAME=mytestcluster003
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
    --image-version=2.0-debian10
```

## Submit Job

```sh
gsutil mb -l $REGION gs://$SERVICE_PROJECT_NAME-temp-$REGION
gsutil iam ch serviceAccount:service-${SERVICE_PROJECT_NUMBER}@dataproc-accounts.iam.gserviceaccount.com:objectAdmin gs://$SERVICE_PROJECT_NAME-temp-$REGION
gcloud projects add-iam-policy-binding $SERVICE_PROJECT_NAME \
  --member="serviceAccount:service-${SERVICE_PROJECT_NUMBER}@dataproc-accounts.iam.gserviceaccount.com" \
  --role="roles/storage.objectCreator"
gsutil iam ch serviceAccount:${SERVICE_PROJECT_NUMBER}-compute@developer.gserviceaccount.com:objectViewer gs://$SERVICE_PROJECT_NAME-temp-$REGION

gcloud projects add-iam-policy-binding $SERVICE_PROJECT_NAME \
    --member="serviceAccount:${SERVICE_PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/storage.objectViewer"

gsutil iam ch serviceAccount:service-${SERVICE_PROJECT_NUMBER}@dataproc-accounts.iam.gserviceaccount.com:objectViewer gs://$SERVICE_PROJECT_NAME-temp-$REGION

gcloud projects add-iam-policy-binding $SERVICE_PROJECT_NAME \
    --member="serviceAccount:service-${SERVICE_PROJECT_NUMBER}@dataproc-accounts.iam.gserviceaccount.com" \
    --role="roles/storage.objectViewer"

mvn clean package
gsutil cp target/redis-hello-world-1.0-SNAPSHOT.jar gs://$SERVICE_PROJECT_NAME-temp-$REGION/

gcloud dataproc jobs submit hadoop \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --class=RedisHelloWorld \
    --jars=gs://$SERVICE_PROJECT_NAME-temp-$REGION/redis-hello-world-1.0-SNAPSHOT.jar \
    --project=$SERVICE_PROJECT_NAME \
     -- 172.29.0.3 6379
```