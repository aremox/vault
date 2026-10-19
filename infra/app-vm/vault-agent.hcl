pid_file = "/var/run/vault-agent.pid"

vault {
  address = "http://172.29.0.10:8200"
  retry {
    num_retries = 10
  }
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path                   = "/etc/vault.d/role_id"
      secret_id_file_path                 = "/etc/vault.d/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/var/run/vault-token"
      mode = 0600
    }
  }
}

template_config {
  static_secret_render_interval = "10s"
  exit_on_retry_failure         = false
}

template {
  source      = "/etc/vault.d/templates/db-dynamic.properties.ctmpl"
  destination = "/run/secrets/db-dynamic.properties"
  perms       = 0640
}

template {
  source      = "/etc/vault.d/templates/db-static.properties.ctmpl"
  destination = "/run/secrets/db-static.properties"
  perms       = 0640
}
