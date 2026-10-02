terraform {
  required_version = ">= 1.12.5"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  backend "s3" {
    bucket = "volta-lab-tfstate"
    key    = "infra.tfstate"
    region = "us-east-1"
    endpoints = {
      s3 = "https://s3.pub1.infomaniak.cloud"
    }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_path_style              = true
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
