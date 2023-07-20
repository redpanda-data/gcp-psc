### GCP Config

# A prefix for use in naming resources we create in GCP
variable "prefix" {
  default = "psc"
}

# Your GCP project name
variable "project_name" {
  default = "your-project-123456"
}

# The GCP region in which resources will be created
variable "region" {
  default = "europe-west1"
}

# The GCP storage bucket location
variable "location" {
  default = "EU"
}

# Availability Zones in which to create the HAProxy VMs
variable "availability_zones" {
  default     = ["b", "c", "d"]
  type        = list(string)
}

# A subnet for use by client (test) VMs
variable "client_cidr" {
  default = "192.168.30.0/24"
}

### Redpanda Config

# The DNS domain of the Redpanda BYOC cluster
variable "domain" {
  default = "abcdefghijklmn1o2pq34.byoc.prd.cloud.redpanda.com"
}

# The GCP URL for the network used by Redpanda (needed for peering)
variable "rp-network" {
  default = "projects/your-project-123456/global/networks/redpanda-cihueaerbdersm5f2h6g"
}

# The name of the subnet used by Redpanda
variable "rp-subnet" {
  default = "redpanda-abcdefghidersm5f2h6g-abcdefghijklmn1o2pq34"
}

# The seed broker as shown in the Redpanda Console
variable "seed-broker" {
  default = "seed-63f403ec.abcdefghijklmn1o2pq34.byoc.prd.cloud.redpanda.com:9092"
}

# A Redpanda user that we can use to retrieve broker information
variable "seed-user" {
  default = "foo"
}

# The password for the user defined above
variable "seed-password" {
  default = "foo123"
}

### Proxy Config

# These are the ports on the Redpanda brokers for which endpoints should be created
variable "ports" {
  type = map(number)
  default = {
    "kafka" = 30092
    "proxy" = 30081
    "registry" = 30082
  }
}

# This increment is used to allow multiple brokers to be contactable through a single HAProxy instance
# With an increment of 1000, broker 0 will be on 30092, broker 1 on 31092, etc
# Used in conjunction with the ports defined above
variable "port-increment" {
  default = 1000
}

# The number of brokers in the BYOC cluster
variable "brokers" {
  default = 3
}

### HAProxy VM Config

# The number of HAProxy VMs to create. For resiliency, a minimum of 2 is recommended
# The default is the same number of VMs are there are brokers
variable "haproxy-count" {
  default = 3
}

# A subnet for use by GCP proxies (and only proxies - nothing else is allowed)
variable "proxy-cidr" {
  default = "192.168.9.0/24"
}

# A subnet for use by the HAProxy VMs
variable "vm-cidr" {
  default = "192.168.10.0/24"
}

# The OS image to use when building HAProxy VMs
variable "image" {
  default = "ubuntu-os-cloud/ubuntu-2204-lts"
}

# The SSH public key to deploy into the HAProxy (and client) VMs for access
variable "public_key_path" {
  default = "/Users/pmw/.ssh/id_rsa.pub"
}

# The SSH user for use in creating SSH keys files on the VMs
variable "ssh_user" {
  default = "pmw"
}

### PSC

# A subnet prefix for use in dynamically creating multiple subnets
# (PSC requires a unique subnet per PSC endpoint, /29 or larger)
variable "psc-subnet-cidr-prefix" {
  default = "192.168.50."
}
