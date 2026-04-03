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

A **node** is a machine that Kubernetes can use to run work. In minikube, you usually have one node named `minikube`.

The **kubelet** is the Kubernetes agent running on that node. Its job is to make sure the things Kubernetes asked to run on that machine are actually started and kept in the expected state.

At this point in the tutorial, some of the terminology in the command output may still be new. That is okay. The goal here is to start recognizing what the cluster reports about itself. Later sections will explain these ideas in more detail when you begin creating and managing your own application objects.

```bash
kubectl get nodes -o wide
kubectl describe node minikube
kubectl get pods -n kube-system -o wide
```

What these commands are showing:

- `kubectl get nodes -o wide`
  - lists the machines Kubernetes currently knows about
  - in this tutorial, that is usually just one row for `minikube`
  - the `-o wide` form adds extra columns such as internal IP address, operating system, kernel version, and container runtime
- `kubectl describe node minikube`
  - prints a much more detailed report about that one node
  - useful for seeing labels, resource capacity, health conditions, and recent node-related events
- `kubectl get pods -n kube-system -o wide`
  - lists the cluster's own supporting components that are running in the `kube-system` namespace
  - this is useful because it shows that Kubernetes is not just managing your future applications; it is also running internal cluster services

Brief terminology guide for this section:

- **node**
  - a machine Kubernetes can run things on
  - in minikube, this is usually the single cluster machine
- **Pod**
  - a running unit of work in Kubernetes
  - Pods are explained properly later; for now, think of them as the basic things Kubernetes starts and manages
- **namespace**
  - a way Kubernetes groups related objects
  - `kube-system` is the namespace commonly used for built-in cluster components
- **container runtime**
  - the software on the node that actually runs containers
  - in this tutorial, that is typically Docker through minikube's setup
- **conditions**
  - status checks Kubernetes records about a node, such as whether it is ready to run work
- **events**
  - recent messages Kubernetes recorded about something that happened, such as successful startup or a failure

What to notice on a first read:

- the node is the machine-level execution target for the cluster
- the kubelet is the node-local agent responsible for keeping that machine aligned with Kubernetes expectations
- `kubectl describe node` gives a much richer operational view than `kubectl get nodes`
- the `kube-system` namespace shows that the cluster itself runs supporting Pods too

You do not need to memorize all of this output yet. For now, the important idea is simply that Kubernetes can report both:

1. **machine-level information** about the node
2. **cluster-service information** about the internal components running on it

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

If you are coming from Docker, a useful first mental model is:

- a **container image** is the packaged application filesystem and startup definition
- a **container** is a running instance created from that image
- a **Pod** is the Kubernetes object that tells the cluster to run one or more containers together

In many beginner examples, a Pod runs just one container, so it is tempting to think of a Pod and a container as the same thing. They are related, but not identical:

- the **image** is what gets run
- the **container** is the running process instance created from the image
- the **Pod** is the Kubernetes wrapper that gives that running container a place in the cluster's scheduling, networking, and lifecycle model

That distinction becomes more important later, but it is worth naming now.

### 4.1 Run a short-lived BusyBox pod

This first Pod is meant to be temporary and easy to inspect.

The image used here is `busybox:1.36`, which is a very small Linux userspace image often used for demonstrations, debugging, and simple shell commands.

Before you run the command, one small timing note matters:

- the Pod's shell command will print a message immediately
- then it will **sleep for 15 seconds**
- during that sleep time, the Pod still exists and can be inspected
- after the sleep ends, the shell command exits and the Pod's main work is finished

That pause is intentional. It gives you a short window to look at the Pod while it is alive.

Create the Pod:

```bash
kubectl run bb-demo --image=busybox:1.36 --restart=Never --command -- sh -c 'echo hello from kubernetes && sleep 15'
```

What this command means:

- `kubectl run bb-demo`
  - asks Kubernetes to create a Pod named `bb-demo`
- `--image=busybox:1.36`
  - tells Kubernetes which container image to start inside that Pod
- `--restart=Never`
  - tells Kubernetes to create a plain Pod for this one-off example rather than a higher-level controller
