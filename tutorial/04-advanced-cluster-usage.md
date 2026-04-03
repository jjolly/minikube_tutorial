# Part 4. Advanced cluster usage

## 4.1 Secrets

A **Secret** stores sensitive values such as passwords, tokens, and connection strings.

Example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: example-secret
  namespace: tutorial
type: Opaque
stringData:
  username: demo
  password: super-secret-value
```

We use Secrets in the journal examples for SQL Server credentials and connection strings.

## 4.2 RBAC

**RBAC** controls who can do what in Kubernetes.

Namespaces matter here because permissions are often granted within a namespace boundary rather than across the whole cluster.

Example file: `config/05-journal/12-rbac-readonly.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tutorial-reader
  namespace: tutorial
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tutorial-readonly
  namespace: tutorial
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tutorial-readonly-binding
  namespace: tutorial
subjects:
  - kind: ServiceAccount
    name: tutorial-reader
    namespace: tutorial
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: tutorial-readonly
```

Apply it:

```bash
kubectl apply -f config/05-journal/12-rbac-readonly.yaml
kubectl auth can-i list pods --as=system:serviceaccount:tutorial:tutorial-reader -n tutorial
kubectl auth can-i create deployments --as=system:serviceaccount:tutorial:tutorial-reader -n tutorial || true
```

The second command should print `no`.

## 4.3 Advanced topics: Gateway and alternatives to Ingress

The main tutorial intentionally stays with Ingress. But there are more advanced options worth considering after the core lessons are complete.

See:

- `config/advanced/gateway-options.md`

Summary of options:

- **NGINX Gateway Fabric**
- **Envoy Gateway**
- **Cilium Gateway API**
- **Istio Gateway API support**

### 4.4 Recommendation

Keep the main tutorial on **Ingress**.

If you later want one advanced Gateway-focused extension, the best first options are:

1. **NGINX Gateway Fabric**
2. **Envoy Gateway**

## 4.5 Exercise notes and possible solutions

This tutorial includes a few small challenge prompts meant to slow the reader down just enough to think about what Kubernetes is doing.

These are not the only correct ways to reason about the exercises, but they provide useful reference answers if you got stuck.

### 4.6 Pod access challenge from section 2.5

Question:

- can you adapt the earlier in-cluster access pattern so it reaches `echo-pod` instead of `simple-echo-pod`?

One solution:

```bash
POD_IP=$(kubectl get pod echo-pod -o jsonpath='{.status.podIP}')
kubectl run netshoot-pod-check --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc "curl -fsS http://$POD_IP:5678"
```

Expected shape of response:

```text
hello from echo-pod
```

### 4.7 Namespace default challenge from section 2.11

Question:

- why does `kubectl get pods` show different results from `kubectl get pods -n default` after you changed the current context namespace?

Possible explanation:

- `kubectl get pods` now uses the context's default namespace, which you set to `tutorial`
- `kubectl get pods -n default` overrides that default and explicitly asks for objects in `default`
- this is a reminder that the current context can carry a namespace preference, but explicit `-n` flags still win

### 4.8 Label selector challenge from section 2.13

Question:

- what happens if you run `kubectl get pods -n tutorial -l tier=demo` before the Deployment exists?

Possible explanation:

- you likely get no results yet
- that is because the earlier standalone Pod used the `app=echo` label, but not `tier=demo`
- the `tier=demo` label appears later in the Deployment's Pod template

### 4.9 Deployment observation challenge from section 2.15

Questions:

- after scaling to 3 replicas, how many Pods should you expect?
- what label can be used to list only the Pods for this app?
- what might happen if you send several requests through the Service?

Possible explanation:

- you should expect three Deployment-managed Pods once the rollout completes
- `app=echo` is the key label used throughout the example
- repeated requests through the Service may return different Pod names, because the Service can send traffic to any matching healthy replica

One way to test that:

```bash
kubectl port-forward -n tutorial service/echo-service 8080:80
```

Then in another terminal:

```bash
for i in 1 2 3 4 5; do curl -s http://127.0.0.1:8080; done
```

Possible output shape:

```text
hello from echo-deployment-7d8c6c9f5b-abc12
hello from echo-deployment-7d8c6c9f5b-def34
hello from echo-deployment-7d8c6c9f5b-abc12
hello from echo-deployment-7d8c6c9f5b-ghi56
hello from echo-deployment-7d8c6c9f5b-def34
```

You might not see all replicas in a short run, and the exact sequence can vary. The main lesson is that the responses do not have to come from one fixed Pod.

### 4.10 Ingress route prediction challenge from section 3.11

Questions:

- which backend should receive `/genkey/`?
- which backend should receive `/genkey/api`?
- which backend should receive `/journal/`?

Possible explanation:

- `/genkey/` should route to the `genkey-web` Service
- `/genkey/api` also reaches the `genkey-web` Service first in this tutorial's setup, and that frontend nginx then proxies the API path to the backend API Service
- `/journal/` should route to the `journal-web` Service

The key lesson is that Ingress routes to Services, and a Service or frontend proxy may then forward deeper into the application.

## 4.11 What is already ready for polish later

This version is meant to have the right **structure**, **teaching contrasts**, and **object ordering** first.

During a later polish phase, the highest-value upgrades will be:

- expected command output gathered from actually running the steps
- screenshots if desired
- stronger diagrams and request-flow sketches
- additional troubleshooting callouts after each multi-step example
- possibly replacing the key-generation demo with a safer interactive Flask example if you decide to do that later
