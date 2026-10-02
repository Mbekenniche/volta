variable "environment" {
  type        = string
  default     = "lab"
  description = "Deployment environment."
}

variable "region" {
  type        = string
  default     = "dc3-a"
  description = "Target cloud region."
}

variable "external_network_name" {
  type        = string
  default     = "ext-floating1"
  description = "Name of the external network for floating IPs."
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for the subnet."
  default     = "10.10.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 1))
    error_message = "The subnet_cidr variable must be a valid CIDR block."
  }
}


variable "ssh_public_key_path" {
  type        = string
  description = "Path to the SSH public key file."
}

variable "admin_cidr" {
  type        = string
  description = "Allowed CIDR block for admin access."

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "The admin_cidr variable must be a valid CIDR block."
  }
}

variable "encryption_passphrase" {
  type        = string
  description = "The secret passphrase used for data encryption (minimum 16 characters)."
  sensitive   = true
  validation {
    condition     = length(var.encryption_passphrase) >= 16
    error_message = "The passphrase must be at least 16 characters long."
  }
}

# Ubuntu 24.04 LTS Noble Numbat, built 2026-09-28. Glance rebuilds its images under the same
# name and hides the previous build: moving to a newer one is a deliberate change here.
variable "image_id" {
  type        = string
  default     = "abe3bf73-f45c-42bb-a63c-4f5cf00a62a7"
  description = "ID of the node image. Pinned rather than looked up by name, which would replace every node at each rebuild."
}

variable "image_name" {
  type        = string
  default     = "Ubuntu 24.04 LTS Noble Numbat"
  description = "Exact name of the image the pinned ID must be a build of, visible or hidden."
}

variable "node_flavor" {
  type        = string
  default     = "a2-ram4-disk20-perf1"
  description = "Flavor of the cluster nodes, by name."
}

variable "bastion_flavor" {
  type        = string
  default     = "a1-ram2-disk20-perf1"
  description = "Flavor of the bastion, by name."
}

variable "node_map" {
  type = map(string)
  default = {
    "1" = "dc3-a-04"
    "2" = "dc3-a-09"
    "3" = "dc3-a-10"
  }
  description = "One cluster node per entry, keyed by a stable index and placed in its own availability zone. Zones are listed literally: a lookup would move nodes when a zone is added."
}

variable "k3s_version" {
  type        = string
  default     = "v1.36.4+k3s1"
  description = "k3s release installed on every server, from the stable channel. It is written into the cloud-init, so a change replaces the servers."
}

variable "k3s_install_script_sha256" {
  type        = string
  default     = "46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad"
  description = "SHA-256 of install.sh at the k3s_version tag. A server runs the script only if it matches: change both together."
}

variable "init_node" {
  type        = string
  default     = "1"
  description = "Key of node_map whose server initialises the cluster. The other servers join it."

  validation {
    condition     = contains(keys(var.node_map), var.init_node)
    error_message = "init_node must be one of the keys of node_map."
  }
}

variable "pod_cidr" {
  type        = string
  default     = "10.42.0.0/16"
  description = "Pod network. Written into the k3s configuration and into the rule that keeps pods away from the metadata service, so the two cannot drift apart."
}

locals {
  name_prefix = "volta-${var.environment}"
}
