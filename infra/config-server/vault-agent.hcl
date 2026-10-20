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
      path = "/run/secrets/vault-token"
      mode = 0640
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
  static_secret_render_interval = "15s"
  exit_on_retry_failure         = false
}

template {
  source      = "/etc/vault.d/templates/git-creds.properties.ctmpl"
  destination = "/run/secrets/git-credentials.properties"
  perms       = 0640
}
