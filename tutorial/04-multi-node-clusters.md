# Part 4. Multi-Node Local Clusters

This part explores what happens when your local cluster has more than one node. It matters because the main tutorial uses a single-node cluster, which is the clearest starting point but doesn't show you how Kubernetes makes decisions about where to place workloads when it has multiple nodes to choose from.

## 4.1 Why try a multi-node cluster?

The main tutorial demonstrates all the core Kubernetes concepts with just one node. That works because Pods, Deployments, Services, ConfigMaps, Secrets, and PersistentVolumeClaims all behave the same way whether there's one node or ten.

However, a multi-node cluster shows you behaviors that are hard to observe when everything runs on the same machine:

- **Scheduling decisions**: Kubernetes chooses which node runs each Pod. With multiple nodes, you can see these decisions in action.
- **Pod distribution**: Replicas from a single Deployment may be spread across nodes for resilience.
- **Node-level visibility**: `kubectl get pods -o wide` becomes much more interesting when the NODE column varies.
- **Resource-aware placement**: You can observe how Kubernetes considers node resources when scheduling.

This belongs as a separate extension because the core tutorial doesn't require multiple nodes. But once you're comfortable with the basics, seeing multi-node behavior helps build a more complete mental model of how Kubernetes works.

## 4.2 Creating a multi-node cluster with Docker Desktop

Docker Desktop provides a straightforward way to run a multi-node cluster through its GUI:

### Step 1: Open Docker Desktop Settings

1. Click the Docker Desktop icon in your taskbar/menu bar
2. Click the **Settings** (gear icon)

### Step 2: Adjust Kubernetes node count

1. In the left sidebar, click **Kubernetes**
2. Find the **Kubernetes nodes** slider
3. Adjust to your desired number of nodes (2-3 is a good starting point)
4. Click **Apply & Restart**

### What happens next

Docker Desktop will:
- Stop the current Kubernetes cluster
- Destroy the existing single-node cluster
- Create a new multi-node cluster with the specified number of nodes
- Start Kubernetes with the new configuration

This is a **destructive operation**. Your existing cluster, including all deployed applications, will be removed.

### Step 3: Re-apply essential manifests

After the cluster restarts, you'll need to reinstall some components:

```bash
# Re-enable ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

# Wait for ingress to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

# Re-create the tutorial namespace
kubectl create namespace tutorial

# Verify your nodes
kubectl get nodes -o wide
```

### What you should see

```
NAME                    STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION                      CONTAINER-RUNTIME
desktop-control-plane   Ready    control-plane   4m4s    v1.34.3   172.18.0.4    <none>        Debian GNU/Linux 12 (bookworm)   6.6.114.1-microsoft-standard-WSL2   containerd://2.2.0
desktop-worker          Ready    <none>          3m51s   v1.34.3   172.18.0.3    <none>        Debian GNU/Linux 12 (bookworm)   6.6.114.1-microsoft-standard-WSL2   containerd://2.2.0
desktop-worker2         Ready    <none>          3m50s   v1.34.3   172.18.0.2    <none>        Debian GNU/Linux 12 (bookworm)   6.6.114.1-microsoft-standard-WSL2   containerd://2.2.0
```

**Note:** Your output will differ. Node names, ages, IP addresses, and version numbers will vary depending on your Docker Desktop version and when you created the cluster.

Key observations:
- Multiple nodes are listed
- One node (`desktop-control-plane`) has the `control-plane` role
- The other nodes (`desktop-worker`, `desktop-worker2`) are worker nodes
- The `-o wide` flag shows additional information including internal IPs, OS image, kernel version, and container runtime

## 4.3 Observing system Pods across nodes

Once you have multiple nodes, look at how system Pods are distributed:

```bash
kubectl get pods -A -o wide
```

What to look for:

- **Ingress controller Pods** may be distributed across nodes
- **CoreDNS Pods** typically run on different nodes for resilience
- **System components** like `etcd` and the API server run on the control-plane node

The `NODE` column tells you exactly where each Pod is running. In a single-node cluster, this column is nearly identical for every Pod. In a multi-node cluster, it shows Kubernetes' placement decisions.

## 4.4 Scheduling experiment: spread replicas across nodes

One of the clearest ways to see scheduling in action is to create a Deployment with multiple replicas and watch where Kubernetes places them.

### Create a test Deployment

```bash
kubectl create deployment hello-multi --image=nginx:1.27-alpine -n tutorial
kubectl scale deployment hello-multi --replicas=4 -n tutorial
kubectl rollout status deployment/hello-multi -n tutorial
```

### Observe Pod placement

```bash
kubectl get pods -n tutorial -o wide
```

What you might see:

```
NAME                          READY   STATUS    RESTARTS   AGE     IP           NODE              NOMINATED NODE   READINESS GATES
hello-multi-8bd4df9c4-dlz6w   1/1     Running   0          63s     10.244.2.5   desktop-worker2   <none>           <none>
hello-multi-8bd4df9c4-fqwtx   1/1     Running   0          63s     10.244.1.4   desktop-worker    <none>           <none>
hello-multi-8bd4df9c4-ghpns   1/1     Running   0          63s     10.244.1.3   desktop-worker    <none>           <none>
hello-multi-8bd4df9c4-l7wrz   1/1     Running   0          2m53s   10.244.2.4   desktop-worker2   <none>           <none>
```

