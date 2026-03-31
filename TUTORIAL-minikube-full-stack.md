# Minikube Tutorial: From Single Pods to a Reverse-Proxy Front End and a Stateful Journal App

This is a progressive, hands-on tutorial for running Kubernetes locally with **minikube** inside **WSL Linux**. It is written to be general enough for **Ubuntu** and **openSUSE Leap** users running in WSL, and it starts from installation and ends with a realistic multi-service stack:

- a simple pod
- a static site served by nginx
- a Python `/genkey` service behind nginx
- a more complete React + Flask application under `/genkey` and `/genkey/api`
- a C# journal application backed by **Microsoft SQL Server** with **persistent storage**

Along the way, the tutorial introduces Kubernetes concepts in this order:

1. Pods
2. Services
3. Kubernetes networking
4. Namespaces
5. Labels
6. Deployments
7. The kube-apiserver
8. Nodes and kubelet
9. etcd
10. ConfigMaps
11. Secrets
12. Persistent Volumes
13. Ingress and the Gateway API
14. RBAC

Everything is stored in this repository so you can inspect and refine it:

- `src/` — application source code and static assets
- `config/` — Kubernetes manifests and related config files

## 0. What you are building and why

Minikube is a local Kubernetes distribution that runs a single-node cluster on your machine. In WSL, it is a practical way to learn Kubernetes without renting cloud infrastructure.

By the end of this guide you will understand how Kubernetes pieces fit together:

- **Pods** run containers.
- **Services** provide stable network identities.
- **Namespaces** separate environments and concerns.
- **Labels** let Kubernetes group and select objects.
- **Deployments** manage rollout and self-healing for stateless workloads.
- **ConfigMaps** and **Secrets** externalize configuration.
- **Persistent Volumes** keep data alive beyond a pod restart.
- **Ingress** and **Gateway API** expose HTTP routes cleanly.
- **RBAC** controls what identities can do.

You will also touch the control plane pieces that make Kubernetes work:

- **kube-apiserver** — the front door to the cluster
- **etcd** — the cluster database
- **kubelet** — the agent running on each node
- **node** — the machine hosting workloads

## 1. Prerequisites

You already have minikube working, which is excellent. For completeness, this section documents a clean install path on WSL.

### Why WSL-specific guidance matters

Minikube can use different drivers and runtimes. In WSL, the easiest path is usually Docker or Podman if they are already available in your WSL instance. The exact package names differ between Ubuntu and openSUSE Leap, but the Kubernetes workflow is the same.

### 1.1 Install required tools on Ubuntu

```bash
sudo apt update
sudo apt install -y curl wget tar conntrack socat git ca-certificates
```

If you plan to use Docker as the minikube driver:

```bash
sudo apt install -y docker.io
sudo usermod -aG docker "$USER"
newgrp docker
```

### 1.2 Install required tools on openSUSE Leap

```bash
sudo zypper refresh
sudo zypper install -y curl wget tar conntrack-tools socat git ca-certificates
```

If you plan to use Docker:

```bash
sudo zypper install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker
```

### 1.3 Install kubectl

Why: `kubectl` is the main command-line client for talking to the Kubernetes API server.

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

### 1.4 Install minikube

Why: minikube creates and manages a local Kubernetes cluster.

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version
```

### 1.5 Start minikube

```bash
minikube start --driver=docker
kubectl get nodes
kubectl cluster-info
```

### 1.6 Enable useful add-ons

```bash
minikube addons enable ingress
minikube addons enable metrics-server
```

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
```

## 3. Pods

A **pod** is the smallest deployable unit in Kubernetes. Usually one application container runs in one pod.

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

Apply it:

```bash
kubectl apply -f config/01-pods/pod-echo.yaml
kubectl get pods -o wide
kubectl describe pod echo-pod
```

## 4. Services

Pods are ephemeral. A **Service** gives a stable virtual IP and DNS name for reaching a group of pods.

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

```bash
kubectl apply -f config/01-pods/service-echo.yaml
kubectl port-forward service/echo-service 8080:80
curl http://127.0.0.1:8080
```

## 5. Kubernetes networking

Networking basics:

- every pod gets an IP
- pods can reach other pods directly
- Services provide stable addresses
- DNS is built in

```bash
kubectl run netshoot --image=nicolaka/netshoot:latest -it --rm -- sh
nslookup echo-service
curl http://echo-service
```

## 6. Namespaces

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

## 7. Labels

Labels are key/value pairs used for selection and organization.

```bash
kubectl get pods -n tutorial --show-labels
kubectl get pods -n tutorial -l app=echo
```

## 8. Deployments

A **Deployment** manages stateless application rollout.

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

```bash
kubectl delete pod -n tutorial echo-pod --ignore-not-found
kubectl apply -n tutorial -f config/01-pods/deployment-echo.yaml
kubectl scale deployment/echo-deployment -n tutorial --replicas=3
```

## 9. kube-apiserver

The **kube-apiserver** is the cluster front door. `kubectl` talks to it.

```bash
kubectl api-resources | head -40
kubectl api-versions
kubectl config current-context
kubectl cluster-info
kubectl get deployment echo-deployment -n tutorial -o yaml
```

## 10. Nodes and kubelet

A **node** is a worker machine. The **kubelet** is the agent on that node.

```bash
kubectl get nodes -o wide
kubectl describe node minikube
kubectl get pods -n kube-system -o wide
```

## 11. etcd

**etcd** is the backing data store for Kubernetes state.

```bash
kubectl get pods -n kube-system
```

Look for an `etcd-*` pod in the control plane.

## 12. Static web page with nginx

