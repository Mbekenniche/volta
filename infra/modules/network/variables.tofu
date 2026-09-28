variable "external_network_name" {
  type        = string
  description = "Name of the external network for floating IPs."
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for the subnet."
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 1))
    error_message = "The subnet_cidr variable must be a valid CIDR block."
  }
}

variable "admin_cidr" {
  type        = string
  description = "Allowed CIDR block for admin access."

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "The admin_cidr variable must be a valid CIDR block."
  }
}

variable "name_prefix" {
  type        = string
  description = "The prefix name of the resources"
}