**Note:** Your output will differ. Pod names, IP addresses, ages, and exact node distribution will vary. The important pattern to observe is that Pods are distributed across multiple worker nodes.

Key observations:
- Kubernetes distributed replicas across available nodes
- Two replicas are on `desktop-worker2` and two on `desktop-worker`
- No replicas landed on `desktop-control-plane` due to its control-plane taint
- The scheduler aims for reasonable distribution, not perfect spread

### Why this matters

In a single-node cluster, the NODE column is boring—every Pod lands on the same node. In a multi-node cluster, you can see:

- The scheduler making real placement decisions
- How replicas provide resilience across node failures
- That identical Pods from the same Deployment can run on completely different machines

### Clean up the experiment

```bash
kubectl delete deployment hello-multi -n tutorial
```

## 4.5 Node labels and scheduling

Kubernetes uses labels extensively for scheduling decisions. You can see the labels on your nodes:

```bash
kubectl get nodes --show-labels
```

Common node labels you might see:

- `kubernetes.io/hostname`: The node's hostname
- `node-role.kubernetes.io/control-plane`: Marks the control-plane node
- `kubernetes.io/os`: Operating system (typically `linux`)

### Viewing node details

```bash
kubectl describe node desktop-control-plane
kubectl describe node desktop-worker
```

What you'll see:
- Resource capacity and allocation
- Labels and taints
- Conditions describing the node's status
- Pods currently running on the node

This information is what the scheduler uses when deciding where to place new Pods.

### 4.5.1 Adding custom labels to nodes

Beyond the built-in labels, you can add your own labels to nodes. This is useful for creating custom scheduling criteria, such as marking nodes for specific workloads, environments, or hardware characteristics.

Add a custom label to a node:

```bash
kubectl label node desktop-worker2 workload=fast-storage
```

Verify the label was added:

```bash
kubectl get nodes --show-labels | grep desktop-worker2
kubectl describe node desktop-worker2 | grep -A 10 "Labels:"
```

You should see the new `workload=fast-storage` label among the node's labels.

**Why this is useful:**
- Mark nodes for specific types of workloads (databases, web servers, batch jobs)
- Identify hardware capabilities (SSD vs HDD, GPU availability, network bandwidth)
- Create environment-based separation (development vs production nodes)
- Support A/B testing scenarios by routing specific deployments to labeled nodes

### Deploying to nodes with custom labels

Once you've labeled a node, you can target it with `nodeSelector`. Create a Pod that only runs on nodes with your custom label:

```bash
kubectl apply -f -n tutorial -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: fast-storage-pod
spec:
  nodeSelector:
    workload: fast-storage
  containers:
  - name: nginx
    image: nginx:1.27-alpine
    ports:
    - containerPort: 80
EOF
```

Verify where it was scheduled:

```bash
kubectl get pods -n tutorial -o wide
```

The Pod should be running on `desktop-worker2` because it's the only node with the `workload=fast-storage` label.

### Clean up

Remove the Pod:

```bash
kubectl delete pod fast-storage-pod -n tutorial
```

Remove the label from the node:

```bash
kubectl label node desktop-worker2 workload-
```

The trailing hyphen tells Kubernetes to remove that label. Verify it's gone:

```bash
kubectl get node desktop-worker2 --show-labels | grep workload
```

No output means the label has been removed.

**Note:** Labels persist until you remove them. If you forget to clean up custom labels, they may cause unexpected scheduling behavior later. Always clean up labels after experiments.

## 4.6 Using labels to control Pod placement

Beyond observing where Kubernetes places Pods, you can actively control placement using labels, affinities, and tolerations. This section shows you how to target specific nodes and exclude the control-plane from application workloads.

### 4.6.1 Understanding node taints and tolerations

Before controlling placement, understand why Pods normally avoid the control-plane node.

```bash
kubectl describe node desktop-control-plane | grep -A 3 "Taints"
```

You'll typically see:

```
Taints:             node-role.kubernetes.io/control-plane:NoSchedule
```

This `NoSchedule` taint means:
- Pods WITHOUT a matching toleration cannot schedule here
- Only system Pods with the appropriate toleration run on the control-plane
- This protects control-plane resources from being consumed by user applications

### 4.6.2 Pinning a Pod to a specific node with nodeSelector

The simplest placement control is `nodeSelector`—a key-value pair that must match a node's labels.

Create a Pod that only runs on `desktop-worker2`:

```bash
kubectl apply -f -n tutorial -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pinned-pod
spec:
  nodeSelector:
    kubernetes.io/hostname: desktop-worker2
  containers:
  - name: nginx
    image: nginx:1.27-alpine
    ports:
    - containerPort: 80
EOF
```

Verify where it was scheduled:

```bash
kubectl get pods -n tutorial -o wide
```

