# GCP Dataflow To Access Resources in Shared VPC

The purpose of this project is to identify necessary permissions and settings on GCP to allow dataflow job to access resources in Shared VPC between projects.

Note, Shared VPC is a feature only available to premium customers (ie, those with Google Workspace or Identity). There is free trial (14 days) that you can leverage to experiement below operations.


A Shared VPC consists of a host project and one or more service projects. The host project contains the shared VPC network, while service projects can use this network to deploy their resources.


## Set up environment variables:

```sh
cp dot.env.example .env  
```
then edit the .env

```

ORG_ID=<your-org-id>
BILLING_ACCOUNT_ID=<your-billing-account-id>
HOST_PROJECT_NAME=host-project-123
SERVICE_PROJECT_NAME=service-project-123
SHARED_VPC_NAME=shared-vpc-123
SHARED_SUBNET_NAME=shared-subnet-123
SUBNET_RANGE=10.194.0.0/24
REGION=us-central1
REDIS_INSTANCE_NAME=my-redis-123
```

and load

```sh
source .env
```

## Create projects:
  

```bash

gcloud  projects  create  $HOST_PROJECT_NAME  --organization=$ORG_ID

gcloud  projects  create  $SERVICE_PROJECT_NAME  --organization=$ORG_ID

HOST_PROJECT=$(gcloud  projects  list  --filter=name:$HOST_PROJECT_NAME  --format="value(projectId)")

SERVICE_PROJECT=$(gcloud  projects  list  --filter=name:$SERVICE_PROJECT_NAME  --format="value(projectId)")

```

## Link billing accounts:

```bash

gcloud billing projects link $HOST_PROJECT --billing-account=$BILLING_ACCOUNT_ID

gcloud billing projects link $SERVICE_PROJECT --billing-account=$BILLING_ACCOUNT_ID

```

## Enable necessary APIs:

```bash

gcloud config set project $HOST_PROJECT

gcloud services enable compute.googleapis.com redis.googleapis.com servicenetworking.googleapis.com

gcloud config set project $SERVICE_PROJECT

gcloud services enable compute.googleapis.com dataflow.googleapis.com

```

## Create Shared VPC network in host project:

```bash

gcloud config set project $HOST_PROJECT

gcloud compute networks create $SHARED_VPC_NAME --subnet-mode=custom

gcloud compute networks subnets create $SHARED_SUBNET_NAME \
--network=$SHARED_VPC_NAME \
--region=$REGION \
--range=$SUBNET_RANGE

```

## Firewalls

```sh
gcloud compute firewall-rules create allow-internal-shared-vpc \
    --network $SHARED_VPC_NAME \
    --allow tcp,udp,icmp \
    --source-ranges $SUBNET_RANGE \
    --project $HOST_PROJECT

# if necessary
#gcloud compute firewall-rules create allow-ssh-rdp-icmp-shared-vpc \
#    --network $SHARED_VPC_NAME \
#    --allow tcp:22,tcp:3389,icmp \
#    --source-ranges 0.0.0.0/0 \
#    --project $HOST_PROJECT

```

## Enable Shared VPC and associate service project:

```bash

gcloud compute shared-vpc enable $HOST_PROJECT

gcloud compute shared-vpc associated-projects add $SERVICE_PROJECT --host-project=$HOST_PROJECT

```

## Create service account for Dataflow:

```bash

gcloud config set project $SERVICE_PROJECT

gcloud iam service-accounts create dataflow-sa --display-name="Dataflow Service Account"

SA_EMAIL=$(gcloud iam service-accounts list --filter="displayName:Dataflow Service Account" --format="value(email)")

```

## Set up necessary permissions:

