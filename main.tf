locals {
  # PSC client side
  services        = toset(flatten(tolist([for name in keys(var.ports) : [for i in range(var.brokers) : "${name}-${i}"]])))
  kafka_endpoints = [
    for ep in google_compute_forwarding_rule.endpoint : ep.ip_address if length(regexall("kafka", ep.name)) > 0
  ]
  byoc = split(".", var.domain)[0]

  # PSC server side
  incremented_ports = merge(
    [
      for i in range(var.brokers) : {
      for name, port in var.ports :
      "${name}-${i}" => port + i * var.port-increment
    }
    ]...)
  non_incremented_ports = merge(
    [
      for i in range(var.brokers) : {
      for name, port in var.ports :
      "${name}-${i}" => port
    }
    ]...)
  psc-subnets = {for i, name in keys(local.incremented_ports) : name => "${var.psc-subnet-cidr-prefix}${i * 8}/29"}
}

# VPC for the client side endpoints and VMs
resource "google_compute_network" "client-network" {
  name                    = "${var.prefix}-client-network"
  auto_create_subnetworks = false
}

# Subnet for the client side endpoints
resource "google_compute_subnetwork" "client-subnet" {
  name          = "${var.prefix}-client-subnet"
  ip_cidr_range = var.client_cidr
  region        = var.region
  network       = google_compute_network.client-network.id
}

# Static IP address for the PSC endpoints
resource "google_compute_address" "endpoint" {
  name     = "${var.prefix}-endpoint-address-${each.key}"
  for_each = local.services
  region   = var.region

  subnetwork   = google_compute_subnetwork.client-subnet.id
  address_type = "INTERNAL"
}

# Client VM for testing
resource "google_compute_instance" "client" {
  name         = "${var.prefix}-client-vm"
  machine_type = "n1-standard-1"
  zone         = "${var.region}-${var.availability_zones[0]}"
  metadata     = {
    ssh-keys = <<KEYS
${var.ssh_user}:${file(abspath(var.public_key_path))}
KEYS
  }
  boot_disk {
    initialize_params {
      image = var.image
    }
  }
  network_interface {
    network    = google_compute_network.client-network.id
    subnetwork = google_compute_subnetwork.client-subnet.id
    access_config {}
  }
  metadata_startup_script = file("${path.module}/client.tftpl")
}

# Private DNS zone to override the broker location to be the PSC endpoints
resource "google_dns_managed_zone" "local-zone" {
  name     = "${local.byoc}-local-zone"
  dns_name = "${var.domain}."

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.client-network.id
    }
  }
}

# DNS entry for the seed broker (round robin over the three endpoints)
resource "google_dns_record_set" "seed" {
  name         = "${split(":", var.seed-broker)[0]}."
  managed_zone = google_dns_managed_zone.local-zone.name
  type         = "A"
  ttl          = 300

  rrdatas = local.kafka_endpoints
}

# DNS entries for the endpoints (kafka-0, registry-1, proxy-2, etc)
resource "google_dns_record_set" "endpoint" {
  name         = "${each.key}.${var.domain}."
  for_each     = local.services
  managed_zone = google_dns_managed_zone.local-zone.name
  type         = "A"
  ttl          = 300

  rrdatas = [google_compute_forwarding_rule.endpoint[each.key].ip_address]
}

# Access Connector to allow the cloudfunction to access private VPCs
resource "google_vpc_access_connector" "default" {
  name          = "${var.prefix}-vpc-access-connector"
  network       = google_compute_network.client-network.id
  ip_cidr_range = "192.168.50.0/28"
  region        = var.region
}

# Zip file to hold the cloudfunction Source Code
data "archive_file" "locator" {
  type        = "zip"
  output_path = "source.zip"
  source_dir  = "locator"
}

# Storage bucket to hold the cloudfunction zip file
resource "google_storage_bucket" "bucket" {
  name     = "${var.prefix}-bucket-${local.byoc}"
  location = var.location
}

# Directive to upload the cloudfunction zip file to the bucket
resource "google_storage_bucket_object" "archive" {
  name   = "source.zip"
  bucket = google_storage_bucket.bucket.name
  source = "./source.zip"
}

