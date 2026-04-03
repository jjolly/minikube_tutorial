# Part 1. Installation and infrastructure

## 1.1 Installation

### 1.1.1 Prerequisites

Assume you are starting at a Linux shell prompt and you are not yet sure what is installed, what is configured, or whether minikube is already running. This section is written for that situation.

You should assume only that:

- you can log in as a normal user
- you can use `sudo`
- you are working inside WSL on either Ubuntu or openSUSE Leap

If you already have some of these tools installed, the commands below are still useful because they help you verify what state the machine is in before you begin.

### 1.1.2 Check what is already installed

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

If one of these setup or verification commands behaves unexpectedly and you want a more systematic way to diagnose the problem, see the troubleshooting guide in **Part 4, section 4.1**.

### 1.1.3 Why this tutorial uses Docker as the minikube driver

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

### 1.1.4 Why the Docker setup steps matter

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

### 1.1.5 Ubuntu packages

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

### 1.1.6 openSUSE Leap packages

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

### 1.1.7 Install kubectl

`kubectl` is the command-line client for the Kubernetes API server.

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

### 1.1.8 Install minikube

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version
```

If you ever want to reset the tutorial back to a clean cluster state, the simplest supported approach is to delete the entire minikube cluster and recreate it rather than trying to clean up Kubernetes objects one by one.

Use:

```bash
minikube delete
```

What this is for:

- it removes the minikube cluster itself rather than only deleting tutorial workloads
- it is the cleanest way to return to a known starting point
- after doing this, continue from **section 1.1.9** to start the cluster again

### 1.1.9 Start and verify the cluster

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

If one of these checks fails, or if `kubectl` later seems to be talking to the wrong cluster or a stale endpoint, use the troubleshooting guide in **Part 4, section 4.1**.

### 1.1.10 Enable ingress and metrics collection

The tutorial uses two minikube addons early:

```bash
minikube addons enable ingress
minikube addons enable metrics-server
```

Why these addons are enabled:

- **ingress** provides the nginx ingress controller used later in the tutorial
- **metrics-server** provides resource-usage data for commands such as `kubectl top`

If enabling addons fails or they do not appear healthy afterward, the troubleshooting guide in **Part 4, section 4.1** gives a structured way to inspect cluster status, system Pods, events, and addon-related failures.

## 1.2 Infrastructure

### 1.2.1 kube-apiserver

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

### 1.2.2 Nodes and kubelet

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

### 1.2.3 etcd

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

### 1.2.4 metrics-server and `kubectl top`

The `metrics-server` addon collects resource-usage data from the cluster and makes it available through the Kubernetes metrics APIs.

```bash
kubectl get pods -n kube-system
kubectl top nodes
```

Later, after you create workloads in the `tutorial` namespace, `kubectl top pods -n tutorial` becomes more interesting.

---
