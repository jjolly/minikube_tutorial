# Minikube Tutorial: From First Pods to a Reverse-Proxy Stack and Stateful Journal App

This tutorial is a progressive guide to learning Kubernetes on **minikube** running inside **WSL Linux**. It is written for a setup that should be general enough for **Ubuntu** and **openSUSE Leap** inside WSL.

The tutorial intentionally teaches by contrast in a few places:

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
- a small Flask service behind nginx
- a React frontend under `/genkey` with a Flask API at `/genkey/api`
- a C# journal application backed by Microsoft SQL Server with persistent storage
- an Ingress route exposing both `/genkey` and `/journal`

---

## 0. What you are building and why

Minikube gives you a local Kubernetes cluster you can experiment with safely. On WSL, that means you can learn the Kubernetes object model and application deployment flow without renting cloud infrastructure first.

This tutorial introduces Kubernetes in four large parts:

1. **installation and infrastructure**
2. **typical cluster functionality and usage**
3. **cluster usage examples**
4. **advanced cluster usage**

The goal is to show not only how to run things, but also how to reason about why Kubernetes uses these objects and patterns.

---

## 1. Tutorial layout

This section is here to help you find the files used by the tutorial while you work.

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
scripts/
  reset-minikube-tutorial.sh
```

How to use this layout:

- `src/` contains application source code and Docker build inputs.
- `config/` contains Kubernetes manifests used by the tutorial.
- `config/05-journal/step1-startup-init/` contains the first database-init approach.
- `config/05-journal/step2-job-init/` contains the improved database-init approach.
- `scripts/reset-minikube-tutorial.sh` resets tutorial resources. It is intentionally destructive and now requires explicit confirmation of the target context before proceeding.

---

# Part 1. Installation and infrastructure

## 2. Prerequisites

Assume you are starting at a Linux shell prompt and you are not yet sure what is installed, what is configured, or whether minikube is already running. This section is written for that situation.

You should assume only that:

- you can log in as a normal user
- you can use `sudo`
- you are working inside WSL on either Ubuntu or openSUSE Leap

If you already have some of these tools installed, the commands below are still useful because they help you verify what state the machine is in before you begin.

### 2.1 Check what is already installed

Before installing anything, inspect the environment.

```bash
uname -a
cat /etc/os-release
which docker
which kubectl
which minikube
docker --version
kubectl version --client
minikube version
```

What this tells you:

- `uname -a` confirms you are in a Linux environment
- `/etc/os-release` tells you which distribution you are on
- `which ...` checks whether a command is already on your `PATH`
- the `--version` commands confirm whether the installed tools actually run

Some of these commands may fail if the tool is not installed yet. That is fine. At this stage, you are only checking what is already present before installing anything.

### 2.2 Why this tutorial uses Docker as the minikube driver

Minikube can run on top of different drivers and container runtimes. In practice, these are the options people often encounter first when using Kubernetes locally:

- **Docker driver**
  - usually the most straightforward local path when first setting things up
  - familiar if you have seen container workflows before
  - works well in WSL-based development setups
- **Podman driver**
  - viable in some environments
  - attractive if you prefer a daemonless container tool
  - less common in beginner minikube walkthroughs
- **KVM/libvirt or other VM-based drivers**
  - useful on full Linux systems
  - solid, but usually more host setup than is helpful for a first tutorial in WSL
- **none driver / bare-metal style setups**
  - powerful, but usually not the best path when first learning Kubernetes

This tutorial chooses **Docker** because it is usually the least surprising route in a WSL setup.

### 2.3 Why the Docker setup steps matter

You will see these Docker-related steps below:

- install the Docker package
- start the Docker service when needed
- add your user to the `docker` group
- refresh your shell group membership with `newgrp docker`

Why these steps are needed:

- **install Docker** so minikube has a local container runtime/driver to use
- **start the Docker service** so the Docker daemon is actually listening for work
- **add your user to the `docker` group** so you do not have to prefix every Docker command with `sudo`
- **run `newgrp docker`** so your current shell notices the new group membership without forcing a full logout/login cycle

### 2.4 Ubuntu packages

Install the basic tools used throughout the tutorial:

```bash
sudo apt update
sudo apt install -y curl wget tar conntrack socat git ca-certificates
```

Install and configure Docker for this tutorial's minikube workflow:

```bash
sudo apt install -y docker.io
sudo usermod -aG docker "$USER"
newgrp docker
```

After that, verify Docker is usable from your current shell:

```bash
docker --version
docker ps
```

### 2.5 openSUSE Leap packages

Install the basic tools used throughout the tutorial:

```bash
sudo zypper refresh
sudo zypper install -y curl wget tar conntrack-tools socat git ca-certificates
```

Install and configure Docker:

```bash
sudo zypper install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker
```

After that, verify Docker is usable:

```bash
docker --version
docker ps
```

### 2.6 Install kubectl

`kubectl` is the command-line client for the Kubernetes API server.

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

### 2.7 Install minikube

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version
```

