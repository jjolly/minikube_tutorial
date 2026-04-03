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

## 4.5 Minikube profiles

So far, the tutorial has treated minikube as if there were only one cluster. That is the right simplification for the main walkthrough. But minikube can manage more than one local cluster by using **profiles**.

A profile is essentially a named minikube cluster instance. Different profiles let you keep separate local Kubernetes environments for different purposes.

Why this can be useful:

- one profile for tutorial experiments
- another profile for unrelated application work
- a clean profile for testing from scratch without disturbing an existing cluster
- a way to compare different addon or configuration choices

Useful commands:

```bash
minikube profile list
minikube start -p tutorial-lab --driver=docker
minikube status -p tutorial-lab
minikube delete -p tutorial-lab
```

What these commands do:

- `minikube profile list`
  - shows the profiles minikube knows about
- `minikube start -p tutorial-lab --driver=docker`
  - creates or starts a cluster named `tutorial-lab`
- `minikube status -p tutorial-lab`
  - checks the state of that specific cluster
- `minikube delete -p tutorial-lab`
  - removes that specific cluster

Important idea:

- a profile is broader than a Kubernetes namespace
- **namespaces** separate resources *inside one cluster*
- **profiles** separate entire local minikube clusters

That means profiles are useful when you want stronger separation than a namespace can give. For example, you might use namespaces to separate tutorial resources from other workloads inside one cluster, but use profiles when you want completely independent clusters with different lifecycle, storage, addons, or experiments.

For this tutorial, you do not need profiles to succeed. But once you start revisiting the tutorial, they can be a practical way to keep a clean lab environment without interfering with other minikube work.

## 4.6 Minikube limitations and Kubernetes alternatives

Minikube is excellent for learning Kubernetes concepts, testing manifests, and experimenting with application behavior on a local machine. But it is still a **local development cluster**, not a full substitute for every kind of Kubernetes environment.

That does not make minikube "fake." It is real Kubernetes. But it is real Kubernetes in a very particular operating context: usually small, local, single-user, and optimized for experimentation.

### Where minikube is especially strong

Minikube is a good fit when you want:

- a safe place to learn Kubernetes objects and workflows
- fast local iteration
- a disposable environment for trying manifests and images
- one-node cluster behavior that is easy to reason about
- a low-cost lab without renting cloud infrastructure

### Important limitations to expect

Minikube usually differs from larger Kubernetes environments in several ways:

- **cluster size and topology**
  - minikube is often a single-node cluster
  - that means you do not naturally experience multi-node scheduling, node failures, or cross-node networking behavior the way you would in larger environments
- **resource constraints**
  - minikube is sharing your local machine's CPU, memory, and disk
  - resource pressure in minikube often reflects laptop or workstation limits as much as application behavior
- **storage behavior**
  - local storage in minikube is useful for learning, but it is not the same as cloud block storage, network storage, or production-grade storage classes
- **network exposure**
  - NodePort, ingress, and localhost testing in minikube are often shaped by your desktop, WSL, Docker, or VM networking setup
  - production routing and load-balancer behavior often looks different
- **cloud integrations**
  - minikube does not automatically give you managed load balancers, managed databases, cloud IAM integration, cloud DNS, or provider-native storage services
- **high availability and failure modes**
  - many production concerns involve control-plane redundancy, node replacement, autoscaling, disruption handling, and upgrade workflows that a local lab does not fully represent
- **team and operational context**
  - minikube is usually one person's environment
  - shared cluster governance, policy, audit, quotas, and organizational security models often matter much more in real deployments

So the main mindset shift is:

- minikube teaches Kubernetes concepts very well
- but it does not automatically teach every operational reality of a larger environment

### Common Kubernetes environment alternatives

The main alternatives you are likely to encounter fall into a few broad categories.

#### Managed cloud Kubernetes services

Examples include:

- **Amazon EKS**
- **Google GKE**
- **Azure AKS**
- similar managed offerings from other providers

What is different from minikube:

- the control plane is usually provider-managed
- cloud integrations are much richer
- storage, load balancers, IAM, DNS, and networking often connect directly to provider services
- multi-node and production-style scaling are much more normal
- cost, quotas, account permissions, and provider architecture become part of daily life

What to expect if you later move from minikube to a managed service:

- many basic Kubernetes manifests still look familiar
- infrastructure objects and integrations become more provider-specific
- operational concerns shift toward cloud permissions, networking, and managed-service behavior

#### Self-managed Kubernetes on servers or VMs

Examples include clusters built with:

- **kubeadm**
- distributions built around upstream Kubernetes installation workflows
- self-managed clusters on bare metal, VMs, or homelab infrastructure

What is different from minikube:

