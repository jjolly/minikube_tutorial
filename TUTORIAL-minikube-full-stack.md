# Minikube Tutorial: From First Pods to a Reverse-Proxy Stack and Stateful Journal App

This tutorial is a progressive guide to learning Kubernetes on **minikube** running inside **WSL Linux**. It is aimed at a setup that should be general enough for **Ubuntu** and **openSUSE Leap** inside WSL.

The tutorial deliberately teaches by contrast in a few places:

- first a simple, workable approach
- then a stronger, more production-like approach
- then an explanation of why the second approach is better

That teaching pattern appears in two especially important places:

1. **frontend assets**
   - first: ConfigMap-mounted static files
   - later: packaged frontend image
2. **database initialization**
   - first: schema creation in API startup
   - later: schema creation in a dedicated Kubernetes Job

By the end, you will have:

- a simple pod and service
- a static nginx web page
- a Flask `/genkey` service behind nginx
- a React frontend under `/genkey` with a Flask API at `/genkey/api`
- a C# journal application backed by Microsoft SQL Server with persistent storage
- an Ingress route exposing both `/genkey` and `/journal`

---

## 0. What you are building and why

Minikube gives you a local Kubernetes cluster you can experiment with safely. On WSL, that means you can learn the Kubernetes object model and application deployment flow without renting cloud infrastructure first.

The tutorial introduces these Kubernetes ideas in this order:

1. Pods
2. Services
3. Networking
4. Namespaces
5. Labels
6. Deployments
7. kube-apiserver
8. Nodes and kubelet
9. etcd
10. Secrets
11. ConfigMaps
12. Persistent Volumes
13. RBAC
14. Ingress
15. Advanced topics: Gateway API options

---

## 1. Prerequisites

You already have minikube running, which is a good starting point. This section documents a general install path so the tutorial is self-contained.

### 1.1 Ubuntu packages

```bash
sudo apt update
sudo apt install -y curl wget tar conntrack socat git ca-certificates
```

If using Docker as the minikube driver:

```bash
sudo apt install -y docker.io
sudo usermod -aG docker "$USER"
newgrp docker
```

### 1.2 openSUSE Leap packages

```bash
sudo zypper refresh
sudo zypper install -y curl wget tar conntrack-tools socat git ca-certificates
```

If using Docker:

```bash
sudo zypper install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker
```

### 1.3 Install kubectl

`kubectl` is the command-line client for the Kubernetes API server.

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

### 1.4 Install minikube

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version
```

### 1.5 Start and verify the cluster

```bash
minikube start --driver=docker
kubectl get nodes
kubectl cluster-info
```

### Note for later refinement: container runtimes and driver choice

During the polish phase, this tutorial should add a short comparison of the common container-runtime and driver choices available in a local minikube workflow, and explain why Docker was chosen here. The short version is that Docker is being used in this tutorial because it is common, familiar, and usually the least surprising path for a WSL-based learning environment.

### 1.6 Enable ingress

Ingress is the primary HTTP exposure path used in the main tutorial.

```bash
minikube addons enable ingress
minikube addons enable metrics-server
```

---

## 2. Repository layout

```text
src/
  02-nginx-static/
  03-genkey-basic/
  04-genkey-full/
  05-journal/
config/
  01-pods/
  02-static-nginx/
  03-genkey-basic/
  04-genkey-full/
  05-journal/
  advanced/
```

- `src/` contains application source code and Docker build inputs.
- `config/` contains Kubernetes manifests.
- `config/05-journal/step1-startup-init/` contains the first database-init approach.
- `config/05-journal/step2-job-init/` contains the improved database-init approach.

---

## 3. Pods

A **pod** is the smallest deployable unit in Kubernetes. A pod usually runs one application container, though it can run more than one when the containers are meant to cooperate tightly.

### 3.1 Run a short-lived BusyBox pod

```bash
kubectl run bb-demo --image=busybox:1.36 --restart=Never --command -- sh -c 'echo hello from kubernetes && sleep 15'
kubectl logs bb-demo
kubectl get pod bb-demo
kubectl delete pod bb-demo
```

### 3.2 Create a long-running pod from YAML

File: `config/01-pods/pod-echo.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: echo-pod
  labels:
    app: echo