### 2.8 Start and verify the cluster

Start minikube with Docker as the driver:

```bash
minikube start --driver=docker
kubectl get nodes
kubectl cluster-info
```

What you should observe:

- `minikube start` should report that the cluster is starting and then running
- `kubectl get nodes` should show a node named `minikube`
- `kubectl cluster-info` should print API and service endpoints

If `kubectl` later appears to be talking to an old or stale minikube endpoint, compare what `kubectl` thinks the current cluster is with what minikube reports:

```bash
kubectl config current-context
kubectl cluster-info
kubectl config view --minify
minikube status
```

If the server address, certificates, or cluster state do not line up with the minikube instance you just started, fix the context with:

```bash
minikube update-context
```

### 2.9 Enable ingress and metrics collection

The tutorial uses two minikube addons early:

```bash
minikube addons enable ingress
minikube addons enable metrics-server
```

Why these addons are enabled:

- **ingress** provides the nginx ingress controller used later in the tutorial
- **metrics-server** provides resource-usage data for commands such as `kubectl top`

## 3. Cluster infrastructure

This section groups together cluster-infrastructure topics that are important for administration, troubleshooting, and understanding how Kubernetes works internally.

### 3.1 kube-apiserver

The **kube-apiserver** is the front door to the cluster. `kubectl`, controllers, and other cluster components all interact with Kubernetes by talking to the API server.

Use commands that reference objects which already exist at this point in the tutorial:

```bash
kubectl api-resources | head -40
kubectl api-versions
kubectl config current-context
kubectl cluster-info
kubectl get nodes -o yaml | head -40
```

What these commands show and why they matter:

- `kubectl api-resources | head -40`
  - lists resource types the API server knows about
- `kubectl api-versions`
  - lists API group and version names exposed by the cluster
- `kubectl config current-context`
  - shows which kubeconfig context `kubectl` is currently using
- `kubectl cluster-info`
  - shows the main control-plane endpoints for the current cluster
- `kubectl get nodes -o yaml | head -40`
  - shows live object data that the API server is serving back right now

### 3.2 Nodes and kubelet

A **node** is a machine that runs workloads. In minikube, you typically have one node. The **kubelet** is the agent on that node that makes sure the assigned containers actually run.

```bash
kubectl get nodes -o wide
kubectl describe node minikube
kubectl get pods -n kube-system -o wide
```

What to notice:

- the node is the machine-level execution target
- the kubelet is the node-local agent that keeps Pod state in sync
- the `kube-system` namespace shows that the cluster itself runs supporting Pods too

### 3.3 etcd

**etcd** is the key-value store that holds cluster state. When you create a namespace, Secret, Deployment, or Service, the desired state is stored through the API server and backed by etcd.

Useful mental model:

```text
your manifest / kubectl command
            |
            v
      kube-apiserver
            |
            v
          etcd
            |
            v
controllers and kubelets react to the stored desired state
```

At this stage, use objects that already exist:

```bash
kubectl get pods -n kube-system
kubectl get namespace default -o yaml
```

What to notice:

- etcd supports the cluster; it is not where your application database lives
- in normal cluster use, you usually see etcd indirectly through the Kubernetes API

### 3.4 metrics-server and `kubectl top`

The `metrics-server` addon collects resource-usage data from the cluster and makes it available through the Kubernetes metrics APIs.

```bash
kubectl get pods -n kube-system
kubectl top nodes
```

Later, after you create workloads in the `tutorial` namespace, `kubectl top pods -n tutorial` becomes more interesting.

---

# Part 2. Typical cluster functionality and usage

## 4. Pods

A **pod** is the smallest deployable unit in Kubernetes.

### 4.1 Run a short-lived BusyBox pod

```bash
kubectl run bb-demo --image=busybox:1.36 --restart=Never --command -- sh -c 'echo hello from kubernetes && sleep 15'
kubectl logs bb-demo
kubectl get pod bb-demo
kubectl delete pod bb-demo
```

