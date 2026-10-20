# Permiso para leer credenciales dinamicas de PostgreSQL (usuarios efimeros por lease)
path "database/creds/postgres-dynamic-role" {
  capabilities = ["read"]
}

# Permiso para leer credenciales estaticas rotadas de PostgreSQL (app_static_user)
path "database/static-creds/postgres-static-role" {
  capabilities = ["read"]
}

# Permiso para leer credenciales de Gitea en Vault KV v2 (usado por vm-config-server y vm-app)
path "secret/data/git-credentials" {
  capabilities = ["read"]
}

# Permiso para leer y actualizar secretos de aplicacion en Vault KV v2 (Spring Cloud Config)
path "secret/data/vault-rotation-pilot" {
  capabilities = ["read", "create", "update"]
}

path "secret/data/vault-rotation-pilot/*" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/*" {
  capabilities = ["list", "read"]
}

# Permiso para renovar el propio token y consultar leases
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}
