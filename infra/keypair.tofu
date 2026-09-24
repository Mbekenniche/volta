resource "openstack_compute_keypair_v2" "cluster" {
  name       = "${local.name_prefix}-keypair"
  public_key = file(var.ssh_public_key_path)
}