```bash

SERVICE_PROJECT_NUMBER=$(gcloud projects describe $SERVICE_PROJECT --format="value(projectNumber)")
echo $SERVICE_PROJECT_NUMBER
COMPUTE_SA="${SERVICE_PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo $COMPUTE_SA
DATAFLOW_AGENT_SA="service-${SERVICE_PROJECT_NUMBER}@dataflow-service-producer-prod.iam.gserviceaccount.com"
echo $DATAFLOW_AGENT_SA
for ROLE in roles/dataflow.admin roles/dataflow.serviceAgent roles/compute.networkUser roles/storage.objectViewer

do

gcloud projects add-iam-policy-binding $HOST_PROJECT \
--member="serviceAccount:$SA_EMAIL" \
--role="$ROLE"

gcloud projects add-iam-policy-binding $HOST_PROJECT \
--member="serviceAccount:$COMPUTE_SA" \
--role="$ROLE"

gcloud projects add-iam-policy-binding $HOST_PROJECT \
--member="serviceAccount:$DATAFLOW_AGENT_SA" \
--role="$ROLE"

done

gcloud compute networks subnets add-iam-policy-binding $SHARED_SUBNET_NAME \
--project=$HOST_PROJECT \
--region=$REGION \
--member="serviceAccount:$SA_EMAIL" \
--role="roles/compute.networkUser"

gcloud compute networks subnets add-iam-policy-binding $SHARED_SUBNET_NAME \
--project=$HOST_PROJECT \
--region=$REGION \
--member="serviceAccount:$COMPUTE_SA" \
--role="roles/compute.networkUser"

gcloud compute networks subnets add-iam-policy-binding $SHARED_SUBNET_NAME \
--project=$HOST_PROJECT \
--region=$REGION \
--member="serviceAccount:$DATAFLOW_AGENT_SA" \
--role="roles/compute.networkUser"

gcloud projects add-iam-policy-binding $SERVICE_PROJECT \
--member="serviceAccount:$SA_EMAIL" \
--role="roles/dataflow.worker"
```

## Create a GCS bucket for Dataflow temp files:

```bash

gsutil mb -l $REGION gs://$SERVICE_PROJECT-temp-$REGION

gsutil iam ch serviceAccount:$SA_EMAIL:objectAdmin gs://$SERVICE_PROJECT-temp-$REGION

gcloud projects add-iam-policy-binding $SERVICE_PROJECT \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/storage.objectCreator"

```

## Run Simple Dataflow with Shared VPC Networking

```bash
gcloud config set project $SERVICE_PROJECT
    
PARAMS="inputFile=gs://dataflow-samples/shakespeare/kinglear.txt,output=gs://$SERVICE_PROJECT-temp-$REGION/output"

gcloud dataflow jobs run test-job \
    --gcs-location gs://dataflow-templates/latest/Word_Count \
    --region $REGION \
    --network https://www.googleapis.com/compute/v1/projects/$HOST_PROJECT/global/networks/$SHARED_VPC_NAME \
    --subnetwork https://www.googleapis.com/compute/v1/projects/$HOST_PROJECT/regions/$REGION/subnetworks/$SHARED_SUBNET_NAME \
    --service-account-email $SA_EMAIL \
    --staging-location gs://$SERVICE_PROJECT-temp-$REGION/staging \
    --parameters $PARAMS \
    --verbosity=debug
```



## Create A Minimal Redis instance in Host Project:

```bash

gcloud redis instances create $REDIS_INSTANCE_NAME \
--tier=basic \
--size=1 \
--region=$REGION \
--network=$SHARED_VPC_NAME \
--connect-mode=PRIVATE_SERVICE_ACCESS \
--project=$HOST_PROJECT \
--redis-version=redis_6_x

```

## Set up private services access for Redis in Shared VPC:

```bash

gcloud compute addresses create google-managed-services-shared-vpc \
--global \
--purpose=VPC_PEERING \
--prefix-length=16 \
--network=$SHARED_VPC_NAME \
--project=$HOST_PROJECT

gcloud services vpc-peerings connect \
--service=servicenetworking.googleapis.com \
--ranges=google-managed-services-shared-vpc \
--network=$SHARED_VPC_NAME \
--project=$HOST_PROJECT
```

## Set up Firewall

```bash
gcloud compute firewall-rules create allow-redis-shared-vpc \
    --network $SHARED_VPC_NAME \
    --allow tcp:6379 \
    --source-ranges $SUBNET_RANGE \
    --project $HOST_PROJECT
```

## Create the DataFlow Template

