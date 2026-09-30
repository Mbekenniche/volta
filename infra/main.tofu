module "network" {
  source                = "./modules/network"
  subnet_cidr           = var.subnet_cidr
  name_prefix           = local.name_prefix
  admin_cidr            = var.admin_cidr
  external_network_name = var.external_network_name

}

module "compute" {
  source                    = "./modules/compute"
  name_prefix               = local.name_prefix
  ssh_public_key            = file(var.ssh_public_key_path)
  network_id                = module.network.network_id
  subnet_id                 = module.network.subnet_id
  security_group_cluster_id = module.network.security_group_cluster_id
  node_flavor               = var.node_flavor
  image_id                  = var.image_id
  image_name                = var.image_name
  node_map                  = var.node_map
}
