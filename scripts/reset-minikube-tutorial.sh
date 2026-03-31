#!/usr/bin/env bash
set -euo pipefail

# Reset the cluster to a clean tutorial-ready state while preserving
# minikube itself and cluster-created default/system resources.

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"

printf 'Updating kubectl context for profile: %s
' "$MINIKUBE_PROFILE"
minikube -p "$MINIKUBE_PROFILE" update-context >/dev/null

printf '
Deleting tutorial namespace if present...
'
kubectl delete namespace tutorial --ignore-not-found=true --wait=true

printf '
Deleting non-system user workloads from default namespace...
'
kubectl delete deployment,job,cronjob,ingress,pvc,role,rolebinding -n default --all --ignore-not-found=true || true
kubectl delete pod -n default --all --ignore-not-found=true || true

printf '
Deleting user-created services/configmaps/secrets/serviceaccounts from default namespace while preserving cluster defaults...
'
kubectl get svc -n default -o name 2>/dev/null | grep -v '^service/kubernetes$' | xargs -r kubectl delete -n default || true
kubectl get configmap -n default -o name 2>/dev/null | grep -v '^configmap/kube-root-ca.crt$' | xargs -r kubectl delete -n default || true
kubectl get secret -n default -o name 2>/dev/null | xargs -r kubectl delete -n default || true
kubectl get sa -n default -o name 2>/dev/null | grep -v '^serviceaccount/default$' | xargs -r kubectl delete -n default || true

printf '
Deleting completed/failed pods in all non-system namespaces...
'
for ns in $(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"
"}{end}' | grep -Ev '^(kube-system|kube-public|kube-node-lease)$'); do
  kubectl delete pod -n "$ns" --field-selector=status.phase==Succeeded --ignore-not-found=true || true
  kubectl delete pod -n "$ns" --field-selector=status.phase==Failed --ignore-not-found=true || true
done

printf '
Current namespaces:
'
kubectl get ns
printf '
Current workload summary:
'
kubectl get all -A