### 4.2 Create a long-running pod from YAML

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

Test it from inside the cluster:

```bash
POD_IP=$(kubectl get pod echo-pod -o jsonpath='{.status.podIP}')
kubectl run netshoot-pod-check --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc "curl -fsS http://$POD_IP:5678"
```

Then clean up the standalone Pod before moving on:

```bash
kubectl delete pod echo-pod
```

## 5. Services

Pods are ephemeral. A **Service** gives a stable virtual IP and DNS name that can target one or more matching Pods.

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

Recreate the Pod, then create the Service:

```bash
kubectl apply -f config/01-pods/pod-echo.yaml
kubectl wait --for=condition=Ready pod/echo-pod --timeout=120s
kubectl apply -f config/01-pods/service-echo.yaml
kubectl port-forward service/echo-service 8080:80
```

In a second terminal:

```bash
curl http://127.0.0.1:8080
```

Expected response:

```text
hello from echo-pod
```

## 6. Kubernetes networking

Kubernetes networking is built around a few expectations:

```text
Pod A  --DNS lookup-->  Service name
  |                      |
  |------HTTP/TCP------> Service virtual IP
                         |
                         v
                      backend Pod
```

Test from a temporary shell pod:

```bash
kubectl run netshoot --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc 'nslookup echo-service && curl -fsS http://echo-service'
```

Expected response:

```text
hello from echo-pod
```

## 7. Namespaces

A **namespace** groups resources so you can separate environments and reduce clutter.

File: `config/01-pods/namespace-tutorial.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tutorial
```

Create the namespace and move the echo resources into it:

```bash
kubectl apply -f config/01-pods/namespace-tutorial.yaml
kubectl apply -n tutorial -f config/01-pods/pod-echo.yaml
kubectl apply -n tutorial -f config/01-pods/service-echo.yaml
kubectl get all -n tutorial
```

### 7.1 Contexts and changing the default namespace

```bash
kubectl config current-context
kubectl config view --minify
kubectl config set-context --current --namespace=tutorial
kubectl get pods
kubectl get svc
```

## 8. Labels

**Labels** are key/value pairs attached to objects. Kubernetes uses them heavily for selection.

```bash
kubectl get pods -n tutorial --show-labels
kubectl get pods -n tutorial -l app=echo
```

## 9. Deployments

A **Deployment** manages rollout for a stateless application.

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

Apply it:

```bash
kubectl delete pod -n tutorial echo-pod --ignore-not-found
kubectl apply -n tutorial -f config/01-pods/deployment-echo.yaml
kubectl rollout status deployment/echo-deployment -n tutorial
kubectl scale deployment/echo-deployment -n tutorial --replicas=3
kubectl rollout status deployment/echo-deployment -n tutorial
kubectl get pods -n tutorial -o wide
```

Because the Service still selects `app: echo`, it can target the new Pods without changing the Service definition.

## 10. ConfigMaps

A **ConfigMap** stores non-secret configuration data.

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

ConfigMaps are useful for small files, app settings, and simple tutorial content.

## 11. Persistent Volumes and PersistentVolumeClaims

A **PersistentVolumeClaim** requests durable storage for a workload.

This is worth introducing as a core concept before the database examples, because it demonstrates a central Kubernetes idea: a Pod can go away while the storage survives.

### 11.1 Simple persistence demo

File: `config/01-pods/pvc-demo.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-shared-data
  namespace: tutorial
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pvc-demo
  namespace: tutorial
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pvc-demo
  template:
    metadata:
      labels:
        app: pvc-demo
    spec:
      containers:
        - name: writer
          image: busybox:1.36
          command:
            - /bin/sh
            - -c
            - |
              mkdir -p /data
              if [ ! -f /data/hello.txt ]; then
                echo "hello from pvc-demo" > /data/hello.txt
                date -u +"created %Y-%m-%dT%H:%M:%SZ" >> /data/hello.txt
              fi
              tail -f /dev/null
          volumeMounts:
            - name: shared-data
              mountPath: /data
      volumes:
        - name: shared-data
          persistentVolumeClaim:
            claimName: demo-shared-data
```

Apply it:

```bash
kubectl apply -f config/01-pods/pvc-demo.yaml
kubectl rollout status deployment/pvc-demo -n tutorial
kubectl get pvc -n tutorial
kubectl exec -n tutorial deploy/pvc-demo -- cat /data/hello.txt
```

Delete the Pod and let the Deployment bring up another one:

