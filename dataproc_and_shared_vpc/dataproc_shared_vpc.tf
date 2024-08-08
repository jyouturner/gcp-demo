# Define variables
variable "service_project" {}
variable "host_project" {}
variable "region" {}
variable "shared_subnet_name" {}
variable "shared_vpc_name" {}
variable "subnet_range" {}

# Get the service project number
data "google_project" "service_project" {
  project_id = var.service_project
}

locals {
  service_project_number = data.google_project.service_project.number
  dataproc_sa            = "service-${local.service_project_number}@dataproc-accounts.iam.gserviceaccount.com"
  compute_sa             = "${local.service_project_number}-compute@developer.gserviceaccount.com"
  google_apis_sa         = "${local.service_project_number}@cloudservices.gserviceaccount.com"
}

# Enable necessary APIs in the service project
resource "google_project_service" "compute_api" {
  project = var.service_project
  service = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dataproc_api" {
  project = var.service_project
  service = "dataproc.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudresourcemanager_api" {
  project = var.service_project
  service = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking_api" {
  project = var.service_project
  service = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

# Add IAM policy bindings to host project for Dataproc SA
resource "google_project_iam_member" "host_project_dataproc_networkuser" {
  project = var.host_project
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:${local.dataproc_sa}"
}

# Add IAM policy bindings to host project for Google APIs SA
resource "google_project_iam_member" "host_project_googleapis_networkuser" {
  project = var.host_project
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:${local.google_apis_sa}"
}

# Add IAM policy bindings to service project for Compute SA
resource "google_project_iam_member" "service_project_compute_dataprocworker" {
  project = var.service_project
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${local.compute_sa}"
}

resource "google_project_iam_member" "service_project_compute_dataprocserviceagent" {
  project = var.service_project
  role    = "roles/dataproc.serviceAgent"
  member  = "serviceAccount:${local.compute_sa}"
}

# Add IAM policy bindings to shared subnet
resource "google_compute_subnetwork_iam_member" "shared_subnet_dataproc" {
  project    = var.host_project
  region     = var.region
  subnetwork = var.shared_subnet_name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${local.dataproc_sa}"
}

resource "google_compute_subnetwork_iam_member" "shared_subnet_googleapis" {
  project    = var.host_project
  region     = var.region
  subnetwork = var.shared_subnet_name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${local.google_apis_sa}"
}

# Enable Private Google Access on the shared subnet
resource "google_compute_subnetwork" "update_subnet" {
  project                  = var.host_project
  name                     = var.shared_subnet_name
  region                   = var.region
  network                  = var.shared_vpc_name
  private_ip_google_access = true

  # You need to specify other required fields here, such as ip_cidr_range
  # Make sure this doesn't conflict with your existing subnet configuration
  ip_cidr_range = var.subnet_range
}

# Create firewall rule for Redis
resource "google_compute_firewall" "allow_dataproc_to_redis" {
  name    = "allow-dataproc-to-redis"
  network = var.shared_vpc_name
  project = var.host_project

  allow {
    protocol = "tcp"
    ports    = ["6379"]
  }

  source_ranges = [var.subnet_range]
  target_tags   = ["redis"]
}

# Output the service accounts for reference
output "dataproc_service_account" {
  value = local.dataproc_sa
}

output "compute_service_account" {
  value = local.compute_sa
}

output "google_apis_service_account" {
  value = local.google_apis_sa
}