# Vault Key Setup for Issuer Node (Dev)

## Prerequisites

- `kubectl` access to the cluster
- Namespace: `trustid-issuer-dev`
- Vault pod: `vault-issuer-node-0`
- An Ethereum private key (hex, without `0x` prefix)

## Steps

### 1. Get the Vault Root Token

```bash
kubectl exec vault-issuer-node-0 -n trustid-issuer-dev -- \
    cat /vault/plugins/init.out
```

Copy the `Initial Root Token` value.

### 2. Login to Vault with Root Token

```bash
kubectl exec vault-issuer-node-0 -n trustid-issuer-dev -- \
    sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault login <ROOT_TOKEN>'
```

> **Important:** Always set `VAULT_ADDR=http://127.0.0.1:8200`. Without it, the CLI defaults to HTTPS which the dev Vault doesn't serve.

### 3. Verify the iden3 Plugin is Mounted

```bash
kubectl exec vault-issuer-node-0 -n trustid-issuer-dev -- \
    sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault secrets list'
```

You should see `iden3/` in the list. If not, enable it:

```bash
kubectl exec vault-issuer-node-0 -n trustid-issuer-dev -- \
    sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault secrets enable -path=iden3 vault-plugin-secrets-iden3'
```

> If you get `path is already in use at iden3/`, the plugin is already mounted — this is fine.

### 4. Import the Ethereum Private Key (pbkey)

```bash
kubectl exec vault-issuer-node-0 -n trustid-issuer-dev -- \
    sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault write iden3/import/pbkey key_type=ethereum private_key=<YOUR_PRIVATE_KEY_WITHOUT_0x>'
```

> **Note:** Use `iden3/import/pbkey`, NOT `vault kv put`. The iden3 plugin has its own API — it is not a KV engine.

### 5. Verify the Key is Readable

```bash
kubectl exec vault-issuer-node-0 -n trustid-issuer-dev -- \
    sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault read -field=key_type iden3/keys/pbkey'
```

Expected output: `ethereum`

## Troubleshooting

### "key already exists" on import but "key not found" on read

The key storage is corrupted. Delete and re-import:

```bash
kubectl exec vault-issuer-node-0 -n trustid-issuer-dev -- \
    sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault delete iden3/keys/pbkey'

kubectl exec vault-issuer-node-0 -n trustid-issuer-dev -- \
    sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault write iden3/import/pbkey key_type=ethereum private_key=<YOUR_KEY>'
```

### "permission denied" (403)

You're not using the root token. Re-login:

```bash
kubectl exec vault-issuer-node-0 -n trustid-issuer-dev -- \
    sh -c 'export VAULT_ADDR=http://127.0.0.1:8200 && vault login <ROOT_TOKEN>'
```

### "connection refused" on HTTPS

You forgot `VAULT_ADDR`. The dev Vault uses HTTP, not HTTPS:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
```

### "unsupported path" with `vault kv put`

The iden3 mount is a custom plugin, not a KV engine. Use `vault write iden3/import/...` instead of `vault kv put iden3/...`.
