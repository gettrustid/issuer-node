#!/bin/bash

# RESOLVER_FILE="resolvers_settings_sample.yaml"
RESOLVER_FILE="resolvers_settings.yaml"

if [[ ! -f "$RESOLVER_FILE" ]]; then
  echo "File not found: $RESOLVER_FILE"
  exit 1
fi

ENCODED=$(base64 -i "$RESOLVER_FILE" | tr -d '\n')
export ISSUER_RESOLVER_FILE="$ENCODED"

echo "ISSUER_RESOLVER_FILE has been exported:"
echo "$ISSUER_RESOLVER_FILE"
