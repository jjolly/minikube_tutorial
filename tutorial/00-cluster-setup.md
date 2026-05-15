# Part 0. Cluster Setup

This part gets you running with a local Kubernetes cluster.

This tutorial is written for Docker Desktop with Kubernetes. The core Kubernetes concepts you learn here apply universally—the control plane, scheduler, object model, and API work the same way in any Kubernetes environment. However, specific setup steps, particularly around image handling and cluster configuration, are unique to Docker Desktop and will be explicitly noted when they differ from the base Kubernetes behavior.

---

## Setting up Docker Desktop with Kubernetes

Docker Desktop includes built-in Kubernetes support. This is the simplest way to get started if you're using Docker Desktop on Windows or macOS.

### 0.1 Prerequisites

You should have:

- Docker Desktop installed (Windows or macOS)
- Administrator access (for enabling Kubernetes)
- At least 4GB of memory allocated to Docker Desktop
- Approximately 4GB of available disk space

### 0.2 Install kubectl (if not already installed)

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

### 0.3 Enable Kubernetes in Docker Desktop

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

### 0.4 Installing Extras

When you enabled Kubernetes in Docker Desktop, you got a working control plane, a single node, and the core Kubernetes components needed to run basic workloads. But you didn't get everything. Kubernetes is deliberately minimal out of the box—cluster operators add only the features they need. This keeps the base system small and secure, but it means some useful capabilities aren't available by default.

Docker Desktop's Kubernetes is missing at least two important features that this tutorial relies on:

1. **Ingress** - for HTTP routing to multiple applications on the same host
2. **Metrics API** - for seeing actual resource usage with `kubectl top`

These features aren't included because they're optional. Some clusters don't need them, and there are multiple valid implementations to choose from. Instead of bundling every possible feature, Kubernetes expects you to add what you need.

#### How features are added to Kubernetes

Features in Kubernetes are typically added by applying manifests—YAML files that describe the desired state of your cluster. A single feature often requires multiple Kubernetes objects working together: Namespaces, ServiceAccounts, Roles, ConfigMaps, Deployments, Services, and more. These objects must be created in the right order with the right configuration, or the feature won't work.

This is where **bundled manifests** become useful. Instead of manually creating each object one by one, you can apply a single YAML file that contains everything needed for a feature. The manifest authors have already figured out the correct order, configuration, and relationships between objects. You just apply it and Kubernetes makes it happen.

Think of a bundled manifest like a furniture kit from IKEA: someone else has already figured out which screws go where and included all the parts. You just follow the instructions (apply the manifest) and trust that the pieces fit together.

Both of these features will show up as new Pods running in your cluster. You'll be able to see them with `kubectl get pods --all-namespaces`, and they'll be serving traffic or collecting data shortly after you apply them. The tutorial will explain what these components actually do and how to use them when the time comes. For now, focus on understanding how they're installed and what happens during that process.

---

#### 0.4.1 Enable ingress

By default, Kubernetes provides a way to route traffic within your cluster using **Services**, but Services have limitations when you want to expose multiple HTTP applications on the same port or host. That's where **Ingress** comes in.

Ingress is a Kubernetes API object that manages external access to Services, typically HTTP. Ingress can provide load balancing, SSL termination, and name-based virtual hosting. Think of it as a smart reverse proxy that sits in front of your Services and routes incoming requests based on rules you define.

