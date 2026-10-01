data "openstack_compute_flavor_v2" "bastion" {
  name = var.bastion_flavor
}

resource "openstack_networking_port_v2" "bastion" {
  name       = "${var.name_prefix}-bastion-port"
  network_id = var.network_id

  fixed_ip {
    subnet_id = var.subnet_id
  }
  security_group_ids = [var.security_group_bastion_id]
}

resource "openstack_compute_instance_v2" "bastion" {

  name      = "${var.name_prefix}-bastion"
  image_id  = var.image_id
  flavor_id = data.openstack_compute_flavor_v2.bastion.id
  key_pair  = openstack_compute_keypair_v2.cluster.name
  user_data = file("${path.module}/script/cloud-init-bastion.yaml")
  network {
    port = openstack_networking_port_v2.bastion.id
  }

  lifecycle {
    precondition {
      condition = contains(
        concat(
          data.openstack_images_image_ids_v2.image_visible.ids,
          data.openstack_images_image_ids_v2.image_hidden.ids
        ),
        var.image_id
      )
      error_message = "Bastion: image ${var.image_id} is not a build of \"${var.image_name}\", visible or hidden."
    }
  }

}

resource "openstack_networking_floatingip_v2" "bastion" {
  pool        = var.external_network_name
  description = "Public entry point of the platform, on the bastion."
}

resource "openstack_networking_floatingip_associate_v2" "bastion" {
  floating_ip = openstack_networking_floatingip_v2.bastion.address
  port_id     = openstack_networking_port_v2.bastion.id
}