```sh
gcloud config set project $SERVICE_PROJECT
gcloud auth application-default login
```

```sh
mvn compile exec:java \
 -Dexec.mainClass=com.example.WriteToRedis \
 -Dexec.args="--runner=DataflowRunner \
               --project=$SERVICE_PROJECT \
               --region=$REGION \
               --gcpTempLocation=gs://$SERVICE_PROJECT-temp-$REGION/temp \
               --stagingLocation=gs://$SERVICE_PROJECT-temp-$REGION/staging \
               --templateLocation=gs://$SERVICE_PROJECT-temp-$REGION/templates/redis-writer-template \
               --redisHost=$REDIS_HOST \
               --redisPort=$REDIS_PORT"

gsutil ls gs://$SERVICE_PROJECT-temp-$REGION/templates/
```

## Run the Dataflow job:

```bash


REDIS_HOST=$(gcloud redis instances describe $REDIS_INSTANCE_NAME --region=$REGION --project=$HOST_PROJECT --format='get(host)')

echo $REDIS_HOST

REDIS_PORT=6379

# Run the Dataflow job
gcloud dataflow jobs run redis-writer-job \
    --gcs-location=gs://$SERVICE_PROJECT-temp-$REGION/templates/redis-writer-template \
    --region=$REGION \
    --network=https://www.googleapis.com/compute/v1/projects/$HOST_PROJECT/global/networks/$SHARED_VPC_NAME \
    --subnetwork=https://www.googleapis.com/compute/v1/projects/$HOST_PROJECT/regions/$REGION/subnetworks/$SHARED_SUBNET_NAME \
    --service-account-email=$SA_EMAIL \
    --parameters=redisHost=$REDIS_HOST,redisPort=$REDIS_PORT \
    --project=$SERVICE_PROJECT

```

  

## clean up

  

1. First, let's set our environment variables again (if you're in a new session):

  

```bash

source .env

```

  

### Delete the Dataflow job (if it's still running):

  

```bash

gcloud  dataflow  jobs  list  --region=$REGION  --project=$SERVICE_PROJECT

# Note the Job ID, then run:

gcloud  dataflow  jobs  cancel  JOB_ID  --region=$REGION  --project=$SERVICE_PROJECT

```

### Delete the GCS bucket:

```bash
gsutil  rm  -r  gs://$SERVICE_PROJECT-temp-$REGION

```

  

### Delete Redis instance

```sh
gcloud  config  set  project  $HOST_PROJECT

gcloud  redis  instances  delete  $REDIS_INSTANCE_NAME  --region=$REGION

```

  

### Remove the VPC peering for private services access:

```bash
gcloud  services  vpc-peerings  delete  \
--service=servicenetworking.googleapis.com \
--network=$SHARED_VPC_NAME  \
--project=$HOST_PROJECT
```


### Delete the reserved IP addresses for VPC peering:

```bash
gcloud  compute  addresses  delete  google-managed-services-shared-vpc  \
--global \
--project=$HOST_PROJECT
```

  

### Remove the service project from the Shared VPC:

  

```bash
gcloud  compute  shared-vpc  associated-projects  remove  $SERVICE_PROJECT  \
--host-project=$HOST_PROJECT
```

  

### Disable Shared VPC on the host project:

```bash
gcloud  compute  shared-vpc  disable  $HOST_PROJECT
```

### Delete the subnet and VPC:

```bash
gcloud  compute  networks  subnets  delete  $SHARED_SUBNET_NAME  \
--region=$REGION \
--project=$HOST_PROJECT

  
gcloud  compute  networks  delete  $SHARED_VPC_NAME  --project=$HOST_PROJECT
```

  

### Delete the service account:

```sh

gcloud  config  set  project  $SERVICE_PROJECT

SA_EMAIL=$(gcloud  iam  service-accounts  list  --filter="displayName:Dataflow Service Account"  --format="value(email)")

gcloud  iam  service-accounts  delete  $SA_EMAIL
```

### Finally, delete both projects:

```sh
gcloud  projects  delete  $SERVICE_PROJECT

gcloud  projects  delete  $HOST_PROJECT
```