spec:
  containers:
    - name: echo
      image: hashicorp/http-echo:1.0.0
      args:
        - "-text=hello from echo-pod"
      ports:
        - containerPort: 5678
```

What the fields are for:

- `apiVersion: v1` — says this object uses the core v1 Kubernetes API.
- `kind: Pod` — declares the object type.
- `metadata.name` — gives the object its cluster-local name.
- `metadata.labels` — attaches identifying key/value metadata for selection and grouping.
- `spec.containers` — lists containers that should run inside the pod.
- `image` — container image to launch.
- `args` — command arguments passed to the container entrypoint.
- `containerPort` — documents the port the container listens on.

Apply it:

```bash
kubectl apply -f config/01-pods/pod-echo.yaml
kubectl get pods -o wide
kubectl describe pod echo-pod
```

What you should observe:

- `kubectl apply` should report `pod/echo-pod created` the first time
- `kubectl get pods -o wide` should eventually show `echo-pod` in `Running`
- the pod should be scheduled onto your minikube node

Example shape of output:

```text
NAME       READY   STATUS    RESTARTS   AGE   IP           NODE
echo-pod   1/1     Running   0          23s   10.244.0.6   minikube
```

---

## 4. Services

Pods are ephemeral. A pod can be recreated and receive a different IP address. A **Service** gives a stable virtual IP and DNS name that can target one or more matching pods.

This is one of the most important mental-model shifts in Kubernetes:

- you usually do **not** build application communication around Pod IPs
- you usually build it around **Services**

Pods come and go. Services give other workloads a stable way to find the current healthy backend Pods.

File: `config/01-pods/service-echo.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: echo-service
spec:
  selector:
    app: echo
  ports:
    - port: 80
      targetPort: 5678
```

What the fields are for:

- `kind: Service` — declares a stable network endpoint.
- `selector` — chooses pods with matching labels.
- `port` — port exposed by the Service.
- `targetPort` — port on the selected pods.

```bash
kubectl apply -f config/01-pods/service-echo.yaml
kubectl port-forward service/echo-service 8080:80
curl http://127.0.0.1:8080
```

What you should observe:

- the Service should be created immediately
- `kubectl port-forward` should hold the terminal open while forwarding traffic
- the `curl` request should return the text served by the container through the Service

Expected response:

```text
hello from echo-pod
```

This is an important moment in the tutorial: you are no longer talking to the Pod directly. You are talking to a stable Service endpoint that selects the Pod.

Troubleshooting:

- if `curl` cannot connect, make sure `kubectl port-forward` is still running in the foreground
- if the Service exists but does not answer, run `kubectl get pods -n tutorial --show-labels` and confirm the Pod still has `app=echo`
- if needed, inspect the Service selector with `kubectl get svc echo-service -n tutorial -o yaml`

---

## 5. Kubernetes networking

Kubernetes networking is built around a few expectations:

- every pod gets an IP
- pods can usually talk directly to other pods
- Services provide stable names and virtual IPs
- cluster DNS resolves Service names automatically

Test from a temporary shell pod:

```bash
kubectl run netshoot --image=nicolaka/netshoot:latest -it --rm -- sh
nslookup echo-service
curl http://echo-service
```

What you should observe:

- `nslookup echo-service` should resolve the Service name using cluster DNS
- `curl http://echo-service` should return the same echo text as before
- this demonstrates that Pods inside the cluster can reach Services by DNS name instead of hard-coded IP addresses

Expected response from `curl`:

```text
hello from echo-pod
```

Troubleshooting:

