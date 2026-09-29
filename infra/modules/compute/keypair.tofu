resource "openstack_compute_keypair_v2" "cluster" {
  name       = "${var.name_prefix}-keypair"
  public_key = var.ssh_public_key
}
