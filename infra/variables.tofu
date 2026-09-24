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

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for the subnet."
  default     = "10.10.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 1))
    error_message = "The subnet_cidr variable must be a valid CIDR block."
  }
}

variable "external_network_name" {
  type        = string
  default     = "ext-floating1"
  description = "Name of the external network for floating IPs."
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

locals {
  name_prefix = "volta-${var.environment}"
}
