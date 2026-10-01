output "network_id" {
  description = "ID of the internal private network hosting the cluster."
  value       = module.network.network_id
}

output "subnet_id" {
  description = "Subnet the cluster nodes attach to."
  value       = module.network.subnet_id
}

output "security_group_cluster_id" {
  description = "ID of the security group applied to the cluster nodes."
  value       = module.network.security_group_cluster_id
}

output "security_group_bastion_id" {
  description = "ID of the security group applied to the bastion."
  value       = module.network.security_group_bastion_id
}

output "keypair_name" {
  description = "Name of the SSH keypair injected into instances for administrative access."
  value       = module.compute.keypair_name
}

output "public_ip_bastion" {
  description = "Public address of the bastion, the only public address of the platform."
  value       = module.compute.public_ip_bastion
}

output "private_ip_node" {
  description = "Private address of each cluster node, keyed by instance name."
  value       = module.compute.private_ip_node

}
