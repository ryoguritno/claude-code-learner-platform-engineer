# Template policy for application access to Vault
# The seed processor replaces APP_NAME with the actual application name
# and creates a policy named after the application.

# Read application secrets
path "secret/data/APP_NAME/*" {
  capabilities = ["read"]
}

# List secret metadata
path "secret/metadata/APP_NAME/*" {
  capabilities = ["list", "read"]
}

# Read its own dynamic database credentials (if configured)
path "database/creds/APP_NAME-role" {
  capabilities = ["read"]
}
