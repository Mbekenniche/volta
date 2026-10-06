output "public_address" {
  description = "Public address of the ingress, the floating IP reserved in the bootstrap stack."
  value       = data.openstack_networking_floatingip_v2.ingress.address
}