- you are more responsible for the cluster itself
- networking, storage, upgrades, certificates, and control-plane health become much more your problem
- the environment can be much closer to production reality, but also more operationally demanding

What to expect:

- more flexibility
- more responsibility
- more places for infrastructure mistakes to matter

#### Lightweight local or edge-focused Kubernetes distributions

Examples include:

- **kind**
- **k3s**
- **k0s**
- **microk8s**

These are not all trying to solve the exact same problem, but they are often considered alongside minikube.

What is different from minikube:

- **kind** is often used for CI, testing, and disposable multi-node-in-Docker scenarios
- **k3s** focuses on lightweight Kubernetes and is common in edge, lab, and small-server environments
- **microk8s** focuses on an easy local or small-scale Kubernetes experience with its own packaging and addon style
- some of these environments feel more "cluster-like" in multi-node testing, while others emphasize small-footprint deployment

What to expect:

- the Kubernetes API surface is still broadly familiar
- installation model, defaults, networking, ingress setup, storage, and operational tooling can differ a lot

### How to think about the differences

A practical comparison is:

- **minikube**
  - best for learning, local development, and experimentation
- **kind**
  - strong for disposable test clusters and CI-oriented workflows
- **k3s / similar lightweight distributions**
  - strong for small servers, edge, labs, and lightweight deployments
- **managed cloud Kubernetes**
  - strong when you want Kubernetes with provider-managed infrastructure and production-oriented integrations
- **self-managed clusters**
  - strong when you want maximum control and are willing to own the operational complexity

### What usually carries over from minikube

Even when the surrounding environment changes, many of the core lessons in this tutorial still transfer well:

- Pods
- Services
- Deployments
- ConfigMaps
- Secrets
- PVC concepts
- RBAC concepts
- Ingress and routing ideas
- `kubectl` habits

That is the most important thing to remember: minikube is not the end state for every Kubernetes user, but it is still a very good way to build the conceptual foundation.

## 4.7 Ten minikube addons worth exploring

Once you are comfortable with the basics of Pods, Services, Deployments, storage, and ingress, minikube addons are one of the easiest ways to keep experimenting.

An addon is a prepackaged cluster feature that minikube knows how to enable and disable for you. They are useful because they let you try common Kubernetes components without manually installing every controller or supporting manifest yourself.

A good first command to know is:

```bash
minikube addons list
```

And the basic pattern for using an addon is:

```bash
minikube addons enable <addon-name>
minikube addons disable <addon-name>
```

Two important addons have already been used in this tutorial:

- `ingress`
  - enabled in **section 1.10**
  - used more fully in the application routing walkthrough in **section 3.11**
- `metrics-server`
  - enabled in **section 1.10**
  - explained and used with `kubectl top` in **section 1.15**

Those were introduced earlier because they were needed for the main walkthrough. The list below focuses on **additional addons** you can experiment with after the core tutorial, while still keeping a practical top-10 set overall.

### 4.8 dashboard

What it does:

- provides the Kubernetes Dashboard web UI

Why it is useful:

- gives you a visual way to browse workloads, namespaces, and object status
- useful when you want a second view alongside `kubectl`

Basic use:

```bash
minikube addons enable dashboard
minikube dashboard
```

### 4.9 storage-provisioner

What it does:

- provides dynamic storage provisioning for local PersistentVolumeClaims in minikube

Why it is useful:

- makes PVC examples easier because storage can be provisioned automatically
- helps demonstrate persistent storage concepts without setting up a separate storage system

Basic use:

```bash
minikube addons enable storage-provisioner
kubectl get storageclass
kubectl get pvc -A
```

### 4.10 default-storageclass

What it does:

- marks a storage class as the default choice for PVCs that do not specify one explicitly

Why it is useful:

- makes storage examples simpler
- helps you understand how Kubernetes picks a storage class when none is named

Basic use:

```bash
minikube addons enable default-storageclass
kubectl get storageclass
```

### 4.11 registry

What it does:

- provides an in-cluster container registry endpoint for image workflows

Why it is useful:

- lets you experiment with image push/pull flows without depending entirely on remote registries
- useful when learning how clusters consume custom images

Basic use:

```bash
minikube addons enable registry
kubectl get svc -n kube-system
```

This one often benefits from reading the current minikube docs before deeper use, because local image workflow details can vary by driver and setup.

### 4.12 registry-creds

What it does:

- helps configure registry credentials for pulling images from supported external registries

Why it is useful:

- useful when your experiments involve private images
- shows how cluster image-pull behavior interacts with registry auth

Basic use:

```bash
minikube addons enable registry-creds
kubectl get pods -n kube-system
```

This addon is more interesting once you have a real registry workflow to test.

### 4.13 volumesnapshots

What it does:

