terraform {
  required_version = ">= 1.12.5"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.0"
    }
  }
  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.encryption_passphrase
    }

    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.passphrase
    }


    state {
      method   = method.aes_gcm.default
      enforced = true


    }

    plan {
      method   = method.aes_gcm.default
      enforced = true

    }


  }
}

provider "openstack" {
  region = var.region
}