Docker Desktop's Kubernetes doesn't include an ingress controller by default, so we'll install the NGINX Ingress Controller. This is a popular choice that implements the Ingress API using NGINX as a reverse proxy.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
```

What just happened:

- `kubectl apply` submitted a manifest to the Kubernetes API server describing several related objects: a Namespace, ServiceAccounts, Roles, RoleBindings, ConfigMaps, a Deployment, and a Service
- The API server stored these objects in etcd and acknowledged the request
- The cluster controllers noticed the new objects and began working to make the desired state a reality:
  - The Deployment controller created a ReplicaSet
  - The ReplicaSet created Pods
  - The Scheduler assigned those Pods to nodes
  - The Kubelet on each node instructed the container runtime to start the ingress controller containers

This process doesn't happen instantly. The ingress controller image must be pulled, the container must start, and it must pass its readiness probes before it can handle traffic.

Wait for the ingress controller to become ready:

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

What this command does:

- `kubectl wait` blocks until the condition you specified is met or the timeout expires
- `--namespace ingress-nginx` targets only the ingress-nginx namespace where we installed the controller
- `--for=condition=ready pod` waits for Pods to report as "Ready"
- `--selector=app.kubernetes.io/component=controller` filters to only the ingress controller Pods
- `--timeout=90s` gives Kubernetes up to 90 seconds before giving up

Why waiting matters:

The ingress controller Pod goes through several phases after being created:
1. **Pending**: The Pod is accepted but not yet scheduled to a node
2. **ContainerCreating**: The image is being pulled and the container is starting
3. **Running**: The container is running, but not yet ready to serve traffic
4. **Ready**: The container passed its readiness probe and can handle requests

Using `kubectl wait` ensures you don't try to use the ingress controller before it's actually ready.

Verify the ingress controller is running:

```bash
kubectl get pods -n ingress-nginx
```

You should see a Pod with a name like `ingress-nginx-controller-xxxxx` in the `Ready` state.

What you can now do with ingress:

Later in the tutorial, you'll create an Ingress object that defines routing rules like "send requests for `/genkey/*` to the genkey Service" and "send requests for `/journal/*` to the journal Service." The ingress controller reads these rules from the Kubernetes API and reconfigures its NGINX reverse proxy accordingly, all without you needing to manually configure NGINX.

---

#### 0.4.2 Enable metrics-server

Kubernetes can tell you the **resource requests** and **limits** you've set for your workloads—how much CPU and memory you've asked for or capped. But it doesn't inherently know how much CPU and memory your workloads are actually **using**. That's where **metrics-server** comes in.

metrics-server is a cluster-wide aggregator of resource usage data. It collects metrics from the Kubelet on each node (which gets them from the cgroups that the container runtime uses) and exposes them through the Kubernetes Metrics API. Tools like `kubectl top` and the horizontal pod autoscaler depend on this data.

Without metrics-server, running `kubectl top nodes` will return an error: "Metrics API not available." With metrics-server installed, you can see actual resource consumption and make informed decisions about scaling and capacity planning.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

What just happened:

- Similar to ingress, we applied a manifest that creates the metrics-server components
- A Deployment was created that runs the metrics-server Pod
- This Pod runs a small Go program that continuously:
  - Scrapes the Kubelet on each node for CPU and memory usage
  - Caches this data in memory
  - Serves it via the Metrics API

You may need to patch metrics-server to work with Docker Desktop's container runtime:

```bash
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

Why this patch is sometimes needed:

metrics-server connects to each Kubelet over HTTPS to fetch metrics. In some cluster configurations, including Docker Desktop's Kubernetes, the Kubelet serves a self-signed TLS certificate. The `--kubelet-insecure-tls` flag tells metrics-server to accept these certificates without full validation. This isn't recommended for production, but it's acceptable for a local learning environment.

Wait a moment, then verify:

```bash
kubectl top nodes
```

What you're waiting for:

After applying the metrics-server manifest, several things need to happen before `kubectl top` works:

1. The metrics-server Pod must be scheduled and started
2. It must begin scraping metrics from the Kubelet
3. The Metrics API must be registered and serving data
4. The `kubectl top` command must be able to query that API successfully

If you run `kubectl top nodes` immediately and see "Metrics API not available," it means one of these steps hasn't completed yet. Waiting 15-30 seconds is usually enough for metrics-server to start collecting and serving data. You can also watch the Pod startup with:

```bash
kubectl get pods -n kube-system -l k8s-app=metrics-server -w
```

Wait until the Pod shows as `Running` and `Ready` (usually 2/2), then try `kubectl top nodes` again.

What you should see:

```
NAME             CPU(cores)   MEMORY(bytes)
docker-desktop   123m         1234567K
```

This shows real-time CPU and memory usage for your node. The `m` suffix means "millicores" (thousandths of a CPU core), and `K` means kilobytes. Later, when you have application Pods running, `kubectl top pods -n <namespace>` will show resource usage for each Pod.

What you can now do with metrics:

- Use `kubectl top` to identify resource-hungry workloads
- Learn how different applications behave under load
- Understand the relationship between resource requests, limits, and actual usage
- Set up Horizontal Pod Autoscalers (covered in advanced topics) that scale based on actual demand

---

#### 0.4.3 Verify dynamic storage provisioning

The journal application later in this tutorial uses a **PersistentVolumeClaim (PVC)** to store SQL Server data. For this to work, your cluster needs a **StorageClass** that can dynamically provision storage when you create a PVC.

Docker Desktop's Kubernetes includes a storage provisioner by default, but it's worth verifying before you reach the journal exercises.

```bash
kubectl get storageclass
```

What you should see:

```
NAME                 PROVISIONER            RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
standard (default)   docker.io/hostpath     Delete          Immediate           false                  XXd
```

Key things to verify:

- A StorageClass exists (usually named `standard` or `hostpath`)
- One StorageClass is marked as `(default)`—this is what PVCs use when you don't specify a class
- The `PROVISIONER` column shows something other than `<none>`

What this means for the tutorial:

When you create a PVC in the journal exercises, the default StorageClass automatically creates a PersistentVolume backed by local storage. The database Pod can then mount this PVC, and its data persists even if the Pod is restarted.

If no StorageClass exists or none is marked as default, the journal PVC will remain in `Pending` state and the database will fail to start.

### 0.5 Resetting the cluster

If you need to reset Kubernetes in Docker Desktop:

1. Open Docker Desktop Settings
2. Go to **Kubernetes**
3. Click **Reset Kubernetes Cluster**
4. Confirm the reset

After resetting, re-run the steps from **0.A.4** to re-enable ingress and metrics-server, then verify storage provisioning in **0.A.4.3**.

### 0.6 Building container images with Docker Desktop

With Docker Desktop's Kubernetes, images you build with Docker are immediately available to the cluster—no special loading step required.

```bash
docker build -t my-image:tag /path/to/build/context
```

The image is ready to use in Kubernetes deployments immediately.

## 0.C Useful Cluster Extensions

Now that your cluster is running with ingress and metrics-server installed, you may want to explore additional extensions that enhance your local Kubernetes experience. These aren't required for the tutorial, but they're useful for experimentation and learning.

Extensions are installed using standard Kubernetes manifests or Helm charts.

### 0.C.1 Kubernetes Dashboard

The Kubernetes Dashboard is a general-purpose, web-based UI for Kubernetes clusters. It allows you to manage and troubleshoot your cluster and applications without memorizing kubectl commands.

**What it does:**

- View cluster resources (Deployments, Pods, Services, etc.) in a graphical interface
- Inspect logs and events without using the terminal
- Launch simple terminal sessions into containers
- Monitor resource usage in real-time

Install the Dashboard:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

Docker Desktop's Kubernetes uses the standard kubectl apply method for extensions. Other cluster environments may provide alternative installation methods.

**Create a login token:**

Create a ServiceAccount with admin privileges and generate a bearer token:

```bash
kubectl create serviceaccount dashboard-admin -n kube-system
kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin
kubectl create token dashboard-admin -n kube-system --duration=87600h
```

Copy the token output - you'll need it to log in.

**Start the proxy and access the Dashboard:**

Start kubectl proxy in a terminal:

```bash
kubectl proxy
```

Keep this terminal running while you use the Dashboard. Then open in your browser:

http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

Select "Token" as the authentication method and paste the token you generated.

**Exploring the Dashboard:**

Once logged in, you'll see an overview of the cluster. Try exploring the ingress controller you installed earlier:

1. Select **ingress-nginx** from the namespace dropdown at the top of the screen
2. Click **Workloads** in the left sidebar to see Deployments, Pods, and other resources in this namespace
3. Click on any resource to view detailed information, including labels, annotations, events, and YAML

Take time to explore what the Dashboard shows. You can view Services, ConfigMaps, Secrets, and more—all through the web interface. This visual exploration is a nice complement to the command-line tools you're learning throughout this tutorial.

Everything you see in the Dashboard can also be retrieved with kubectl commands like `kubectl get`, `kubectl describe`, and `kubectl get -o yaml`. The Dashboard is just a more visual way to interact with the same cluster data. Some people prefer graphical interfaces for exploration and learning; others prefer the precision and scriptability of command-line tools.

**Accessing without kubectl proxy:**

The `kubectl proxy` command used above creates a local proxy to reach the Dashboard. For a more persistent setup, you can expose the Dashboard using Ingress or NodePort—similar to how applications are exposed in later sections of this tutorial. For example, using Ingress would give you a URL like `http://dashboard.local/` without needing to keep a proxy terminal running.

Ingress and service exposure are covered in detail in **[Part 3, section 3.11: Ingress in the application example](03-cluster-usage-examples.md#311-ingress-in-the-application-example)**. You can apply the same patterns to the Dashboard once you're comfortable with those concepts.

### 0.C.2 Local Container Registry

A local container registry allows you to push and pull images within your cluster without relying on external registries like Docker Hub. This is useful for testing custom images and for environments with limited internet access.

**What it does:**

- Provides an in-cluster Docker registry at `registry:5000` or similar
- Allows you to push images locally and pull them from your cluster
- Useful for CI/CD pipelines and air-gapped environments

Docker Desktop's Kubernetes shares your local Docker image store with the cluster, so images you build are immediately available without a separate registry. If you do want an in-cluster registry for testing or CI/CD workflows:

```bash
kubectl create namespace registry
kubectl apply -n registry -f https://raw.githubusercontent.com/kubernetes/kubernetes/main/cluster/addons/registry/registry.yaml
kubectl port-forward -n registry svc/registry 5000:5000
```

Then push images:

```bash
docker tag my-image:tag localhost:5000/my-image:tag
docker push localhost:5000/my-image:tag
```

### 0.C.3 Discovery and Installation

One of the most valuable skills in Kubernetes is finding and installing extensions that match your needs.

**How to discover extensions:**

- **Kubernetes documentation**: https://kubernetes.io/docs/concepts/extend-kubernetes/
- **GitHub**: Search for specific tools (e.g., "kubernetes operator for X")
- **Artifact Hub**: https://artifacthub.io/ - A catalog of Kubernetes packages
- **Helm Hub**: https://helm.sh/ - Package manager for Kubernetes

**Common installation methods:**

1. **kubectl apply** - Direct YAML application (shown throughout this tutorial)
2. **Helm** - Package manager that handles upgrades and rollbacks
3. **Kustomize** - Template-free customization of YAML
4. **Operators** - Application-specific controllers that manage complex software

**Helm example (works on any cluster):**

```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Add a chart repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install a chart
helm install my-ingress ingress-nginx/ingress-nginx
```

---

## Next Steps

Once your cluster is running and you've verified connectivity:

Continue to **[Part 1. Infrastructure and kubectl](01-infrastructure-and-kubectl.md)** to learn about the Kubernetes control plane, nodes, and core cluster services.

The rest of the tutorial uses standard `kubectl` commands.
