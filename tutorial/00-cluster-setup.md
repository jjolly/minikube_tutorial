# Part 0. Cluster Setup

This part gets you running with a local Kubernetes cluster. Choose the option that matches your environment:

- **Option A: Docker Desktop with Kubernetes** - Recommended for most users. Works with Docker Desktop on Windows or macOS. Simple GUI-based setup.
- **Option B: Minikube** - Best for WSL environments without Docker Desktop. Highly flexible with multiple driver options.

Both options use standard `kubectl` commands for the rest of the tutorial, so you can switch between them later if needed.

---

## Option A: Docker Desktop with Kubernetes (Recommended)

Docker Desktop includes built-in Kubernetes support. This is the simplest way to get started if you're using Docker Desktop on Windows or macOS—you don't need to install kind or minikube separately.

### 0.A.1 Prerequisites

You should have:

- Docker Desktop installed (Windows or macOS)
- Administrator access (for enabling Kubernetes)
- At least 4GB of memory allocated to Docker Desktop
- Approximately 4GB of available disk space

### 0.A.2 Install kubectl (if not already installed)

Docker Desktop's Kubernetes usually includes kubectl, but you may want to install it separately for the latest version.

**macOS (using Homebrew):**
```bash
brew install kubectl
kubectl version --client
```

**Windows (using Chocolatey):**
```powershell
choco install kubernetes-cli
kubectl version --client
```

**Manual download (any platform):**
Download from https://kubernetes.io/docs/tasks/tools/

**Check if kubectl is installed:**
```bash
# Windows PowerShell
where kubectl

# macOS/Linux
which kubectl

# Any platform
kubectl version --client
```

### 0.A.3 Enable Kubernetes in Docker Desktop

**Step 1: Open Docker Desktop Settings**

1. Click the Docker Desktop icon in your taskbar/menu bar
2. Click the **Settings** (gear icon)

**Step 2: Enable Kubernetes**

1. In the left sidebar, click **Kubernetes**
2. Check the box **Enable Kubernetes**
3. Click **Apply & Restart**

Docker Desktop will download and start the Kubernetes cluster. This may take several minutes.

**Step 3: Verify Kubernetes is Running**

Once Docker Desktop restarts, you should see "Kubernetes running" in the menu bar.

Open a terminal and verify:

```bash
# Windows PowerShell or macOS Terminal
kubectl get nodes
kubectl cluster-info
```

Expected output:

```
NAME             STATUS   ROLES           AGE   VERSION
docker-desktop   Ready    control-plane   1m    v1.x.x.x
```

What you should observe:

- `kubectl get nodes` should show a node named `docker-desktop`
- `kubectl cluster-info` should print API and service endpoints

### 0.A.4 Enable ingress

Docker Desktop's Kubernetes includes ingress support. Enable the NGINX ingress controller:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
```

Wait for the ingress controller to be ready:

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

Verify the ingress controller is running:

```bash
kubectl get pods -n ingress-nginx
```

### 0.A.5 Enable metrics-server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

You may need to patch metrics-server to work with Docker Desktop's container runtime:

```bash
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

Wait a moment, then verify:

```bash
kubectl top nodes
```

What this does:

- **ingress** provides the nginx ingress controller used later in the tutorial
- **metrics-server** provides resource-usage data for commands such as `kubectl top`

### 0.A.6 Resetting the cluster

If you need to reset Kubernetes in Docker Desktop:

1. Open Docker Desktop Settings
2. Go to **Kubernetes**
3. Click **Reset Kubernetes Cluster**
4. Confirm the reset

After resetting, re-run the ingress and metrics-server steps from **0.A.4** and **0.A.5**.

### 0.A.7 Building container images with Docker Desktop

With Docker Desktop's Kubernetes, images you build with Docker are immediately available to the cluster—no special loading step required.

```bash
docker build -t my-image:tag /path/to/build/context
```

The image is ready to use in Kubernetes deployments immediately.

---

## Option B: Minikube (WSL-focused)

Minikube is an alternative way to run a local Kubernetes cluster. It's especially useful in WSL environments where you don't have Docker Desktop, or when you need more flexibility in drivers and configuration.

### 0.B.1 Prerequisites

Assume you are starting at a Linux shell prompt and you are not yet sure what is installed, what is configured, or whether minikube is already running.

You should assume only that:

- you can log in as a normal user
- you can use `sudo`
- you are working inside WSL on either Ubuntu or openSUSE Leap

