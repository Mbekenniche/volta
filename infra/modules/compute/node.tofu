data "openstack_images_image_ids_v2" "image_visible" {
  name = var.image_name
}

data "openstack_images_image_ids_v2" "image_hidden" {
  name   = var.image_name
  hidden = true
}
data "openstack_compute_flavor_v2" "node" {
  name = var.node_flavor
}

resource "openstack_networking_port_v2" "nodes" {
  for_each   = var.node_map
  name       = "${var.name_prefix}-server-${each.key}-port"
  network_id = var.network_id

  fixed_ip {
    subnet_id = var.subnet_id
  }
  security_group_ids = [var.security_group_cluster_id]
}

resource "openstack_compute_instance_v2" "nodes" {
  for_each = var.node_map

  name      = "${var.name_prefix}-server-${each.key}"
  image_id  = var.image_id
  flavor_id = data.openstack_compute_flavor_v2.node.id
  key_pair  = openstack_compute_keypair_v2.cluster.name
  user_data = file("${path.module}/script/cloud-init-server.yaml")
  network {
    port = openstack_networking_port_v2.nodes[each.key].id
  }
  availability_zone = each.value

  lifecycle {
    precondition {
      condition = contains(
        concat(
          data.openstack_images_image_ids_v2.image_visible.ids,
          data.openstack_images_image_ids_v2.image_hidden.ids
        ),
        var.image_id
      )
      error_message = "Server ${each.key}: image ${var.image_id} is not a build of \"${var.image_name}\", visible or hidden."
    }
  }

}