- `--command -- sh -c 'echo hello from kubernetes && sleep 15'`
  - overrides the container startup command so it runs a shell
  - the shell prints a message and then waits 15 seconds before exiting

What happens after you press Enter:

1. Kubernetes accepts the request to create the Pod
2. the node pulls the image if it is not already present
3. the container starts and runs the shell command
4. the command prints its message
5. the command sleeps for 15 seconds, giving you time to inspect the Pod
6. the shell exits, so the Pod's main task is complete

One subtle but important Kubernetes detail: when that short-lived command finishes, Kubernetes does not instantly forget the Pod. The Pod object usually remains in the cluster until you delete it, and Kubernetes records status information about how it finished. That means you can still inspect it after the 15-second sleep has ended and see that it ran and exited rather than simply vanishing.

Read the Pod's logs:

```bash
kubectl logs bb-demo
```

What this shows:

- the text written by the command running inside the container
- in this example, that should be the `hello from kubernetes` output

Check the Pod status:

```bash
kubectl get pod bb-demo
```

What to look for:

- if you run this while the `sleep 15` is still in progress, the Pod may show as `Running`
- if you run it after the sleep ends, it may show as `Completed`
- even in the `Completed` state, Kubernetes is still keeping the Pod object and its exit details around until you delete it

That timing difference is useful. It shows that a Pod can exist for a short task, not only for long-running servers, and that Kubernetes keeps status information about the finished Pod for later inspection.

Clean up the Pod:

```bash
kubectl delete pod bb-demo
```

Why delete it if it may already be finished?

Because a finished Pod can still remain as a cluster object until you remove it. Deleting it keeps the tutorial environment tidy before moving on.

### 4.2 Create a long-running pod from YAML

The previous example created a short-lived Pod directly from the command line. This next example moves to a more typical Kubernetes workflow: define the Pod in YAML, apply it, and inspect the object Kubernetes creates.

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

Apply the manifest:

```bash
kubectl apply -f config/01-pods/pod-echo.yaml
```

What just happened:

- Kubernetes received the Pod definition from the YAML file
- it created a Pod object named `echo-pod`
- the node then started a container from the `hashicorp/http-echo:1.0.0` image
- that container runs a tiny HTTP server which replies with the text you supplied in `args`

List the Pods:

```bash
kubectl get pods -o wide
```

Why this is a separate step:

- it lets you see whether the Pod is still starting or already running
- the `-o wide` output also shows extra details such as the Pod IP and the node it landed on

Describe the Pod in detail:

```bash
kubectl describe pod echo-pod
```

Why this is useful:

- `describe` gives much more detail than `get`
- it is one of the first commands to use when a Pod does not behave the way you expect
- the `Events` section near the bottom is especially useful for startup and scheduling problems

Test the Pod from inside the cluster:

```bash
POD_IP=$(kubectl get pod echo-pod -o jsonpath='{.status.podIP}')
kubectl run netshoot-pod-check --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc "curl -fsS http://$POD_IP:5678"
```

Why this is written as two commands:

- the first command asks Kubernetes for the Pod's current internal IP address
- the second command starts a temporary helper Pod and uses it to send an HTTP request to that IP from inside the cluster network

Expected response:

```text
hello from echo-pod
```

Then clean up the standalone Pod before moving on:

```bash
kubectl delete pod echo-pod
```

That cleanup is intentional because the next sections rebuild the same idea using Services and then Deployments.

## 5. Services

Pods are ephemeral. A **Service** gives a stable virtual IP and DNS name that can target one or more matching Pods.

This is one of the biggest practical differences between "a thing is running" and "other things can reliably find it." A Pod may disappear and come back with a different IP. A Service gives clients a steadier way to reach the backend.

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

Recreate the Pod first:

```bash
kubectl apply -f config/01-pods/pod-echo.yaml
kubectl wait --for=condition=Ready pod/echo-pod --timeout=120s
```

Why these two commands are separate:

- the first recreates the backend Pod that the Service will point at
- the second waits until the Pod is actually ready, so you do not race ahead while it is still starting

Create the Service:

```bash
kubectl apply -f config/01-pods/service-echo.yaml
```

