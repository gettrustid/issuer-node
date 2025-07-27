# Overview

This is a helm chart for deploying Privado ID issuer node on Kubernetes.
To learn more about Privado ID issuer, see [this](https://0xpolygonid.github.io/tutorials/issuer/issuer-overview).

## Installation

### Prerequisites

#### Set up command-line tools

Make sure you have these tools installed.

- [kubectl](https://kubernetes.io/docs/reference/kubectl/overview/)
- [helm](https://helm.sh/)

### Setup Ingress

The first step is update and modify the ingress chart (`charts/ingress`) according to your requirements. The issuer node works over HTTPS, so you need to provide a valid certificate. Certificate Installation sample [here](charts/ingress/certs/README.md)

### Setup volumes

How the volumes are set up depends on the cloud provider you are using, so you need to set up the volumes according to your cloud provider. Please, take a look at the [volumes](https://kubernetes.io/docs/concepts/storage/volumes/) documentation. You have to set up the volumes in the [vault pvc](charts/vault/templates/pvc.yaml) and [postgres pvc](charts/postgres/templates/pvc.yaml) file.

### Configure the app

To set up the app, you need to configure the following environment variables.
The ISSUER_RESOLVER_FILE is a base64 encoded string of the resolver file. You can take a look at the resolver file [here](../../resolvers_settings_sample.yaml)

```shell
export APP_INSTANCE_NAME=trustid-issuernode           # Sample name for the application
export NAMESPACE=identity                             # Namespace where you want to deploy the application
export UI_DOMAIN=ui.example.com                         # Domain for the UI.
export API_DOMAIN=api.example.com                       # Domain for the API.
export PRIVATE_KEY='YOUR PRIVATE KEY'                   # Private key of the wallet (Ethereum private key wallet).
export UIPASSWORD="my ui password"                      # Password for user: ui-user. This password is used when the user visit the ui.
export UI_INSECURE=true                                 # Set as true if the ui doesn't require basic auth. If this value true UIPASSWORD can be blank
export ISSUERNAME="My Issuer"                           # Issuer Name. This value is shown in the UI
export VAULT_PWD=password                               # Vault password to anable issuer node to connect with vault. Put the password you want to use.
export ISSUER_RESOLVER_FILE="cG9XYZ0K+"                 # Base64 encoded string of the resolver file. You can take a look at the resolver file [here](../../resolvers_settings_sample.yaml)
```

## Encode Resolver File

* Run encode_resolver.sh, can test default included sample matches Base64 encoding above
* Set base64 value as value for ISSUER_RESOLVER_FILE

## Pre-Populate Vault
* Use set_vault_secrets.sh , modify script as needed. This will populate the keyvault with secrets necessary for issuer


## Install the helm chart

```bash
helm install "$APP_INSTANCE_NAME" . \
--create-namespace --namespace "$NAMESPACE" \
--set namespace="$NAMESPACE" \
--set global.uidomain="$UI_DOMAIN" \
--set global.apidomain="$API_DOMAIN" \
--set privatekey="$PRIVATE_KEY" \
--set uiPassword="$UIPASSWORD" \
--set issuerName="$ISSUERNAME" \
--set global.vaultpwd="$VAULT_PWD" \
--set issuerUiInsecure=$UI_INSECURE \
--set issuerResolverFile="$ISSUER_RESOLVER_FILE"
```

#### Install TrustId Issuer

```bash
helm install trustid-issuer . \
  --namespace trustid-issuer \
  -f values.yaml \
  -f values.secrets.yaml
```
#### Upgrade
```bash
helm upgrade trustid-issuer . \
  --namespace trustid-issuer \
  -f values.yaml
```
```bash
helm uninstall trustid-issuer --namespace trustid-issuer
```
## Ingress 
* /ingress is default with cloudflare
* switching temporarily to /ingress-nginx for testing 
* run ingress-deploy.sh to deploy it to cluster