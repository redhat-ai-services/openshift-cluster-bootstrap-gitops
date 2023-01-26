#!/bin/bash
set -e

# shellcheck source=/dev/null
source "$(dirname "$0")/functions.sh"

LANG=C
SLEEP_SECONDS=45
ARGO_NS="openshift-gitops"
GITOPS_OVERLAY=components/operators/openshift-gitops/operator/overlays/latest/

install_gitops(){
  echo ""
  echo "Installing GitOps Operator."

  kustomize build ${GITOPS_OVERLAY} | oc apply -f -

  echo "Pause ${SLEEP_SECONDS} seconds for the creation of the gitops-operator..."
  sleep ${SLEEP_SECONDS}

  echo "Waiting for operator to start"
  until oc get deployment gitops-operator-controller-manager -n openshift-operators
  do
    sleep 5
  done

  echo "Waiting for openshift-gitops namespace to be created"
  until oc get ns ${ARGO_NS}
  do
    sleep 5
  done

  echo "Waiting for deployments to start"
  until oc get deployment cluster -n ${ARGO_NS}
  do
    sleep 5
  done

  wait_for_openshift_gitops

  echo ""
  echo "OpenShift GitOps successfully installed."

}

bootstrap_cluster(){

  PS3="Please enter a number to select a bootstrap folder: "
  
  select bootstrap_dir in bootstrap/overlays/*/; 
  do
      test -n "$bootstrap_dir" && break;
      echo ">>> Invalid Selection";
  done

  echo "Selected: ${bootstrap_dir}"
  echo "Apply overlay to override default instance"
  kustomize build "${bootstrap_dir}" | oc apply -f -

  sleep 10
  wait_for_openshift_gitops

  sleep 10
  echo "Restart the application-controller to start the sync"
  # Restart is necessary to resolve a bug where apps don't start syncing after they are applied
  oc delete pods -l app.kubernetes.io/name=openshift-gitops-application-controller -n ${ARGO_NS}

  echo
  echo "GitOps has successfully deployed!  Check the status of the sync here:"

  route=$(oc get route openshift-gitops-server -o jsonpath='{.spec.host}' -n ${ARGO_NS})

  echo "https://${route}"
}

# functions
setup_bin
check_bin oc
#check_bin kustomize
check_bin kubeseal
check_oc_login

# bootstrap
check_sealed_secret
install_gitops
bootstrap_cluster