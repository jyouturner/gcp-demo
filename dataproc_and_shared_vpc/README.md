# GCP Dataproc To Access Resources in Shared VPC

In this experiement, we proceed to test dataproc job accessing a Memorystore (redis) through Shared VPC.

Most of the setups are same or similar to the step listed in dataflow_and_shared_vpc

## Create Projects, Shared VPC, And Share between Projects

refer to the README.md in ../dataflow_and_shared_vpc

## Create Redis Instance

refer to the README.md in ../dataflow_and_shared_vpc

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