- if `nslookup echo-service` fails, check that you are still inside the temporary shell pod and that the Service exists in the same namespace
- if DNS resolves but `curl` fails, verify that the backend Pod is running and that the Service selector matches it
- if the temporary pod exits too quickly, rerun the `kubectl run netshoot ...` command and test again

---

## 6. Namespaces

A **namespace** groups resources so you can separate environments and reduce clutter.

File: `config/01-pods/namespace-tutorial.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tutorial
```

```bash
kubectl apply -f config/01-pods/namespace-tutorial.yaml
kubectl apply -n tutorial -f config/01-pods/pod-echo.yaml
kubectl apply -n tutorial -f config/01-pods/service-echo.yaml
kubectl get all -n tutorial
```

---

## 7. Labels

**Labels** are key/value pairs attached to objects. Kubernetes uses them heavily for selection.

Examples:

- a Service uses labels to decide which pods are backends
- a Deployment uses labels to identify the pods it manages
- operators use labels to filter resources

```bash
kubectl get pods -n tutorial --show-labels
kubectl get pods -n tutorial -l app=echo
```

---

## 8. Deployments

A **Deployment** manages rollout for a stateless application.

A **stateless application** is one where an individual application instance does not hold the only copy of important long-term data inside its own process or filesystem. If the container restarts, another identical instance can usually take over.

Examples of stateless applications:

- nginx serving static files from an image or ConfigMap
- a C# API that stores durable data in SQL Server

Why is the C# API still considered stateless even though it works with durable data?

Because the durable data lives in **SQL Server**, not inside the API container itself. The API can be replaced, restarted, or scaled out, and another identical API replica can still serve requests as long as it can reach the database.

A stateful application, by contrast, keeps important durable state locally or depends on stable identity. SQL Server storing database files is the clearest stateful example in this tutorial.

A useful rule of thumb is:

- if you can replace one replica with another identical replica without losing the application's durable data, that part is usually **stateless**
- if the workload itself owns the durable storage or needs a stable identity, it is usually **stateful**

File: `config/01-pods/deployment-echo.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-deployment
  labels:
    app: echo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: echo
  template:
    metadata:
      labels:
        app: echo
        tier: demo
        lesson: deployments
    spec:
      containers:
        - name: echo
          image: hashicorp/http-echo:1.0.0
          args:
            - "-text=hello from echo-deployment"
          ports:
            - containerPort: 5678
```

What the important fields do:

- `replicas` — desired number of pod copies.
- `selector.matchLabels` — tells the Deployment which pods belong to it.
- `template` — pod template used for each replica.

```bash
kubectl delete pod -n tutorial echo-pod --ignore-not-found
kubectl apply -n tutorial -f config/01-pods/deployment-echo.yaml
kubectl scale deployment/echo-deployment -n tutorial --replicas=3
```

What you should observe:

- the old standalone Pod is removed
- the Deployment creates replacement Pods under ReplicaSet control
- after scaling, you should see three running replicas

A useful verification command is:

```bash
kubectl get pods -n tutorial -o wide
```

Example shape of output after scaling:

```text
NAME                               READY   STATUS    RESTARTS   AGE
echo-deployment-...                1/1     Running   0          ...
echo-deployment-...                1/1     Running   0          ...
echo-deployment-...                1/1     Running   0          ...
```

This is the point where Kubernetes starts managing a desired replica count for you instead of just running a single unmanaged Pod.

---

## 9. kube-apiserver

The **kube-apiserver** is the front door to the cluster. `kubectl`, controllers, and other cluster components all interact with Kubernetes by talking to the API server.

```bash
kubectl api-resources | head -40
kubectl api-versions
kubectl config current-context
kubectl cluster-info
kubectl get deployment echo-deployment -n tutorial -o yaml
```

---

## 10. Nodes and kubelet

A **node** is a machine that runs workloads. In minikube, you typically have one node. The **kubelet** is the agent on that node that makes sure the assigned containers actually run.

```bash
kubectl get nodes -o wide
kubectl describe node minikube
kubectl get pods -n kube-system -o wide
```

---

