# Runbook: Rotate TLS Certificates

**When to use**: mkcert cert expired, browser shows certificate error, or annually as a practice.
**Time**: ~10 minutes
**Risk**: Low (brief TLS disruption during rotation)

## Check Certificate Status

```bash
# Check all certificates in the cluster
kubectl get certificates -A

# Check specific cert
kubectl describe certificate local-dev-wildcard -n cert-manager

# Check expiry of the local mkcert cert
openssl x509 -in _wildcard.local.dev+1.pem -noout -dates
```

## Rotate mkcert Certificate

### Step 1: Regenerate certificate

```bash
# Generate new wildcard cert (mkcert automatically uses the installed CA)
mkcert "*.local.dev" local.dev

# This creates:
# _wildcard.local.dev+1.pem      (certificate)
# _wildcard.local.dev+1-key.pem  (private key)
```

### Step 2: Update the Kubernetes Secret

```bash
kubectl create secret tls local-dev-wildcard-tls \
  --cert=_wildcard.local.dev+1.pem \
  --key=_wildcard.local.dev+1-key.pem \
  --namespace=cert-manager \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 3: Restart ingress-nginx to pick up new cert

```bash
kubectl rollout restart daemonset/ingress-nginx-controller -n ingress-nginx
kubectl rollout status daemonset/ingress-nginx-controller -n ingress-nginx
```

### Step 4: Verify

```bash
# Check cert in browser or with openssl
echo | openssl s_client -connect argocd.local.dev:443 2>/dev/null \
  | openssl x509 -noout -dates

# Verify all services work
curl -sk https://argocd.local.dev | grep -c "Argo"
curl -sk https://harbor.local.dev/api/v2.0/health
```

## Rotate mkcert CA (Nuclear Option)

Only needed if the mkcert CA itself is compromised or expired.

```bash
# Uninstall current CA
mkcert -uninstall

# Remove old CA files
rm -rf "$(mkcert -CAROOT)"

# Install new CA
mkcert -install

# Regenerate all certs
mkcert "*.local.dev" local.dev

# Update Kubernetes secret (same as Step 2-4 above)
```

**After CA rotation**: browsers will need to trust the new CA. Run `mkcert -install` again, which updates the system trust store. You may need to restart browsers.

## If cert-manager is Managing Certs

For certs issued by cert-manager (not our manual wildcard), force renewal:

```bash
# List cert-manager certificates
kubectl get certificates -A

# Delete the cert object (cert-manager recreates it)
kubectl delete certificate <cert-name> -n <namespace>

# Watch it recreate
kubectl get certificate <cert-name> -n <namespace> -w
```

Or use cert-manager's renewal annotation:
```bash
kubectl annotate certificate <cert-name> -n <namespace> \
  cert-manager.io/renew-now="true"
```

## Troubleshooting

### Browser still shows old certificate

Browsers cache TLS sessions. Try:
- Clear browser cache (Ctrl+Shift+Delete)
- Open incognito window
- Wait 5-10 minutes for session cache to expire

### Certificate valid but browser shows warning

The mkcert CA might not be trusted:
```bash
mkcert -install
# Restart browser after this
```

### `tls: certificate is not valid for any names` error

The cert SAN doesn't match the hostname. Regenerate:
```bash
mkcert "*.local.dev" local.dev
# Note: "*.local.dev" covers sub.local.dev but NOT local.dev itself
# Including "local.dev" explicitly covers the root domain
```
