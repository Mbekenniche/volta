# Alphanumeric only: the token is written into the servers' k3s configuration as a YAML string.
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}
