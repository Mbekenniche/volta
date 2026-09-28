module "network" {
  source                = "./modules/network"
  subnet_cidr           = var.subnet_cidr
  name_prefix           = local.name_prefix
  admin_cidr            = var.admin_cidr
  external_network_name = var.external_network_name

}