# Cloudfunction for DNS updates from the HAProxy scripts
resource "google_cloudfunctions_function" "function" {
  name                  = "update-dns-${local.byoc}"
  runtime               = "go120"
  vpc_connector         = google_vpc_access_connector.default.id
  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.archive.name
  trigger_http          = true
  entry_point           = "update" # The name of the .go file containing the function
  environment_variables = {
    PROJECT = var.project_name
    ZONE    = "${local.byoc}-local-zone"
  }
  lifecycle {
    replace_triggered_by = [google_storage_bucket_object.archive]
  }
}

# IAM entry to allow any user to invoke the cloudfunction (credentials passed as POST arguments)
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.function.project
  region         = google_cloudfunctions_function.function.region
  cloud_function = google_cloudfunctions_function.function.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}


####################################################################

# VPC to host the HAProxy infrastructure needed for PSC
resource "google_compute_network" "proxy-network" {
  name                    = "${var.prefix}-proxy-network"
  auto_create_subnetworks = false
}

# Proxy subnet indirectly required by forwarding rules
resource "google_compute_subnetwork" "proxy-network-subnet" {
  name          = "${var.prefix}-proxy-subnet"
  ip_cidr_range = var.proxy-cidr
  region        = var.region
  network       = google_compute_network.proxy-network.id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# Private subnet to host HAProxy VMs and related infra
resource "google_compute_subnetwork" "haproxy-network-subnet" {
  name          = "${var.prefix}-vm-subnet"
  ip_cidr_range = var.vm-cidr
  region        = var.region
  network       = google_compute_network.proxy-network.id
}

# Debug: Firewall rule to allow SSH access
#resource "google_compute_firewall" "ssh-to-proxy-network" {
#  name    = "${var.prefix}-ssh-firewall-rule"
#  network = google_compute_network.proxy-network.name
#  allow {
#    protocol = "all"
#  }
#  source_ranges = ["your.ip.here"]
#  direction     = "INGRESS"
#  priority      = 1
#  log_config {
#    metadata = "INCLUDE_ALL_METADATA"
#  }
#}

# Firewall rule to allow
resource "google_compute_firewall" "internal" {
  name    = "${var.prefix}-allow-internal"
  network = google_compute_network.proxy-network.name
  allow {
    protocol = "all"
  }
  source_ranges = [var.vm-cidr, var.proxy-cidr]
  direction     = "INGRESS"
  priority      = 1
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Peering to allow our new VM VPC to access the Redpanda VPC created by BYOC
resource "google_compute_network_peering" "peering1" {
  name         = "${var.prefix}-peering-inbound"
  network      = google_compute_network.proxy-network.self_link
  peer_network = var.rp-network
}

# Peering to allow our new VM VPC to access the Redpanda VPC created by BYOC
resource "google_compute_network_peering" "peering2" {
  name         = "${var.prefix}-peering-outbound"
  network      = var.rp-network
  peer_network = google_compute_network.proxy-network.self_link
}

# Router (needed for HAProxy VMs to access the internet to download packages)
resource "google_compute_router" "router" {
  name    = "${var.prefix}-router"
  project = var.project_name
  network = google_compute_network.proxy-network.id
  region  = var.region
}

# NAT (needed for HAProxy VMs to access the internet to download packages)
resource "google_compute_router_nat" "nat" {
  name                               = "${var.prefix}-router-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.haproxy-network-subnet.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# HAProxy VMs
resource "google_compute_instance" "haproxy" {
  name         = "${var.prefix}-vm-${count.index}"
  machine_type = "n1-standard-1"
  count        = var.haproxy-count
  zone         = "${var.region}-${var.availability_zones[count.index % length(var.availability_zones)]}"
  metadata     = {
    ssh-keys = <<KEYS
${var.ssh_user}:${file(abspath(var.public_key_path))}
KEYS
  }
  boot_disk {
    initialize_params {
      image = var.image
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.haproxy-network-subnet.name
    #access_config {} # Commented out to prevent public NAT ip being created
  }
  metadata_startup_script = templatefile("${path.module}/haproxy.tftpl", {
    seed-broker    = var.seed-broker,
    seed-user      = var.seed-user,
    seed-password  = var.seed-password,
    prefix         = "kafka",
    credentials    = google_service_account_key.mykey.private_key
    update-url     = google_cloudfunctions_function.function.https_trigger_url
    ports          = join(" ", [for name, port in var.ports : port]),
    port-increment = var.port-increment
  })

}

# HAProxy VM Instance Group (needed for internal load balancer to target the VMs)
resource "google_compute_instance_group" "default" {
  name      = "${var.prefix}-instance-group-${var.region}-${var.availability_zones[count.index]}"
  count     = length(var.availability_zones)
  zone      = "${var.region}-${var.availability_zones[count.index]}"
  instances = tolist([
    for i in google_compute_instance.haproxy.* : i.self_link
    if i.zone == "${var.region}-${var.availability_zones[count.index]}"
  ])
  network = google_compute_network.proxy-network.id
  dynamic "named_port" {
    for_each = local.incremented_ports
    content {
      name = named_port.key
      port = named_port.value
    }
  }
}

# Health check definition for our HAProxy targets
resource "google_compute_region_health_check" "kafka" {
  name = "${var.prefix}-backend-health-check-kafka"
  tcp_health_check {
    port = "30092"
  }
  region = var.region
}

# Firewall rules to allow health checks against our internal load balancer
resource "google_compute_firewall" "health-check" {
  name    = "${var.prefix}-health-check-firewall-rule"
  network = google_compute_network.proxy-network.name
  allow {
    protocol = "all"
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "35.235.240.0/20"] # These are the Google Health Check sources
  direction     = "INGRESS"
  priority      = 1
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Internal proxy load balancer (backend) for the PSC service attachment to point to
resource "google_compute_region_backend_service" "backend" {
  name                  = "${var.prefix}-backend-service-${each.key}"
  for_each              = local.incremented_ports
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  dynamic "backend" {
    for_each = google_compute_instance_group.default
    content {
      group           = backend.value.self_link
      balancing_mode  = "CONNECTION"
      max_connections = 100
      capacity_scaler = 1
    }
  }
  port_name     = each.key
  health_checks = [google_compute_region_health_check.kafka.id]
}

# Internal proxy load balancer (TCP proxy) for the PSC service attachment to point to
resource "google_compute_region_target_tcp_proxy" "default" {
  name            = "${var.prefix}-tcp-proxy-${each.key}"
  for_each        = local.incremented_ports
  backend_service = google_compute_region_backend_service.backend[each.key].id
  #  proxy_header = "PROXY_V1"
}

# Internal proxy load balancer (forwarding rule) for the PSC service attachment to point to
resource "google_compute_forwarding_rule" "default" {
  name                  = "${var.prefix}-internal-forwarding-rule-${each.key}"
  for_each              = local.non_incremented_ports
  load_balancing_scheme = "INTERNAL_MANAGED"
  network               = google_compute_network.proxy-network.id
  subnetwork            = google_compute_subnetwork.haproxy-network-subnet.name
  target                = google_compute_region_target_tcp_proxy.default[each.key].id
  ip_protocol           = "TCP"
  port_range            = each.value
}

# Subnets for PSC (one per service attachment as they can't be shared)
resource "google_compute_subnetwork" "service-attachment-network-subnet" {
  name          = "${var.prefix}-service-attachment-subnet-${each.key}"
  for_each      = local.psc-subnets
  ip_cidr_range = each.value
  region        = var.region
  network       = google_compute_network.proxy-network.id
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

# PSC service attachments
resource "google_compute_service_attachment" "default" {
  name                  = "${var.prefix}-service-attachment-${each.key}"
  for_each              = local.incremented_ports
  connection_preference = "ACCEPT_AUTOMATIC"
  enable_proxy_protocol = false
  nat_subnets           = [google_compute_subnetwork.service-attachment-network-subnet[each.key].id]
  region                = var.region
  target_service        = google_compute_forwarding_rule.default[each.key].id
}

# Service account for DNS updates
resource "google_service_account" "service_account" {
  account_id   = "dns-update-account"
  display_name = "DNS Update Account"
}

# Credentials for DNS update service account
resource "google_service_account_key" "mykey" {
  service_account_id = google_service_account.service_account.id
}

resource "google_project_iam_member" "dns_admin_binding" {
  project = var.project_name
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}


####################################################################

# Client side PSC endpoints
resource "google_compute_forwarding_rule" "endpoint" {
  name                  = "psc-endpoint-${each.key}"
  for_each              = local.services
  region                = var.region
  target                = google_compute_service_attachment.default[each.key].id
  load_balancing_scheme = "" # need to override EXTERNAL default when target is a service attachment
  network               = google_compute_network.client-network.id
  ip_address            = google_compute_address.endpoint[each.key].id
}