### 0.B.2 Check what is already installed

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

### 0.B.3 Why this tutorial uses Docker as the minikube driver

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

### 0.B.4 Docker setup steps

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

### 0.B.5 Ubuntu packages

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

### 0.B.6 openSUSE Leap packages

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

### 0.B.7 Install kubectl

`kubectl` is the command-line client for the Kubernetes API server.

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

### 0.B.8 Install minikube

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version
```

### 0.B.9 Start and verify the cluster

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

### 0.B.10 Enable ingress and metrics collection

The tutorial uses two minikube addons early:

```bash
minikube addons enable ingress
minikube addons enable metrics-server
```

Why these addons are enabled:

- **ingress** provides the nginx ingress controller used later in the tutorial
- **metrics-server** provides resource-usage data for commands such as `kubectl top`

### 0.B.11 Resetting the cluster

If you ever want to reset the tutorial back to a clean cluster state:

```bash
minikube delete
minikube start --driver=docker
```

After doing this, continue from **section 0.B.10** to re-enable addons.

### 0.B.12 Minikube profiles (optional)

Minikube can manage more than one local cluster by using **profiles**. A profile is essentially a named minikube cluster instance.

Why this can be useful:

- one profile for tutorial experiments
- another profile for unrelated application work
- a clean profile for testing from scratch without disturbing an existing cluster

```bash
minikube profile list
minikube start -p tutorial-lab --driver=docker
minikube status -p tutorial-lab
minikube delete -p tutorial-lab
```

Important idea:

- a **profile** is broader than a Kubernetes namespace
- **namespaces** separate resources *inside one cluster*
- **profiles** separate entire local minikube clusters

### 0.B.13 Multi-node minikube clusters (optional)

The main tutorial uses a single-node minikube cluster, but minikube can also create a **multi-node** cluster.

```bash
minikube start -p multinode-lab --driver=docker --nodes 2
kubectl config use-context multinode-lab
kubectl get nodes -o wide
```

What to observe:

- more than one node listed in `kubectl get nodes`
- system Pods distributed across nodes

Clean up when done:

```bash
minikube delete -p multinode-lab
```

### 0.B.14 Minikube addons worth exploring

Once you are comfortable with the basics, minikube addons are one of the easiest ways to keep experimenting. An addon is a prepackaged cluster feature that minikube knows how to enable and disable for you.

```bash
minikube addons list
```

Two important addons have already been used in this tutorial:

- `ingress` - enabled in **section 0.B.10**
- `metrics-server` - enabled in **section 0.B.10**

Additional addons to explore:

1. **dashboard** - provides the Kubernetes Dashboard web UI
   ```bash
   minikube addons enable dashboard
   minikube dashboard
   ```

2. **storage-provisioner** - provides dynamic storage provisioning for local PersistentVolumeClaims
   ```bash
   minikube addons enable storage-provisioner
   ```

3. **default-storageclass** - marks a storage class as the default choice for PVCs
   ```bash
   minikube addons enable default-storageclass
   ```

4. **registry** - provides an in-cluster container registry endpoint
   ```bash
   minikube addons enable registry
   ```

5. **metallb** - provides a software load-balancer for `LoadBalancer` Services
   ```bash
   minikube addons enable metallb
   ```

Enable an addon:
```bash
minikube addons enable <addon-name>
```

Disable an addon:
```bash
minikube addons disable <addon-name>
```

### 0.B.15 Building container images with minikube

Minikube provides a convenient command for building images directly into the minikube image registry:

```bash
minikube image build -t my-image:tag /path/to/build/context
```

This is covered in more detail in the cluster usage examples section.

---

## Image Building Summary

When you reach the sections that require building container images, the approach differs:

**Docker Desktop (Option A):**
```bash
docker build -t my-image:tag /path/to/build/context
# Image is immediately available - no extra step needed
```

**Minikube (Option B):**
```bash
minikube image build -t my-image:tag /path/to/build/context
```

Both approaches get your custom images into the cluster so Kubernetes can use them.

---

## Next Steps

Once your cluster is running and you've verified connectivity:

Continue to **[Part 1. Infrastructure and kubectl](01-infrastructure-and-kubectl.md)** to learn about the Kubernetes control plane, nodes, and core cluster services.

The rest of the tutorial uses standard `kubectl` commands that work identically on both Docker Desktop and minikube clusters.