What just happened:

- Kubernetes created a Service named `echo-service`
- that Service looks for Pods with the label `app: echo`
- because `echo-pod` has that label, the Service can send traffic to it

Forward the Service port to your local machine:

```bash
kubectl port-forward service/echo-service 8080:80
```

Important timing note:

- this command keeps running in the foreground
- leave it open in that terminal while you test from a second terminal or browser

In a second terminal:

```bash
curl http://127.0.0.1:8080
```

Expected response:

```text
hello from echo-pod
```

That response now comes through the Service rather than from manually targeting the Pod IP.

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

This section demonstrates the idea that workloads inside the cluster usually talk to each other through Service names, not by discovering individual Pod IP addresses by hand.

Start a temporary helper Pod and test DNS plus HTTP in one shot:

```bash
kubectl run netshoot --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc 'nslookup echo-service && curl -fsS http://echo-service'
```

What this command is doing:

- it creates a temporary Pod from the `nicolaka/netshoot` image
- inside that Pod, it first asks cluster DNS to resolve `echo-service`
- then it uses `curl` to send an HTTP request to the Service by name
- `--rm` removes the helper Pod when the command finishes

Expected response:

```text
hello from echo-pod
```

The important idea is that cluster-internal name resolution is now doing work for you.

## 7. Namespaces

A **namespace** groups resources so you can separate environments and reduce clutter.

File: `config/01-pods/namespace-tutorial.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tutorial
```

Create the namespace:

```bash
kubectl apply -f config/01-pods/namespace-tutorial.yaml
```

Move the echo resources into it:

```bash
kubectl apply -n tutorial -f config/01-pods/pod-echo.yaml
kubectl apply -n tutorial -f config/01-pods/service-echo.yaml
```

Inspect what now exists in that namespace:

```bash
kubectl get all -n tutorial
```

Why these steps are split up:

- first you create the namespace itself
- then you create objects inside it
- finally you inspect only that namespace so the output stays focused on tutorial resources

### 7.1 Contexts and changing the default namespace

Check the current context information:

```bash
kubectl config current-context
kubectl config view --minify
```

What these commands show:

- the first prints the name of the currently selected kubeconfig context
- the second shows the currently active cluster, user, and namespace settings in a smaller view

Set the current context to default to the `tutorial` namespace:

```bash
kubectl config set-context --current --namespace=tutorial
```

Verify the effect:

```bash
kubectl get pods
kubectl get svc
```

At this point, those commands should use `tutorial` by default.

## 8. Labels

**Labels** are key/value pairs attached to objects. Kubernetes uses them heavily for selection.

Show Pod labels directly:

```bash
kubectl get pods -n tutorial --show-labels
```

Filter by one specific label:

```bash
kubectl get pods -n tutorial -l app=echo
```

Why this matters:

- the first command shows which labels are present
- the second command shows how Kubernetes can use labels to find matching objects
- later, Services and Deployments rely on this same idea

## 9. Deployments

A **Deployment** manages rollout for a stateless application.

A standalone Pod is useful for learning, but it is not the usual way to keep an application running. A Deployment describes the desired state for a replaceable set of Pods and lets Kubernetes maintain that state for you.

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

Remove the earlier standalone Pod:

```bash
kubectl delete pod -n tutorial echo-pod --ignore-not-found
```

Why do this first?

Because the goal now is to let the Deployment manage the backend Pods instead of leaving the original manually created Pod around.

Apply the Deployment and wait for rollout:

```bash
kubectl apply -n tutorial -f config/01-pods/deployment-echo.yaml
kubectl rollout status deployment/echo-deployment -n tutorial
```

What these commands do:

- the first creates the Deployment object
- the second waits while Kubernetes creates the managed Pods and reports when the rollout is complete

Scale the Deployment to three replicas:

```bash
kubectl scale deployment/echo-deployment -n tutorial --replicas=3
kubectl rollout status deployment/echo-deployment -n tutorial
```

Why these are separate again:

- `scale` changes the desired number of replicas
- `rollout status` lets you watch Kubernetes converge toward that new desired state

Inspect the resulting Pods:

```bash
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
