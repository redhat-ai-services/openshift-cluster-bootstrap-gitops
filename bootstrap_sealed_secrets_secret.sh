#!/bin/bash
set -e

echo "Validating cluster login"
oc whoami

SEALED_SECRETS_FOLDER=./components/operators/sealed-secrets-operator/overlays/default/
SEALED_SECRETS_SECRET=./bootstrap/base/sealed-secrets-secret.yaml

echo
echo "Only execute this script if you do not already have a sealed secrets key and you do not plan to re-use existing sealed secrets encrypted with another key."

read -r -p "Are you sure you would like to continue? [y/N] " input
case $input in
      [yY][eE][sS]|[yY])
            oc apply -k ${SEALED_SECRETS_FOLDER}
            oc get secret -l sealedsecrets.bitnami.com/sealed-secrets-key=active -n sealed-secrets -o yaml >  ${SEALED_SECRETS_SECRET}
            ;;
      [nN][oO]|[nN])
            echo
            ;;
      *)
            echo "Invalid input..."
            exit 1
            ;;
esac