## 11. etcd

**etcd** is the key-value store that holds cluster state. When you create a namespace, secret, deployment, or service, the desired state is stored through the API server and backed by etcd.

```bash
kubectl get pods -n kube-system
```

Look for an `etcd-*` pod in the control plane.

---

## 12. Secrets

A **Secret** stores sensitive values such as passwords, tokens, and connection strings.

Conceptually, this section fits well after etcd because Secrets are Kubernetes objects too. They are stored as part of cluster state, even though they are handled separately from ordinary configuration data.

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

Field intent:

- `type: Opaque` — generic Secret type.
- `stringData` — convenient plaintext input that Kubernetes converts into the stored Secret form.

We will use Secrets for SQL Server credentials later in the tutorial.

---

## 13. ConfigMaps

A **ConfigMap** stores non-secret configuration data.

Typical ConfigMap use cases:

- small application config files
- environment-specific settings
- small static content for simple demonstrations

Example:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-config
  namespace: tutorial
data:
  app-mode: tutorial
  index.html: |
    <h1>Hello from a ConfigMap</h1>
```

Field intent:

- `data` — key/value content stored in the ConfigMap.
- multiline entries under `data` are useful when storing small files.

We will first use ConfigMaps for a static web page because they are very easy to inspect and teach. Later we will contrast that with building frontend assets into an image.

---

## 14. Static nginx web page using a ConfigMap

This is the first frontend pattern in the tutorial.

**Why use a ConfigMap here?**

Because it is a great teaching tool:

- you can see the HTML directly in YAML
- you can mount the content into nginx without building an image
- it shows how Kubernetes can inject files into a container at runtime

File: `config/02-static-nginx/static-site.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: static-site-content
  namespace: tutorial
data:
  index.html: |
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>Minikube Tutorial - Static Site</title>
      </head>
      <body>
        <h1>nginx is serving this page from Kubernetes</h1>
        <p>This page comes from a ConfigMap-mounted file.</p>
      </body>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: static-nginx
  namespace: tutorial
spec:
  replicas: 1
  selector:
    matchLabels:
      app: static-nginx
  template:
    metadata:
      labels:
        app: static-nginx
        tier: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: site-content
              mountPath: /usr/share/nginx/html/index.html
              subPath: index.html
      volumes:
        - name: site-content
          configMap:
            name: static-site-content
---
apiVersion: v1
kind: Service
metadata:
  name: static-nginx
  namespace: tutorial
spec:
  selector:
    app: static-nginx
  ports:
    - port: 80
      targetPort: 80
```

Pay attention to these fields:

- `ConfigMap.data.index.html` — stores the page content.
- `volumes.configMap.name` — connects the pod to the ConfigMap.
- `volumeMounts.subPath` — mounts just one file from the ConfigMap to the nginx document root.

```bash
kubectl apply -f config/02-static-nginx/static-site.yaml
kubectl port-forward -n tutorial service/static-nginx 8080:80
```

In another terminal, request the page directly:

```bash
curl http://127.0.0.1:8080
```

What you should observe:

- the Deployment and Service should be created
- the forwarded request should return HTML from nginx
- the page content should match the HTML stored in the ConfigMap

Expected response:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Minikube Tutorial - Static Site</title>
  </head>
  <body>
    <h1>nginx is serving this page from Kubernetes</h1>
    <p>This page comes from a ConfigMap-mounted file.</p>
  </body>
</html>
```

This is your first example of Kubernetes injecting file content into a container at runtime.

Troubleshooting:

- if the page does not load, check `kubectl get pods -n tutorial` and make sure `static-nginx` is `Running`
- if nginx is running but the page content is wrong, inspect the mounted ConfigMap with `kubectl get configmap static-site-content -n tutorial -o yaml`
- if port-forward fails, confirm the Service exists with `kubectl get svc -n tutorial`

---

## 15. Basic Flask `/genkey` service behind nginx

This stage introduces a reverse proxy and service-to-service routing.

