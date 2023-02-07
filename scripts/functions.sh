#!/bin/bash
set -e

OCP_VERSION=4.11
TMP_DIR=tmp
SEALED_SECRETS_FOLDER=components/operators/sealed-secrets-operator/overlays/default/
SEALED_SECRETS_SECRET=bootstrap/base/sealed-secrets-secret.yaml

setup_bin(){
  mkdir -p ${TMP_DIR}/bin
  echo "${PATH}" | grep -q "${TMP_DIR}/bin" || \
    PATH=$(pwd)/${TMP_DIR}/bin:${PATH}
    export PATH
}

check_bin(){
  name=$1
  
  which "${name}" || download_"${name}"
 
  case ${name} in
    oc|openshift-install|kustomize)
      echo "auto-complete: . <(${name} completion bash)"
      
      # shellcheck source=/dev/null
      . <(${name} completion bash)
      
      ${name} version
      ;;
    *)
      echo
      ${name} --version
      ;;
  esac
  sleep 5
}

download_kubeseal(){
  # Kubeseal releases can be found at:
  # https://github.com/bitnami-labs/sealed-secrets/releases/

  if [[ "$OSTYPE" == "darwin"* ]]; then
    # Mac OSX  
    if [[ $(uname -p) == 'arm' ]]; then
      DOWNLOAD_URL=https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.19.4/kubeseal-0.19.4-darwin-arm64.tar.gz
    else
      DOWNLOAD_URL=https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.19.4/kubeseal-0.19.4-darwin-amd64.tar.gz
    fi
  else
    # Linix
    if [[ $(uname -p) == 'arm' ]]; then
      DOWNLOAD_URL=https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.19.4/kubeseal-0.19.4-linux-arm.tar.gz
    else
      DOWNLOAD_URL=https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.19.4/kubeseal-0.19.4-linux-amd64.tar.gz
    fi  
  fi
  echo "Downloading Kubeseal: ${DOWNLOAD_URL}"

  curl "${DOWNLOAD_URL}" -L | tar vzx -C ${TMP_DIR}/bin kubeseal
}


download_ocp-install(){
  DOWNLOAD_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_VERSION}/openshift-install-linux.tar.gz
  curl "${DOWNLOAD_URL}" -L | tar vzx -C ${TMP_DIR}/bin openshift-install
}

download_oc(){
  DOWNLOAD_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_VERSION}/openshift-client-linux.tar.gz
  curl "${DOWNLOAD_URL}" -L | tar vzx -C ${TMP_DIR}/bin oc
}

download_kustomize(){
  cd ${TMP_DIR}/bin
  curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
  cd ../..
}


# check login
check_oc_login(){
  oc cluster-info | head -n1
  oc whoami || exit 1
  echo
  sleep 3
}

create_sealed_secret(){
  read -r -p "Create NEW [${SEALED_SECRETS_SECRET}]? [y/N] " input
  case $input in
    [yY][eE][sS]|[yY])

      oc apply -k ${SEALED_SECRETS_FOLDER}
      [ -e ${SEALED_SECRETS_SECRET} ] && return

      # TODO: explore using openssl
      # oc -n sealed-secrets -o yaml \
      #   create secret generic

      # just wait for it
      sleep 20

      oc -n sealed-secrets -o yaml \
        get secret \
        -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
        > ${SEALED_SECRETS_SECRET}

      ;;
    [nN][oO]|[nN])
      echo
      ;;
    *)
      echo
      ;;
  esac
}

# Validate sealed secrets secret exists
check_sealed_secret(){
  if [ -f ${SEALED_SECRETS_SECRET} ]; then
    echo "Exists: ${SEALED_SECRETS_SECRET}"
  else
    echo "Missing: ${SEALED_SECRETS_SECRET}"
    echo "The master key is required to bootstrap sealed secrets and CANNOT be checked into git."
    echo
    create_sealed_secret
  fi
}

wait_for_openshift_gitops(){
  echo "Checking status of all openshift-gitops pods"
  GITOPS_RESOURCES=(
    deployment/cluster \
    deployment/kam \
    statefulset/openshift-gitops-application-controller \
    deployment/openshift-gitops-applicationset-controller \
    deployment/openshift-gitops-redis \
    deployment/openshift-gitops-repo-server \
    deployment/openshift-gitops-server \
  )

  for i in "${GITOPS_RESOURCES[@]}"
  do
    echo "Waiting for ${i}"
    oc rollout status ${i} -n ${ARGO_NS}
  done
}