- enables snapshot-related Kubernetes resources used with compatible CSI storage drivers

Why it is useful:

- helps you explore more advanced storage ideas beyond "a PVC exists"
- useful when you want to understand how storage backups and snapshots are modeled in Kubernetes

Basic use:

```bash
minikube addons enable volumesnapshots
kubectl api-resources | grep -i snapshot
```

### 4.14 csi-hostpath-driver

What it does:

- provides a CSI hostpath storage driver suitable for local testing and storage experiments

Why it is useful:

- lets you experiment with CSI-based storage behavior in a local lab
- useful when you want to understand modern Kubernetes storage interfaces rather than only older in-tree behavior

Basic use:

```bash
minikube addons enable csi-hostpath-driver
kubectl get csidrivers
kubectl get pods -A | grep csi || true
```

### 4.15 gvisor

What it does:

- enables the gVisor container sandbox runtime in supported environments

Why it is useful:

- gives you a way to experiment with stronger isolation tradeoffs
- useful for learning that not all container runtime choices have the same security and performance profile

Basic use:

```bash
minikube addons enable gvisor
kubectl get runtimeclass
```

This is more advanced than the others because it leads into runtime-class and sandboxing topics.

### 4.16 logviewer

What it does:

- provides a simple web UI for viewing logs from workloads in the cluster

Why it is useful:

- gives another way to inspect application behavior
- can be a nice complement to `kubectl logs` during experimentation

Basic use:

```bash
minikube addons enable logviewer
minikube service logviewer -n kube-system
```

### 4.17 metallb

What it does:

- provides a software load-balancer implementation for bare-metal or local-cluster style environments

Why it is useful:

- helps you experiment with `LoadBalancer` Services in an environment that does not have a cloud-provider load balancer by default
- useful when you want to better understand how service exposure differs between local clusters and cloud clusters

Basic use:

```bash
minikube addons enable metallb
kubectl get pods -n metallb-system
```

This addon becomes more interesting when you start experimenting with `Service` objects of type `LoadBalancer`.

### 4.18 How to choose what to try next

A good order of experimentation after the core tutorial would be:

1. `dashboard`
2. `storage-provisioner` and `default-storageclass`
3. `metallb`
4. `registry` / `registry-creds`
5. `volumesnapshots` / `csi-hostpath-driver`
6. `gvisor`
7. `logviewer`

That order moves from low-friction visibility and storage features toward more advanced network exposure, runtime, and image-distribution topics.

One practical warning: enabling many addons at once can make a small local cluster harder to reason about. It is usually better to enable one addon, inspect what new Pods and resources appear, experiment with it, and then decide whether to keep it.

## 4.19 Exercise notes and possible solutions

This tutorial includes a few small challenge prompts meant to slow the reader down just enough to think about what Kubernetes is doing.

These are not the only correct ways to reason about the exercises, but they provide useful reference answers if you got stuck.

### 4.20 Pod access challenge from section 2.5

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

### 4.21 Namespace default challenge from section 2.11

Question:

- why does `kubectl get pods` show different results from `kubectl get pods -n default` after you changed the current context namespace?

Possible explanation:

- `kubectl get pods` now uses the context's default namespace, which you set to `tutorial`
- `kubectl get pods -n default` overrides that default and explicitly asks for objects in `default`
- this is a reminder that the current context can carry a namespace preference, but explicit `-n` flags still win

### 4.22 Label selector challenge from section 2.13

Question:

- what happens if you run `kubectl get pods -n tutorial -l tier=demo` before the Deployment exists?

Possible explanation:

- you likely get no results yet
- that is because the earlier standalone Pod used the `app=echo` label, but not `tier=demo`
- the `tier=demo` label appears later in the Deployment's Pod template

### 4.23 Deployment observation challenge from section 2.15

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

### 4.24 Ingress route prediction challenge from section 3.11

Questions:

- which backend should receive `/genkey/`?
- which backend should receive `/genkey/api`?
- which backend should receive `/journal/`?

Possible explanation:

- `/genkey/` should route to the `genkey-web` Service
- `/genkey/api` also reaches the `genkey-web` Service first in this tutorial's setup, and that frontend nginx then proxies the API path to the backend API Service
- `/journal/` should route to the `journal-web` Service

The key lesson is that Ingress routes to Services, and a Service or frontend proxy may then forward deeper into the application.

## 4.25 What is already ready for polish later

This version is meant to have the right **structure**, **teaching contrasts**, and **object ordering** first.

During a later polish phase, the highest-value upgrades will be:

- expected command output gathered from actually running the steps
- screenshots if desired
- stronger diagrams and request-flow sketches
- additional troubleshooting callouts after each multi-step example
- possibly replacing the key-generation demo with a safer interactive Flask example if you decide to do that later
