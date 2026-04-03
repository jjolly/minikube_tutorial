#!/usr/bin/env bash
set -euo pipefail

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"
ASSUME_YES="${ASSUME_YES:-false}"

printf 'Updating kubectl context for profile: %s\n' "$MINIKUBE_PROFILE"
minikube -p "$MINIKUBE_PROFILE" update-context >/dev/null

CURRENT_CONTEXT="$(kubectl config current-context)"
printf '\nWARNING: this script is destructive.\n'
printf 'It will delete the tutorial namespace and remove non-system user workloads from the default namespace.\n'
printf 'Review the target cluster information carefully before continuing.\n\n'

printf 'Target kubectl context: %s\n' "$CURRENT_CONTEXT"
printf 'Minikube profile: %s\n' "$MINIKUBE_PROFILE"
printf '\nCluster info:\n'
kubectl cluster-info || true
printf '\nNamespaces currently present:\n'
kubectl get ns

if [ "$ASSUME_YES" != "true" ]; then
  printf '\nType the exact kubectl context name to continue: '
  read -r CONFIRM_CONTEXT
  if [ "$CONFIRM_CONTEXT" != "$CURRENT_CONTEXT" ]; then
    printf 'Context confirmation did not match. Aborting.\n' >&2
    exit 1
  fi

  printf 'Final confirmation: delete tutorial resources from context "%s"? [y/N]: ' "$CURRENT_CONTEXT"
  read -r CONFIRM_DELETE
  case "$CONFIRM_DELETE" in
    y|Y|yes|YES)
      ;;
    *)
      printf 'Aborting without making changes.\n'
      exit 1
      ;;
  esac
fi

printf '\nDeleting tutorial namespace if present...\n'
kubectl delete namespace tutorial --ignore-not-found=true --wait=true

printf '\nDeleting non-system user workloads from default namespace...\n'
kubectl delete deployment,job,cronjob,ingress,pvc,role,rolebinding -n default --all --ignore-not-found=true || true
kubectl delete pod -n default --all --ignore-not-found=true || true

printf '\nDeleting user-created services/configmaps/secrets/serviceaccounts from default namespace while preserving cluster defaults...\n'
kubectl get svc -n default -o name 2>/dev/null | grep -v '^service/kubernetes$' | xargs -r kubectl delete -n default || true
kubectl get configmap -n default -o name 2>/dev/null | grep -v '^configmap/kube-root-ca.crt$' | xargs -r kubectl delete -n default || true
kubectl get secret -n default -o name 2>/dev/null | xargs -r kubectl delete -n default || true
kubectl get sa -n default -o name 2>/dev/null | grep -v '^serviceaccount/default$' | xargs -r kubectl delete -n default || true

printf '\nDeleting completed/failed pods in all non-system namespaces...\n'
while IFS= read -r ns; do
  [ -z "$ns" ] && continue
  case "$ns" in
    kube-system|kube-public|kube-node-lease) continue ;;
  esac
  kubectl delete pod -n "$ns" --field-selector=status.phase==Succeeded --ignore-not-found=true || true
  kubectl delete pod -n "$ns" --field-selector=status.phase==Failed --ignore-not-found=true || true
done < <(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

printf '\nCurrent namespaces:\n'
kubectl get ns
printf '\nCurrent workload summary:\n'
kubectl get all -A
