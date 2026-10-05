terraform {
  required_version = ">= 1.12.5"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.0"
    }
  }
}

provider "openstack" {
  region = "dc3-a"
}

resource "openstack_objectstorage_container_v1" "tfstate" {
  name       = "volta-lab-tfstate"
  versioning = true
  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_networking_floatingip_v2" "ingress" {
  pool        = "ext-floating1"
  tags        = ["volta-ingress"]
  description = "Public address of the ingress load balancer, kept here to survive a destroy of the main stack."
  lifecycle {
    prevent_destroy = true
  }
}

output "container_name" {
  description = "Name of the container that holds the OpenTofu state."
  value       = openstack_objectstorage_container_v1.tfstate.name
}

output "ingress_address" {
  description = "Public address of the ingress, target of the *.volta.koveolabs.com DNS record."
  value       = openstack_networking_floatingip_v2.ingress.address
}
