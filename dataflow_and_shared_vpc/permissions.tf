# Define variables
variable "service_project" {}
variable "host_project" {}
variable "region" {}
variable "shared_subnet_name" {}
variable "sa_email" {}

# Get the service project number
data "google_project" "service_project" {
  project_id = var.service_project
}

locals {
  service_project_number = data.google_project.service_project.number
  compute_sa             = "${local.service_project_number}-compute@developer.gserviceaccount.com"
  dataflow_agent_sa      = "service-${local.service_project_number}@dataflow-service-producer-prod.iam.gserviceaccount.com"
}

# Add IAM policy bindings to host project for sa_email
resource "google_project_iam_member" "host_project_sa_dataflow_admin" {
  project = var.host_project
  role    = "roles/dataflow.admin"
  member  = "serviceAccount:${var.sa_email}"
}

resource "google_project_iam_member" "host_project_sa_dataflow_serviceagent" {
  project = var.host_project
  role    = "roles/dataflow.serviceAgent"
  member  = "serviceAccount:${var.sa_email}"
}

resource "google_project_iam_member" "host_project_sa_compute_networkuser" {
  project = var.host_project
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:${var.sa_email}"
}

resource "google_project_iam_member" "host_project_sa_storage_objectviewer" {
  project = var.host_project
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${var.sa_email}"
}

# Add IAM policy bindings to host project for compute_sa
resource "google_project_iam_member" "host_project_compute_dataflow_admin" {
  project = var.host_project
  role    = "roles/dataflow.admin"
  member  = "serviceAccount:${local.compute_sa}"
}

resource "google_project_iam_member" "host_project_compute_dataflow_serviceagent" {
  project = var.host_project
  role    = "roles/dataflow.serviceAgent"
  member  = "serviceAccount:${local.compute_sa}"
}

resource "google_project_iam_member" "host_project_compute_compute_networkuser" {
  project = var.host_project
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:${local.compute_sa}"
}

resource "google_project_iam_member" "host_project_compute_storage_objectviewer" {
  project = var.host_project
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${local.compute_sa}"
}

# Add IAM policy bindings to host project for dataflow_agent_sa
resource "google_project_iam_member" "host_project_dataflow_dataflow_admin" {
  project = var.host_project
  role    = "roles/dataflow.admin"
  member  = "serviceAccount:${local.dataflow_agent_sa}"
}

resource "google_project_iam_member" "host_project_dataflow_dataflow_serviceagent" {
  project = var.host_project
  role    = "roles/dataflow.serviceAgent"
  member  = "serviceAccount:${local.dataflow_agent_sa}"
}

resource "google_project_iam_member" "host_project_dataflow_compute_networkuser" {
  project = var.host_project
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:${local.dataflow_agent_sa}"
}

resource "google_project_iam_member" "host_project_dataflow_storage_objectviewer" {
  project = var.host_project
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${local.dataflow_agent_sa}"
}

# Add IAM policy bindings to shared subnet
resource "google_compute_subnetwork_iam_member" "shared_subnet_sa" {
  project    = var.host_project
  region     = var.region
  subnetwork = var.shared_subnet_name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${var.sa_email}"
}

resource "google_compute_subnetwork_iam_member" "shared_subnet_compute" {
  project    = var.host_project
  region     = var.region
  subnetwork = var.shared_subnet_name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${local.compute_sa}"
}

resource "google_compute_subnetwork_iam_member" "shared_subnet_dataflow" {
  project    = var.host_project
  region     = var.region
  subnetwork = var.shared_subnet_name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${local.dataflow_agent_sa}"
}

# Add IAM policy binding to service project
resource "google_project_iam_member" "service_project_dataflow_worker" {
  project = var.service_project
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${var.sa_email}"
}