File: `src/02-nginx-static/index.html`

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Minikube Tutorial - Static Site</title>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      body { font-family: sans-serif; margin: 2rem; background: #f7f7f7; color: #222; }
      main { max-width: 48rem; margin: 0 auto; background: white; padding: 2rem; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); }
    </style>
  </head>
  <body>
    <main>
      <h1>nginx is serving this page from Kubernetes</h1>
      <p>This static site is mounted from a ConfigMap in the tutorial namespace.</p>
    </main>
  </body>
</html>
```

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

```bash
kubectl apply -f config/02-static-nginx/static-site.yaml
kubectl port-forward -n tutorial service/static-nginx 8080:80
```

## 13. ConfigMaps

A **ConfigMap** stores non-secret configuration. The static site above is your first example.

```bash
kubectl get configmap static-site-content -n tutorial -o yaml
```

## 14. Simple Python `/genkey` service behind nginx

Architecture:

- `genkey-basic-api` — Flask app serving `/genkey`
- `genkey-basic-proxy` — nginx reverse proxy

Build the image into minikube:

```bash
cd src/03-genkey-basic
minikube image build -t genkey-basic-api:0.1.0 .
cd ../..
```

Apply:

```bash
kubectl apply -f config/03-genkey-basic/genkey-basic.yaml
kubectl port-forward -n tutorial service/genkey-basic-proxy 8081:80
curl http://127.0.0.1:8081/genkey
```

## 15. Secrets

A **Secret** stores sensitive configuration such as passwords.

For the runnable journal stack, the Secret now stores both the SQL Server SA password and the application connection string so the API deployment does not hard-code credentials in its manifest.

Example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mssql-secret
  namespace: tutorial
type: Opaque
stringData:
  SA_PASSWORD: "YourStrong!Passw0rd"
  JOURNALDB_CONNECTION_STRING: "Server=journal-db,1433;Database=JournalDb;User Id=sa;Password=YourStrong!Passw0rd;TrustServerCertificate=True;Encrypt=False"
```

## 16. More complete app: React front end + Flask API under nginx

This version serves a real React front end under `/genkey` and proxies `/genkey/api` to Flask. Unlike the earlier ConfigMap-based static examples, this stage now packages the React app into its own local image so the deployed workload matches the source tree.

Build the front end image and backend image directly into minikube:

```bash
cd src/04-genkey-full/backend
minikube image build -t genkey-api:0.1.0 .
cd ..
minikube image build -f Dockerfile.frontend -t genkey-web:0.1.0 .
cd ../..
```

Apply:

```bash
kubectl apply -f config/04-genkey-full/genkey-full.yaml
kubectl port-forward -n tutorial service/genkey-web 8082:80
```

Open `http://127.0.0.1:8082/genkey/`.

## 17. Persistent Volumes

A **PersistentVolumeClaim** lets state survive pod restarts.

File: `config/05-journal/storage.yaml`

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

## 18. C# journal application step by step

Architecture:

- `journal-web` — frontend served by nginx
- `journal-api` — ASP.NET Core API
- `journal-db` — SQL Server using a PVC

Build the API image:

```bash
cd src/05-journal/api
minikube image build -t journal-api:0.1.0 .
cd ../../..
```

Apply the stack:

```bash
kubectl apply -f config/05-journal/journal-stack.yaml
kubectl port-forward -n tutorial service/journal-web 8083:80
```

Open `http://127.0.0.1:8083/journal/`.

The journal stack now includes a Kubernetes **Job** called `journal-db-init` that waits for SQL Server and then applies the schema automatically. That removes the old manual `sqlcmd` step and makes the stack much more repeatable.

After applying the manifest, check the init job and then the rest of the stack:

```bash
kubectl apply -f config/05-journal/journal-stack.yaml
kubectl get pods,jobs -n tutorial
kubectl logs -n tutorial job/journal-db-init
kubectl port-forward -n tutorial service/journal-web 8083:80
```

## 19. Ingress

File: `config/05-journal/ingress.yaml`

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

## 20. Gateway API

For now, treat Gateway API as an **optional next step** rather than part of the base runnable path. In minikube, Ingress is the simpler route because the ingress add-on is easy to enable and test.

The file `config/05-journal/gateway-api.yaml` is now just a note explaining that you must first choose and install a real Gateway controller before those resources will work.

That means the practical runnable path for this tutorial is:

1. use `port-forward` while building each stage
2. use **Ingress** once both apps are working
3. add **Gateway API** only after you intentionally pick a controller

## 21. RBAC

File: `config/05-journal/rbac-readonly.yaml`

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

Test it:

```bash
kubectl apply -f config/05-journal/rbac-readonly.yaml
kubectl auth can-i list pods --as=system:serviceaccount:tutorial:tutorial-reader -n tutorial
kubectl auth can-i create deployments --as=system:serviceaccount:tutorial:tutorial-reader -n tutorial
```

## 22. What is now runnable vs still optional

Runnable now:

- namespace, pod, service, and deployment examples
- static nginx site via ConfigMap
- basic Flask `/genkey` API behind nginx
- React + Flask `/genkey` app structure
- journal stack with PVC, Secret-backed connection string, and automatic DB-init Job
- Ingress-based HTTP entry point

Still optional / not yet fully operational by default:

- Gateway API, until you install a concrete controller
- production-grade hardening such as resource limits, network policies, TLS, and non-dev database credentials

## 23. Suggested next refinements

This draft is structurally complete, but the next improvements I’d make are:

- split large manifest bundles into smaller files per object
- add screenshots and expected command output
- add health checks, resource requests, and limits everywhere
- replace inline ConfigMap UI assets with built container images
- move the journal DB password fully to Secrets for the API too
- add a Job or init workflow for SQL schema setup
- swap the placeholder GatewayClass/controller with a concrete minikube-friendly controller