```bash
kubectl delete pod -n tutorial -l app=pvc-demo
kubectl rollout status deployment/pvc-demo -n tutorial
kubectl exec -n tutorial deploy/pvc-demo -- cat /data/hello.txt
```

What this demonstrates:

- the Pod changed
- the file did not disappear
- the storage survived Pod replacement

That is the core idea you will rely on later when SQL Server stores durable data.

### 11.2 Why this matters later

A PVC is a request, not the storage implementation itself. In minikube, a storage provisioner usually satisfies that request automatically and binds the claim to backing storage for you.

---

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

```bash
kubectl apply -f config/02-static-nginx/static-site.yaml
kubectl port-forward -n tutorial service/static-nginx 8080:80
```

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

Deploy it:

```bash
kubectl apply -f config/03-genkey-basic/genkey-basic.yaml
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

Build the backend and frontend images:

```bash
cd src/04-genkey-full/backend
minikube image build -t genkey-api:0.1.0 .
cd ..
minikube image build -f Dockerfile.frontend -t genkey-web:0.1.0 .
cd ../..
```

Apply the manifests:

```bash
kubectl apply -f config/04-genkey-full/image-based/
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

Apply the Secret, PVC, database Deployment, and database Service first:

```bash
kubectl apply -f config/05-journal/step1-startup-init/00-secret.yaml
kubectl apply -f config/05-journal/step1-startup-init/01-pvc.yaml
kubectl apply -f config/05-journal/step1-startup-init/02-db-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/03-db-service.yaml
```

Wait for SQL Server:

```bash
kubectl get pods -n tutorial -w
kubectl rollout status deployment/journal-db -n tutorial
```

Then apply the API and web resources:

```bash
kubectl apply -f config/05-journal/step1-startup-init/04-api-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/05-api-service.yaml
kubectl apply -f config/05-journal/step1-startup-init/06-web-assets-configmap.yaml
kubectl apply -f config/05-journal/step1-startup-init/07-web-nginx-configmap.yaml
kubectl apply -f config/05-journal/step1-startup-init/08-web-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/09-web-service.yaml
```

Check health:

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

Apply the improved manifests:

```bash
kubectl apply -f config/05-journal/step2-job-init/
kubectl get pods,jobs -n tutorial
kubectl wait --for=condition=complete job/journal-db-init -n tutorial --timeout=600s
kubectl logs -n tutorial job/journal-db-init
```

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

Apply it:

```bash
kubectl apply -f config/05-journal/13-ingress.yaml
kubectl get ingress -n tutorial
```

Get the minikube IP and the ingress controller's NodePort:

```bash
MINIKUBE_IP=$(minikube ip)
NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
echo "$MINIKUBE_IP"
echo "$NODEPORT"
```

Test the routes with the expected host header:

```bash
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/genkey/"
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/genkey/api"
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/journal/"
```

This is the final proof that a single ingress entrypoint can route to multiple backend Services by path.

---

# Part 4. Advanced cluster usage

## 18. Secrets

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

## 19. RBAC

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

## 20. Advanced topics: Gateway and alternatives to Ingress

The main tutorial intentionally stays with Ingress. But there are more advanced options worth considering after the core lessons are complete.

See:

- `config/advanced/gateway-options.md`

Summary of options:

- **NGINX Gateway Fabric**
- **Envoy Gateway**
- **Cilium Gateway API**
- **Istio Gateway API support**

### Recommendation

Keep the main tutorial on **Ingress**.

If you later want one advanced Gateway-focused extension, the best first options are:

1. **NGINX Gateway Fabric**
2. **Envoy Gateway**

## 21. Reset script warning and safe use

The reset helper exists to make repeated tutorial runs easier, but it is intentionally destructive.

File:

- `scripts/reset-minikube-tutorial.sh`

The script now:

- updates the kubectl context for the selected minikube profile
- shows the current kubectl context and cluster info
- lists namespaces before doing anything destructive
- requires you to type the exact current context name
- asks for a final confirmation before deletion begins

That makes it safer to use on a workstation where you might have more than one Kubernetes context configured.

## 22. What is already ready for polish later

This version is meant to have the right **structure**, **teaching contrasts**, and **object ordering** first.

During a later polish phase, the highest-value upgrades will be:

- expected command output gathered from actually running the steps
- screenshots if desired
- stronger diagrams and request-flow sketches
- additional troubleshooting callouts after each multi-step example
- possibly replacing the key-generation demo with a safer interactive Flask example if you decide to do that later
