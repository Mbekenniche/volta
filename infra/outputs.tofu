output "network_id" {
  description = "ID of the internal private network hosting the cluster."
  value       = module.network.network_id
}

output "subnet_id" {
  description = "Subnet the cluster nodes attach to."
  value       = module.network.subnet_id
}

output "security_group_id" {
  description = "ID of the security group applied to the cluster nodes."
  value       = module.network.security_group_id
}

output "keypair_name" {
  description = "Name of the SSH keypair injected into instances for administrative access."
  value       = openstack_compute_keypair_v2.cluster.name
}