Architecture:

- `genkey-basic-api` — Flask app serving `/genkey`
- `genkey-basic-proxy` — nginx reverse proxy

Build the API image into minikube:

```bash
cd src/03-genkey-basic
minikube image build -t genkey-basic-api:0.1.0 .
cd ../..
```

Deploy it:

```bash
kubectl apply -f config/03-genkey-basic/genkey-basic.yaml
kubectl port-forward -n tutorial service/genkey-basic-proxy 8081:80
curl http://127.0.0.1:8081/genkey
```

What you should observe:

- both the API Deployment and nginx proxy Deployment should become available
- the response should be JSON rather than plain text or HTML
- the JSON should contain generated SSH key material

Expected response shape:

```json
{
  "privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----...",
  "publicKey": "ssh-ed25519 AAAA..."
}
```

This stage matters because it shows:

- Service-to-Service communication by DNS name
- nginx acting as a reverse proxy inside the cluster
- container image build and local deployment

Troubleshooting:

- if the API pod is stuck in `ImagePullBackOff`, the image probably was not built into minikube successfully; rebuild it and recheck the Deployment
- if `/genkey` returns an nginx error instead of JSON, inspect both the proxy pod logs and the API pod logs
- if the API is running but key generation fails, check the container logs for `ssh-keygen`-related errors

---

## 16. Richer frontend: built image instead of ConfigMap assets

Now we revisit frontend delivery with a better packaging model.

Earlier, the ConfigMap-mounted static site was useful because it taught ConfigMaps clearly. But for a richer frontend application, packaging the frontend into an image is a better pattern.

### Why a built image is better here

**ConfigMap-mounted assets**
- simple for tiny examples
- easy to inspect
- good for teaching ConfigMaps
- awkward for larger frontends
- not a normal packaging strategy for serious UI deployments

**Built frontend image**
- versioned artifact
- cleaner deployment manifests
- source tree matches what actually runs
- better reproducibility
- more realistic operational model

### Build the React frontend image and Flask backend image

```bash
cd src/04-genkey-full/backend
minikube image build -t genkey-api:0.1.0 .
cd ..
minikube image build -f Dockerfile.frontend -t genkey-web:0.1.0 .
cd ../..
```

Apply the image-based manifests:

```bash
kubectl apply -f config/04-genkey-full/image-based/
kubectl port-forward -n tutorial service/genkey-web 8082:80
```

Open:

- `http://127.0.0.1:8082/genkey/`

You can also verify the proxied API path through the frontend entrypoint:

```bash
curl http://127.0.0.1:8082/genkey/api
```

What you should observe:

- `/genkey/` should return HTML for the frontend shell
- `/genkey/api` should return JSON with generated key material
- the nginx frontend image is now serving the UI and proxying API requests to the backend Service

Expected response shapes:

```html
<!doctype html>
<html lang="en">
  <head>
    <title>GenKey UI</title>
    ...
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
```

```json
{
  "algorithm": "ed25519",
  "publicKey": "ssh-ed25519 AAAA...",
  "privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----..."
}
```

At this point you have seen both patterns:

1. ConfigMap-mounted static files
2. built frontend image

The tutorial uses both on purpose so the reader understands the difference.

Troubleshooting:

- if `genkey-web` enters `ImagePullBackOff`, the frontend image likely was not built with the correct working directory or Dockerfile path
- the working build command used in verification was:

```bash
cd src/04-genkey-full
minikube image build -f Dockerfile.frontend -t genkey-web:0.1.0 .
```

- if `/genkey/` loads but `/genkey/api` returns 404, make sure you are testing through the frontend entrypoint and not calling the backend with the wrong path

---

## 17. Persistent Volumes

A **PersistentVolumeClaim** requests durable storage for a workload.

We need this for SQL Server because the journal database is stateful and should survive pod restarts.

Example file: `config/05-journal/step1-startup-init/01-pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mssql-data
  namespace: tutorial
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 8Gi
```

