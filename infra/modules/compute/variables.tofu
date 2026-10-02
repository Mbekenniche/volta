variable "name_prefix" {
  type        = string
  description = "The prefix name of the resources"
}

variable "ssh_public_key" {
  type        = string
  description = "Content of the SSH public key file."
}

variable "network_id" {
  type        = string
  description = "ID of the private network the nodes attach to."
}

variable "subnet_id" {
  type        = string
  description = "ID of the subnet the node ports take their address from."
}

variable "security_group_cluster_id" {
  type        = string
  description = "ID of the cluster security group, the only group on each node port."
}

variable "security_group_bastion_id" {
  type        = string
  description = "ID of the bastion security group, the only group on the bastion port."
}

variable "image_id" {
  type        = string
  description = "ID of the node image, pinned because Glance rebuilds images under the same name."
}

variable "image_name" {
  type        = string
  description = "Exact name of the image the pinned ID must be a build of, visible or hidden."
}

variable "node_flavor" {
  type        = string
  description = "Name of the flavor for the cluster nodes."
}

variable "bastion_flavor" {
  type        = string
  description = "Name of the flavor for the bastion."
}

variable "node_map" {
  type        = map(string)
  description = "Cluster nodes, keyed by a stable index, each mapped to its availability zone."
}
variable "external_network_name" {
  type        = string
  description = "Name of the external network for floating IPs."
}

variable "k3s_version" {
  type        = string
  description = "k3s release installed on every server."
}

variable "k3s_install_script_sha256" {
  type        = string
  description = "SHA-256 the k3s install script must match before it runs."
}

variable "init_node" {
  type        = string
  description = "Key of node_map whose server initialises the cluster."
}

variable "pod_cidr" {
  type        = string
  description = "Pod network, shared by the k3s configuration and the metadata rule."
}
