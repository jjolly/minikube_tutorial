# Part 1. Infrastructure and kubectl

This part gives you a first look at the core infrastructure that makes Kubernetes work. It matters because the rest of the tutorial assumes you have a functioning Kubernetes environment and at least a basic mental model of the control plane, nodes, and cluster services. In other words, this part is about making the cluster feel less like a black box.

**Prerequisite:** You should have already set up your local cluster using **[Part 0. Cluster Setup](00-cluster-setup.md)** (either Docker Desktop with Kubernetes or Minikube).

## 1.1 The kube-apiserver

The **kube-apiserver** is the front door to the cluster. `kubectl`, controllers, and other cluster components all interact with Kubernetes by talking to the API server.

At this stage, the main point is not to memorize every line of output. The point is to start recognizing that Kubernetes exposes a large API surface, and that `kubectl` is really a client for that API rather than just a collection of shell shortcuts.

Start by listing resource types the API server knows about:

```bash
kubectl api-resources | head -40
```

What this shows:

- the kinds of things Kubernetes can manage through its API
- examples you are likely to see in this tutorial include:
  - `nodes`
  - `pods`
  - `services`
  - `secrets`
  - `configmaps`
  - `deployments`

Why this is useful:

- it shows that Kubernetes is managing many different object types, not just containers
- it gives you a preview of several concepts you will meet later in the tutorial

A helpful clarification: some things you may think of as one "product" or one application are not always represented by one special API kind. For example, a web application might actually be built from several Kubernetes objects working together, such as a Deployment, a Service, a ConfigMap, a Secret, and an Ingress. Kubernetes often models systems as combinations of smaller building blocks rather than one giant object.

Now list API versions:

```bash
kubectl api-versions
```

What this shows:

- the API groups and versions exposed by the cluster, such as `v1`, `apps/v1`, or `batch/v1`

Why this matters:

- Kubernetes objects are identified by both `kind` and `apiVersion`
- later YAML examples will make more sense when you can see that different object families live in different API groups

Check which context `kubectl` is using:

```bash
kubectl config current-context
```

What this shows:

- which cluster context your `kubectl` commands are currently targeting

Why this matters:

- it helps confirm that your commands are aimed at the cluster you expect

Check the main cluster endpoints:

```bash
kubectl cluster-info
```

What this shows:

- the main control-plane and service endpoints for the current cluster

Why this matters:

- it is one of the quickest ways to confirm that the API server is reachable

Finally, ask the API server for a live object in YAML form:

```bash
kubectl get nodes -o yaml | head -40
```

What this shows:

- real object data returned by the API server right now
- not just a short table, but structured cluster state in YAML form

Why this matters:

- it helps connect the idea of "Kubernetes objects" to the actual data the API server stores and returns
- later in the tutorial, you will create your own objects and inspect them in the same way

It is also worth noticing that full YAML output can become very large very quickly. `kubectl` has built-in output filtering options that let you pull out just the fields you care about.

For example, if you only want the node names:

```bash
kubectl get nodes -o jsonpath='{.items[*].metadata.name}'
```

If you want each node name on its own line:

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
```

If you want to see just the node names and their internal IP addresses:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,INTERNAL_IP:.status.addresses[0].address
```

Why this is useful:

- you do not always need the entire YAML document
- targeted output is much easier to read when objects become large
- later, techniques like `jsonpath` are very helpful when you want one specific value from a Kubernetes object without scanning pages of output

## 1.2 Nodes and the kubelet

A **node** is a machine that Kubernetes can use to run work. In your local cluster, you usually have one node.

The **kubelet** is the Kubernetes agent running on that node. Its job is to make sure the things Kubernetes asked to run on that machine are actually started and kept in the expected state.

At this point in the tutorial, some of the terminology in the command output may still be new. That is okay. The goal here is to start recognizing what the cluster reports about itself. Later sections will explain these ideas in more detail when you begin creating and managing your own application objects.

```bash
kubectl get nodes -o wide
kubectl describe node <your-node-name>
kubectl get pods -n kube-system -o wide
```

**Note:** Replace `<your-node-name>` with your actual node name. This is typically:
- `docker-desktop` for Docker Desktop
- `minikube` for Minikube
- `tutorial-control-plane` for kind

What these commands are showing:

- `kubectl get nodes -o wide`
  - lists the machines Kubernetes currently knows about
  - in this tutorial, that is usually just one node
  - the `-o wide` form adds extra columns such as internal IP address, operating system, kernel version, and container runtime
- `kubectl describe node <your-node-name>`
  - prints a much more detailed report about that one node
  - useful for seeing labels, resource capacity, health conditions, and recent node-related events
- `kubectl get pods -n kube-system -o wide`
  - lists the cluster's own supporting components that are running in the `kube-system` namespace
  - this is useful because it shows that Kubernetes is not just managing your future applications; it is also running internal cluster services

Brief terminology guide for this section:

- **node**
  - a machine Kubernetes can run things on
  - in your local cluster, this is usually the single cluster machine
- **Pod**
  - a running unit of work in Kubernetes
  - Pods are explained properly later; for now, think of them as the basic things Kubernetes starts and manages
- **namespace**
  - a way Kubernetes groups related objects
  - `kube-system` is the namespace commonly used for built-in cluster components
- **container runtime**
  - the software on the node that actually runs containers
  - in this tutorial, that is typically Docker or containerd
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

## 1.3 etcd

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

## 1.4 metrics-server and `kubectl top`

The **metrics-server** collects resource-usage data from the cluster and makes it available through the Kubernetes metrics APIs.

```bash
kubectl get pods -n kube-system
kubectl top nodes
```

Later, after you create workloads in the `tutorial` namespace, `kubectl top pods -n tutorial` becomes more interesting.

---
