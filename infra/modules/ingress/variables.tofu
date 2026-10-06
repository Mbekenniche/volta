variable "subnet_id" {
  type        = string
  description = "ID of the cluster subnet, where the load balancer takes its address and reaches the nodes."
}

variable "name_prefix" {
  type        = string
  description = "The prefix name of the resources"
}

variable "private_ip_node" {
  type        = map(string)
  description = "Private address of each cluster node, keyed by instance name: the members of both pools."
}
