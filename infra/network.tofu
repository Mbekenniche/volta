data "openstack_networking_network_v2" "external" {
  name     = var.external_network_name
  external = true
}

resource "openstack_networking_network_v2" "cluster" {
  name = "${local.name_prefix}-network"
}
resource "openstack_networking_subnet_v2" "cluster" {
  name        = "${local.name_prefix}-subnet"
  network_id  = openstack_networking_network_v2.cluster.id
  cidr        = var.subnet_cidr
  ip_version  = 4
  enable_dhcp = true

}
resource "openstack_networking_router_v2" "cluster" {
  name                = "${local.name_prefix}-router"
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "cluster" {
  router_id = openstack_networking_router_v2.cluster.id
  subnet_id = openstack_networking_subnet_v2.cluster.id
}