The `NODE` column shows `desktop-worker2`. Kubernetes placed the Pod there because the `nodeSelector` requires it.

**Why this is useful:**
- Pinning workloads to nodes with specific hardware (GPUs, SSDs)
- Licensing requirements tied to specific machines
- Debugging by isolating workloads to particular nodes

### Clean up

```bash
kubectl delete pod pinned-pod -n tutorial
```

### 4.6.3 Allowing a Pod on the control-plane with tolerations

To run a Pod on the control-plane node, you must add a toleration that matches the taint.

```bash
kubectl apply -f -n tutorial -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: control-plane-pod
spec:
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  containers:
  - name: nginx
    image: nginx:1.27-alpine
EOF
```

Verify placement:

```bash
kubectl get pods -n tutorial -o wide
```

The Pod runs on `desktop-control-plane` because the toleration allows it to bypass the NoSchedule taint.

**Why this is useful:**
- System tools that need control-plane access
- Monitoring agents that must run near the API server
- Testing and debugging in development environments

### Clean up

```bash
kubectl delete pod control-plane-pod -n tutorial
```

### 4.6.4 Running Pods only on worker nodes

A common production pattern: applications run on worker nodes, never on the control-plane. Use `nodeAffinity` to exclude the control-plane.

```bash
kubectl apply -f -n tutorial -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker-only
spec:
  replicas: 4
  selector:
    matchLabels:
      app: worker-only
  template:
    metadata:
      labels:
        app: worker-only
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
EOF
```

Wait for the Pods to be ready:

```bash
kubectl rollout status deployment/worker-only -n tutorial
```

Observe where they landed:

```bash
kubectl get pods -n tutorial -o wide -l app=worker-only
```

All four Pods should be on worker nodes (`desktop-worker`, `desktop-worker2`), not on `desktop-control-plane`.

**How the affinity rule works:**
- `requiredDuringSchedulingIgnoredDuringExecution` means: "Must match this rule to schedule, but ignore it after scheduling"
- The `nodeSelectorTerm` specifies that nodes must NOT have the `node-role.kubernetes.io/control-plane` label
- The `DoesNotExist` operator matches nodes lacking this label
- Result: only worker nodes match, so Pods only schedule there

**Why this pattern matters:**
- Reserves control-plane nodes for system functions
- Prevents applications from competing with Kubernetes system components
- Standard practice in production clusters

### Clean up

```bash
kubectl delete deployment worker-only -n tutorial
```

## 4.7 Resource-aware scheduling

When nodes have different amounts of available resources, Kubernetes considers this during scheduling.

### Check node resource usage

```bash
kubectl top nodes
```

This requires metrics-server, which you should have installed during cluster setup. If you see an error, refer back to **Part 0, section 0.4.2**.

What you might see:

```
NAME                    CPU(cores)   MEMORY(bytes)
desktop-control-plane   123m         1234567K
desktop-worker          89m          987654K
desktop-worker2         95m          1054321K
```

**Note:** Your actual values will differ based on your cluster's workload and resource usage.

### Create a resource-intensive Deployment

You can see resource-aware scheduling by creating Pods with specific resource requests:

```bash
kubectl create deployment resource-test --image=nginx:1.27-alpine -n tutorial
kubectl set resources deployment/resource-test --requests=cpu=100m,memory=128Mi -n tutorial
kubectl scale deployment resource-test --replicas=6 -n tutorial
kubectl get pods -n tutorial -o wide
```

Kubernetes will consider each node's available CPU and memory when placing these Pods.

### Clean up

```bash
kubectl delete deployment resource-test -n tutorial
```

## 4.8 Important limitations of local multi-node clusters

A multi-node local cluster is valuable for learning, but it's important to understand what it doesn't provide:

### What you CAN explore

- Scheduling across multiple nodes
- Pod distribution and placement
- Node-level visibility in kubectl
- Basic resource-aware scheduling

### What you CANNOT fully simulate

- **Network latency between physical machines**: All nodes run on the same host
- **Real failure modes**: If your host machine crashes, all "nodes" go down together
- **True resource isolation**: All nodes compete for the same physical CPU and memory
- **Production networking**: Local networking differs from cloud datacenter networking
- **Distributed storage challenges**: Local storage behaves differently than networked storage

### The value of this exercise

The goal isn't to simulate a production environment perfectly. The value is seeing Kubernetes make real scheduling decisions across multiple nodes. That mental model—understanding that Kubernetes actively chooses where things run—applies whether you're running 3 nodes locally or 3,000 nodes in the cloud.

## 4.9 Returning to a single-node cluster

When you're done experimenting with multiple nodes, return to a single-node configuration:

1. Open Docker Desktop Settings
2. Go to **Kubernetes**
3. Adjust the **Kubernetes nodes** slider back to 1
4. Click **Apply & Restart**

This will again reset your cluster, so you'll need to reapply manifests if you want to continue using the cluster.

---

## Next Steps

Continue to **[Part 5. Advanced cluster usage](05-advanced-cluster-usage.md)** for more advanced Kubernetes topics including RBAC, troubleshooting, and alternative networking options.