Field intent:

- `accessModes` — how the volume may be mounted.
- `resources.requests.storage` — requested storage size.

---

## 18. Journal application, first approach: schema init inside API startup

This first journal deployment uses the simplest developer-friendly pattern:

- SQL Server runs in the cluster
- the API starts with elevated DB privileges
- the API checks and creates the schema at startup
- the web frontend talks to the API through nginx

This is a very real pattern in small systems, and it is worth seeing first.

### Why show this approach first?

Because it is understandable and practical:

- fewer Kubernetes objects
- the schema logic is visible in the application itself
- easy to reason about as a first implementation

### Important limitation

This approach is **not optimal** because the API runtime now needs privileges that are broader than it needs for normal request handling.

It also creates a startup race:

- SQL Server may still be starting when the API tries to connect
- the API may fail on its first start if the database is not ready yet
- Kubernetes may restart the API pod until the database becomes reachable

That behavior is useful to observe because it shows one of the real operational drawbacks of schema creation during app startup.

### Build the journal API image

```bash
cd src/05-journal/api
minikube image build -t journal-api:0.1.0 .
cd ../../..
```

### Apply the first-step manifests in phases

Apply the Secret, persistent volume claim, database Deployment, and database Service first:

```bash
kubectl apply -f config/05-journal/step1-startup-init/00-secret.yaml
kubectl apply -f config/05-journal/step1-startup-init/01-pvc.yaml
kubectl apply -f config/05-journal/step1-startup-init/02-db-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/03-db-service.yaml
```

Now monitor SQL Server until it is actually ready:

```bash
kubectl get pods -n tutorial -w
kubectl rollout status deployment/journal-db -n tutorial
```

When you are satisfied that the database is up, apply the API and web resources:

```bash
kubectl apply -f config/05-journal/step1-startup-init/04-api-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/05-api-service.yaml
kubectl apply -f config/05-journal/step1-startup-init/06-web-assets-configmap.yaml
kubectl apply -f config/05-journal/step1-startup-init/07-web-nginx-configmap.yaml
kubectl apply -f config/05-journal/step1-startup-init/08-web-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/09-web-service.yaml
```

### How to monitor this step safely

Watch the API pod and logs before moving on:

```bash
kubectl get pods -n tutorial -w
kubectl logs -n tutorial -l app=journal-api --tail=100
kubectl rollout status deployment/journal-api -n tutorial
```

What can happen here:

- **best case**: SQL Server is ready in time, and the API starts cleanly
- **common race case**: the API starts too early, fails to connect, and restarts
- **continue only when** the `journal-api` Deployment reports successfully rolled out and the pod is `Running` and `Ready`

If the database became ready after the API had already failed several times, a manual restart is a simple way to continue cleanly:

```bash
kubectl rollout restart deployment/journal-api -n tutorial
kubectl rollout status deployment/journal-api -n tutorial
```

After the API is healthy, confirm it explicitly:

```bash
kubectl port-forward -n tutorial service/journal-api 8084:8080
curl http://127.0.0.1:8084/healthz
```

Expected healthy response:

```json
{"status":"ok","autoMigrate":true}
```

That `autoMigrate: true` value matters. It tells you that this first approach is still using API-startup schema management.

In another terminal, you can then expose the web frontend:

```bash
kubectl port-forward -n tutorial service/journal-web 8083:80
```

Open:

- `http://127.0.0.1:8083/journal/`

You can also confirm that the API can now write and read data:

```bash
curl -X POST http://127.0.0.1:8084/api/entries   -H 'Content-Type: application/json'   -d '{"title":"first entry","body":"created during startup-init verification"}'

curl http://127.0.0.1:8084/api/entries
```

Expected response shape:

```json
{"id":1}
```

```json
[
  {
    "id": 1,
    "title": "first entry",
    "body": "created during startup-init verification",
    "createdAt": "..."
  }
]
```

### What this step is demonstrating

