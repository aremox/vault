# Permiso para leer credenciales dinamicas de PostgreSQL (usuarios efimeros por lease)
path "database/creds/postgres-dynamic-role" {
  capabilities = ["read"]
}

# Permiso para leer credenciales estaticas rotadas de PostgreSQL (app_static_user)
path "database/static-creds/postgres-static-role" {
  capabilities = ["read"]
}

# Permiso para renovar el propio token y consultar leases
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}
