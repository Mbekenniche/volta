output "keypair_name" {
  description = "Name of the SSH keypair injected into instances for administrative access."
  value       = openstack_compute_keypair_v2.cluster.name
}