- Secrets carrying SQL credentials
- PVC-backed SQL Server storage
- application-driven schema bootstrap
- nginx serving the journal UI and proxying `/journal/api/`
- how startup ordering problems appear in real clusters

### Why this is not the end state

Startup-based schema creation mixes deployment concerns into the API runtime:

- the API needs elevated privileges
- startup behavior becomes more complex
- multiple replicas can complicate initialization workflows
- database bootstrap and request serving are different operational concerns
- the database readiness race becomes part of normal application startup

That leads directly to the improved approach in the next section.

---

## 19. Journal application, improved approach: dedicated database-init Job

Now we split schema initialization away from the API.

In this version:

- SQL Server still starts with persistent storage
- a dedicated **Job** initializes the database schema
- the Job also creates a less-privileged application login
- the API runs with the application login instead of elevated schema-management privileges

### Why this approach is better

**Startup init inside API**
- simpler first implementation
- fewer cluster objects
- easier for a first pass
- but mixes bootstrap and runtime responsibilities
- and gives the API broader DB privileges than it should need

**Dedicated Job**
- clearer separation of concerns
- easier to observe and debug independently
- better security posture
- better cluster deployment strategy
- better teaching example for real Kubernetes workflows

The key conceptual difference is this:

- startup-init treats schema management as part of the application's normal boot path
- Job-based init treats schema management as a separate cluster task with its own lifecycle

That separation is usually healthier. It makes failures easier to locate, limits privileges in the steady-state API, and better matches how Kubernetes wants you to model one-time setup work.

### Apply the improved manifests

```bash
kubectl apply -f config/05-journal/step2-job-init/
kubectl get pods,jobs -n tutorial
kubectl logs -n tutorial job/journal-db-init
kubectl port-forward -n tutorial service/journal-web 8084:80
```

What you should observe:

- the SQL Server Deployment should become available
- the `journal-db-init` Job should move to `Complete`
- the API should start with `autoMigrate` disabled because schema management has been separated out

A useful direct health check is:

```bash
kubectl port-forward -n tutorial service/journal-api 8085:8080
curl http://127.0.0.1:8085/healthz
```

Expected healthy response:

```json
{"status":"ok","autoMigrate":false}
```

You can also verify end-to-end CRUD behavior:

```bash
curl -X POST http://127.0.0.1:8085/api/entries   -H 'Content-Type: application/json'   -d '{"title":"job init entry","body":"created during job-init verification"}'

curl http://127.0.0.1:8085/api/entries
```

Open:

- `http://127.0.0.1:8084/journal/`

### What the improved step teaches

- Jobs as one-time cluster tasks
- privilege separation between schema management and normal app runtime
- a more maintainable deployment model for stateful applications

Troubleshooting:

- if the Job does not complete, inspect it with `kubectl describe job journal-db-init -n tutorial` and read its logs with `kubectl logs job/journal-db-init -n tutorial`
- if the API fails after the Job completed, verify that the Secret-backed application connection string matches the login created by the initialization script
- if the web UI loads but no data operations work, check the API pod logs rather than the web pod first

---

## 20. RBAC

**RBAC** controls who can do what in Kubernetes.

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
    resources: ["pods", "services", "configmaps", "secrets"]
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

```bash
kubectl apply -f config/05-journal/12-rbac-readonly.yaml
kubectl auth can-i list pods --as=system:serviceaccount:tutorial:tutorial-reader -n tutorial
kubectl auth can-i create deployments --as=system:serviceaccount:tutorial:tutorial-reader -n tutorial
```

---

## 21. Ingress

Ingress is the main HTTP exposure strategy for the core tutorial because it is minikube-friendly and easy to enable with the ingress addon.

File: `config/05-journal/13-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tutorial-ingress
  namespace: tutorial
spec:
  ingressClassName: nginx
  rules:
    - host: tutorial.local
      http:
        paths:
          - path: /genkey
            pathType: Prefix
            backend:
              service:
                name: genkey-web
                port:
                  number: 80
          - path: /journal
            pathType: Prefix
            backend:
              service:
                name: journal-web
                port:
                  number: 80
```

