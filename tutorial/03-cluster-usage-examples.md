# Part 3. Cluster usage examples

## 12. Static nginx web page using a ConfigMap

This is the first frontend pattern in the tutorial.

```text
ConfigMap (index.html)
        |
        v
  mounted into nginx Pod
        |
        v
   Service/static-nginx
        |
        v
   kubectl port-forward
        |
        v
      browser/curl
```

File: `config/02-static-nginx/static-site.yaml`

Apply the manifest:

```bash
kubectl apply -f config/02-static-nginx/static-site.yaml
```

What this single file creates:

- a ConfigMap containing the HTML page
- a Deployment running nginx
- a Service exposing that nginx Pod inside the cluster

Port-forward the Service:

```bash
kubectl port-forward -n tutorial service/static-nginx 8080:80
```

Important timing note:

- like other `port-forward` commands in the tutorial, this one stays attached to the current terminal
- leave it running while you test from another terminal or browser

In another terminal:

```bash
curl http://127.0.0.1:8080
```

This stage is useful because it shows three layers working together:

1. a ConfigMap stores content
2. a Deployment runs nginx and mounts that content
3. a Service gives you a stable way to reach the nginx Pod

## 13. Basic Flask `/genkey` service behind nginx

This stage introduces a reverse proxy and service-to-service routing.

Architecture:

```text
browser/curl
    |
    v
Service/genkey-basic-proxy
    |
    v
nginx Pod
    |
    v
Service/genkey-basic-api
    |
    v
Flask API Pod
```

Build the API image into minikube:

```bash
cd src/03-genkey-basic
minikube image build -t genkey-basic-api:0.1.0 .
cd ../..
```

Why this is written as a small sequence:

- first you move into the directory that contains the Docker build context
- then `minikube image build` builds the image directly into minikube's image store
- finally you return to the repository root so later commands match the file paths shown in the tutorial

Apply the Kubernetes manifests:

```bash
kubectl apply -f config/03-genkey-basic/genkey-basic.yaml
```

What this creates:

- a ConfigMap for nginx configuration
- a Deployment and Service for the Flask API
- a Deployment and Service for the nginx reverse proxy

Port-forward the proxy Service:

```bash
kubectl port-forward -n tutorial service/genkey-basic-proxy 8081:80
```

In a second terminal:

```bash
curl http://127.0.0.1:8081/genkey
```

Expected response shape:

```json
{
  "privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----...",
  "publicKey": "ssh-ed25519 AAAA..."
}
```

### Important note about this example

This is a convenient **teaching example** for:

- Service-to-Service communication by DNS name
- nginx acting as a reverse proxy inside the cluster
- container image build and local deployment

It is **not** a production-safe key-management design. Returning generated private keys over HTTP is useful for a small lab, but it should not be copied directly into a real security-sensitive system.

If you later want a safer interactive Flask example, good alternatives would be:

- random passphrase generation
- slug or identifier generation
- hash or encoding demonstrations
- simple text transformation APIs

## 14. Richer frontend: built image instead of ConfigMap assets

Now revisit frontend delivery with a better packaging model.

```text
browser
  |
  v
Service/genkey-web
  |
  v
nginx frontend Pod  -- /genkey/api -->  Service/genkey-api  -->  Flask API Pod
  |
  '-- /genkey/ --> serves built React frontend files
```

Build the backend image first:

```bash
cd src/04-genkey-full/backend
minikube image build -t genkey-api:0.1.0 .
```

Then build the frontend image:

```bash
cd ..
minikube image build -f Dockerfile.frontend -t genkey-web:0.1.0 .
cd ../..
```

Why the build is split in two:

- the backend and frontend are packaged separately
- each image has its own build context and purpose
- keeping the commands separate makes it clearer which artifact you are building at each step

Apply the manifests:

```bash
kubectl apply -f config/04-genkey-full/image-based/
```

Port-forward the frontend Service:

```bash
kubectl port-forward -n tutorial service/genkey-web 8082:80
```

Open:

- `http://127.0.0.1:8082/genkey/`

Or verify the proxied API path directly:

```bash
curl http://127.0.0.1:8082/genkey/api
```

This stage matters because it shows the contrast between:

1. ConfigMap-mounted static files
2. a built frontend image

For a richer frontend, the image-based approach is usually cleaner and more realistic.

## 15. Journal application, first approach: schema init inside API startup

This first journal deployment uses the simplest developer-friendly pattern:

```text
browser
  |
  v
Service/journal-web
  |
  v
nginx web Pod  -- /journal/api -->  Service/journal-api  -->  C# API Pod
                                                          |
                                                          '-- startup schema creation --> Service/journal-db --> SQL Server Pod + PVC
```

### Why show this approach first?

Because it is understandable and practical:

- fewer Kubernetes objects
- the schema logic is visible in the application itself
- easy to reason about as a first implementation

### Important limitation

This approach is **not optimal** because the API runtime needs broader database privileges than it needs for normal request handling.

### Apply the first-step manifests in phases

Build the journal API image:

```bash
cd src/05-journal/api
minikube image build -t journal-api:0.1.0 .
cd ../../..
```

Why start with the image build?

Because the cluster cannot run the journal API Deployment until the image exists in minikube.

Apply the Secret, PVC, database Deployment, and database Service first:

```bash
kubectl apply -f config/05-journal/step1-startup-init/00-secret.yaml
kubectl apply -f config/05-journal/step1-startup-init/01-pvc.yaml
kubectl apply -f config/05-journal/step1-startup-init/02-db-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/03-db-service.yaml
```

Why these are grouped together:

- the Secret provides the database credentials
- the PVC provides durable storage
- the database Deployment starts SQL Server
- the database Service gives SQL Server a stable in-cluster name

Wait for SQL Server:

```bash
kubectl get pods -n tutorial -w
kubectl rollout status deployment/journal-db -n tutorial
```

Why two monitoring commands?

- `kubectl get pods -w` gives you a live stream of Pod state changes
- `kubectl rollout status` gives you a cleaner Deployment-level success signal

Then apply the API and web resources:

```bash
kubectl apply -f config/05-journal/step1-startup-init/04-api-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/05-api-service.yaml
kubectl apply -f config/05-journal/step1-startup-init/06-web-assets-configmap.yaml
kubectl apply -f config/05-journal/step1-startup-init/07-web-nginx-configmap.yaml
kubectl apply -f config/05-journal/step1-startup-init/08-web-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/09-web-service.yaml
```

What this second phase adds:

- the API Deployment and Service
- the frontend assets and nginx configuration
- the web Deployment and Service

Check health by forwarding the API locally:

```bash
kubectl port-forward -n tutorial service/journal-api 8084:8080
```

In another terminal:

```bash
curl http://127.0.0.1:8084/healthz
```

Expected response:

```json
{"status":"ok","autoMigrate":true}
```

That `autoMigrate: true` value matters. It tells you the API is still doing schema work during startup.

## 16. Journal application, improved approach: dedicated database-init Job

Now split schema initialization away from the API.

```text
Job/journal-db-init  -->  Service/journal-db  -->  SQL Server Pod + PVC

browser
  |
  v
Service/journal-web
  |
  v
nginx web Pod  -- /journal/api -->  Service/journal-api  -->  C# API Pod

(schema work is no longer part of normal API startup)
```

### Why this approach is better

- clearer separation of concerns
- easier to observe and debug independently
- better security posture
- better cluster deployment strategy

If you already ran the startup-init version, remove it before applying the improved version:

```bash
kubectl delete -f config/05-journal/step1-startup-init/
```

This cleanup matters because the improved version recreates some of the same application pieces with a different initialization strategy.

Apply the improved manifests:

```bash
kubectl apply -f config/05-journal/step2-job-init/
```

Inspect the live state:

```bash
kubectl get pods,jobs -n tutorial
```

Wait for the one-time initialization Job to finish:

```bash
kubectl wait --for=condition=complete job/journal-db-init -n tutorial --timeout=600s
```

Read the Job logs:

```bash
kubectl logs -n tutorial job/journal-db-init
```

Why these are separate steps:

- `apply` creates everything
- `get pods,jobs` shows you what exists right now
- `wait` blocks until the one-time schema setup finishes or times out
- `logs` lets you see what the Job actually did

Then check the API health:

```bash
kubectl port-forward -n tutorial service/journal-api 8085:8080
```

In another terminal:

```bash
curl http://127.0.0.1:8085/healthz
```

Expected response:

```json
{"status":"ok","autoMigrate":false}
```

That `autoMigrate: false` value matters. It tells you schema work has been moved out of the API startup path.

## 17. Ingress in the application example

Up to this point, you have used `kubectl port-forward` to reach Services. That is excellent for learning and debugging, but it is not how you usually want users to reach multiple HTTP applications.

This is where **Ingress** helps.

### Why Ingress is useful here

The tutorial now has more than one HTTP-facing app:

- `/genkey`
- `/journal`

Ingress provides one HTTP entrypoint and lets you route requests by host and path.

Useful mental model:

```text
request: Host=tutorial.local, Path=/genkey/... or /journal/...
                 |
                 v
         ingress-nginx controller
                 |
        +--------+--------+
        |                 |
        v                 v
 Service/genkey-web   Service/journal-web
```

There are many ways to expose Kubernetes applications. In this tutorial, Ingress is the right next step because:

- it matches common Kubernetes usage
- minikube supports it easily with the ingress addon
- it cleanly demonstrates path-based routing for both applications

File: `config/05-journal/13-ingress.yaml`

Apply the Ingress object:

```bash
kubectl apply -f config/05-journal/13-ingress.yaml
```

Inspect it:

```bash
kubectl get ingress -n tutorial
```

Get the minikube IP and the ingress controller's NodePort:

```bash
MINIKUBE_IP=$(minikube ip)
NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
echo "$MINIKUBE_IP"
echo "$NODEPORT"
```

Why this is split out:

- the Ingress object defines routing rules
- these extra commands discover how the ingress controller is actually reachable in your local minikube environment

### Small challenge

Before you run the three `curl` commands below, look at the Ingress manifest and make a prediction:

- which backend should receive `/genkey/`?
- which backend should receive `/genkey/api`?
- which backend should receive `/journal/`?

That is a useful habit in Kubernetes: read the routing rule first, then test whether the live system behaves the way you expected.

Test the routes with the expected host header:

```bash
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/genkey/"
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/genkey/api"
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/journal/"
```

This is the final proof that a single ingress entrypoint can route to multiple backend Services by path.

---
