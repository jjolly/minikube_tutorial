#!/usr/bin/env bash
set -euo pipefail

# Reset the cluster to a clean tutorial-ready state while preserving
# minikube itself and core system namespaces/components.

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"

printf 'Updating kubectl context for profile: %s\n' "$MINIKUBE_PROFILE"
minikube -p "$MINIKUBE_PROFILE" update-context >/dev/null

printf '\nDeleting tutorial namespace if present...\n'
kubectl delete namespace tutorial --ignore-not-found=true --wait=true

printf '\nDeleting non-system workload objects from default namespace...\n'
kubectl delete deployment,service,job,cronjob,ingress,configmap,secret,pvc,serviceaccount,role,rolebinding -n default --all --ignore-not-found=true || true
kubectl delete pod -n default --all --ignore-not-found=true || true

printf '\nDeleting completed/failed pods in all non-system namespaces...\n'
for ns in $(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -Ev '^(kube-system|kube-public|kube-node-lease)$'); do
  kubectl delete pod -n "$ns" --field-selector=status.phase==Succeeded --ignore-not-found=true || true
  kubectl delete pod -n "$ns" --field-selector=status.phase==Failed --ignore-not-found=true || true
done

printf '\nCurrent namespaces:\n'
kubectl get ns
printf '\nCurrent workload summary:\n'
kubectl get all -A