Why this is the main path:

- easy to explain
- easy to enable in minikube
- sufficient for the tutorial’s HTTP routing goals

Apply it:

```bash
kubectl apply -f config/05-journal/13-ingress.yaml
kubectl get ingress -n tutorial
```

Expected `kubectl get ingress` shape:

```text
NAME               CLASS   HOSTS            ADDRESS   PORTS   AGE
tutorial-ingress   nginx   tutorial.local             80      ...
```

### Important note about testing Ingress on minikube

The Ingress resource describes routing rules, but the exact way you reach the ingress controller depends on how minikube exposes it in your environment.

In the live verification pass for this tutorial, the reliable test path was through the ingress controller's **NodePort** with the correct `Host` header.

Get the minikube IP and the controller's HTTP NodePort:

```bash
MINIKUBE_IP=$(minikube ip)
NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
echo "$MINIKUBE_IP"
echo "$NODEPORT"
```

Then test the routes with the expected host header:

```bash
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/genkey/"
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/genkey/api"
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/journal/"
```

Expected response shapes:

- `/genkey/` returns the frontend HTML shell with `<title>GenKey UI</title>`
- `/genkey/api` returns JSON with `algorithm`, `publicKey`, and `privateKey`
- `/journal/` returns the journal frontend HTML shell with `<title>Journal App</title>`

This is the final proof that a single ingress entrypoint can route to multiple backend Services by path.

### What can go wrong

If you instead try something like this:

```bash
curl -H 'Host: tutorial.local' "http://$(minikube ip)/genkey/"
```

you may get a default `404 Not Found` response depending on how the ingress controller is exposed in your local environment.

That does **not** necessarily mean your Ingress object is wrong. It may only mean you are reaching the wrong port or exposure path.

### How to confirm whether Ingress itself is healthy

```bash
kubectl describe ingress tutorial-ingress -n tutorial
kubectl get svc -n ingress-nginx
kubectl get endpoints -n tutorial genkey-web journal-web
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100
```

If the Ingress describes the expected rules and the backend Services have endpoints, the next thing to check is usually **how** you are reaching the ingress controller, not the YAML itself.

Troubleshooting summary:

- `404 Not Found` from nginx can mean you reached the ingress controller on the wrong port, not that the Ingress rule is invalid
- missing endpoints usually means the backend Service selectors do not currently match healthy Pods
- if the ingress controller is not ready, wait for the addon to finish creating the controller Pod before testing routes

---

## 22. Advanced topics: Gateway and alternatives to Ingress

The main tutorial intentionally stays with Ingress. But there are more advanced options worth considering after the core lessons are complete.

See:

- `config/advanced/gateway-options.md`

Summary of options:

### NGINX Gateway Fabric
- Benefits: familiar nginx ecosystem, natural follow-on from Ingress.
- Limitations: extra install and controller setup.

### Envoy Gateway
- Benefits: strong modern Gateway API story, good long-term relevance.
- Limitations: heavier than the basic tutorial path.

### Cilium Gateway API
- Benefits: powerful if you also want to learn deeper networking.
- Limitations: adds a lot of extra surface area.

### Istio Gateway API support
- Benefits: very capable traffic management.
- Limitations: too much overhead for the core minikube tutorial.

### Recommendation

Keep the main tutorial on **Ingress**.

If you later want one advanced Gateway-focused extension, the best first options are:

1. **NGINX Gateway Fabric**
2. **Envoy Gateway**

---

## 23. What is already ready for polish later

This version is meant to have the right **structure** and **teaching contrasts** first.

During the polish phase, the highest-value upgrades will be:

- expected command output gathered from actually running the steps
- stronger explanations after each YAML block
- diagrams or request-flow sketches
- better “what you should observe now” callouts
- screenshots if desired
- deeper explanations of each Kubernetes field where helpful

