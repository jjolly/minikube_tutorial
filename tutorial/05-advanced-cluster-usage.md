# Part 5. Advanced cluster usage

This part is where the tutorial steps beyond the core walkthrough and shows the reader how to explore, troubleshoot, and extend a Kubernetes lab environment with more confidence. It matters because real understanding does not come only from following the happy path; it also comes from knowing how to diagnose failures, compare environments, experiment with optional features, and recognize where local clusters fit within the larger Kubernetes landscape. The sections here are meant to help the reader grow from someone following examples into someone investigating and experimenting on purpose.

## 5.1 Cluster troubleshooting: what to check and which tools to use

## 5.2 RBAC

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

### Clean up

If you do not want to keep this RBAC example, remove it with:

```bash
kubectl delete -f config/05-journal/12-rbac-readonly.yaml
```

## 5.3 Gateway and alternatives to Ingress

The main tutorial intentionally stays with Ingress. But there are more advanced options worth considering after the core lessons are complete.

See:

- `config/advanced/gateway-options.md`

Summary of options:

- **NGINX Gateway Fabric**
- **Envoy Gateway**
- **Cilium Gateway API**
- **Istio Gateway API support**

### 5.3.1 Recommendation

Keep the main tutorial on **Ingress**.

If you later want one advanced Gateway-focused extension, the best first options are:

1. **NGINX Gateway Fabric**
2. **Envoy Gateway**

## 5.4 Local cluster limitations and Kubernetes alternatives

Local Kubernetes clusters are excellent for learning Kubernetes concepts, testing manifests, and experimenting with application behavior on a local machine. But they are still **local development clusters**, not a full substitute for every kind of Kubernetes environment.

That does not make them "fake." They are real Kubernetes. But they are real Kubernetes in a very particular operating context: usually small, local, single-user, and optimized for experimentation.

### 5.4.1 Where local clusters are especially strong

Local clusters are a good fit when you want:

- a safe place to learn Kubernetes objects and workflows
- fast local iteration
- a disposable environment for trying manifests and images
- one-node cluster behavior that is easy to reason about
- a low-cost lab without renting cloud infrastructure

### 5.4.2 Important limitations to expect

Local clusters usually differ from larger Kubernetes environments in several ways:

- **cluster size and topology**
  - local clusters are often single-node or have limited nodes
  - that means you do not naturally experience multi-node scheduling, node failures, or cross-node networking behavior the way you would in larger environments
- **resource constraints**
  - local clusters are sharing your local machine's CPU, memory, and disk
  - resource pressure often reflects laptop or workstation limits as much as application behavior
- **storage behavior**
  - local storage is useful for learning, but it is not the same as cloud block storage, network storage, or production-grade storage classes
- **network exposure**
  - NodePort, ingress, and localhost testing are often shaped by your desktop, WSL, Docker, or VM networking setup
  - production routing and load-balancer behavior often looks different
- **cloud integrations**
  - local clusters do not automatically give you managed load balancers, managed databases, cloud IAM integration, cloud DNS, or provider-native storage services
- **high availability and failure modes**
  - many production concerns involve control-plane redundancy, node replacement, autoscaling, disruption handling, and upgrade workflows that a local lab does not fully represent
- **team and operational context**
  - local clusters are usually one person's environment
  - shared cluster governance, policy, audit, quotas, and organizational security models often matter much more in real deployments
- **scaling consequences of Pod design**
  - in production-oriented environments, Pod design choices become more operationally important
  - if a Pod contains two tightly coupled containers and you scale that Pod template to three replicas, you are really running six containers in total
  - that is fine when the containers truly belong together, but it is wasteful or awkward when the processes should really scale independently

So the main mindset shift is:

- local clusters teach Kubernetes concepts very well
- but they do not automatically teach every operational reality of a larger environment

### 5.4.3 Common Kubernetes environment alternatives

The main alternatives you are likely to encounter fall into a few broad categories.

#### Managed cloud Kubernetes services

Examples include:

- **Amazon EKS**
- **Google GKE**
- **Azure AKS**
- similar managed offerings from other providers

What is different from local clusters:

- the control plane is usually provider-managed
- cloud integrations are much richer
- storage, load balancers, IAM, DNS, and networking often connect directly to provider services
- multi-node and production-style scaling are much more normal
- cost, quotas, account permissions, and provider architecture become part of daily life

What to expect if you later move from a local cluster to a managed service:

- many basic Kubernetes manifests still look familiar
- infrastructure objects and integrations become more provider-specific
- operational concerns shift toward cloud permissions, networking, and managed-service behavior

##### AKS example: exposing a Service with `type: LoadBalancer`

One of the clearest differences between a local development cluster and a managed cloud environment is how you expose an application.

In Part 2, section 2.8 used `kubectl port-forward` because it is a quick and low-friction way to reach a Service from your local machine during a tutorial. In a production-oriented environment such as **Azure Kubernetes Service (AKS)**, a more typical pattern is to create a Service of type `LoadBalancer` and let the cloud provider allocate an external frontend for it.

Example file: `config/advanced/service-echo-aks-loadbalancer.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: echo-service-lb
  namespace: tutorial
spec:
  type: LoadBalancer
  selector:
    app: echo
  ports:
    - port: 80
      targetPort: 5678
```

What is new here:

- `kind: Service` still creates a Service, just as in Part 2
- `metadata.name: echo-service-lb` gives this Service a distinct name
- `metadata.namespace: tutorial` places it in the `tutorial` namespace
- `spec.type: LoadBalancer` asks AKS to provision an external load balancer for this Service
- `selector.app: echo` tells the Service to send traffic to Pods with the label `app: echo`
- `port: 80` exposes the Service on port 80
- `targetPort: 5678` forwards that traffic to port 5678 on the selected Pods

Apply it:

```bash
kubectl apply -f config/advanced/service-echo-aks-loadbalancer.yaml
kubectl get service echo-service-lb -n tutorial
```

What to look for:

- the `TYPE` column should show `LoadBalancer`
- the `EXTERNAL-IP` field may begin as `<pending>` while AKS asks Azure to provision the load balancer resources
- once provisioning finishes, the Service should receive a public IP address

Why this is different from `port-forward`:

- `port-forward` creates a temporary tunnel from your current machine through `kubectl`
- a `LoadBalancer` Service asks the cloud platform to create infrastructure that can receive traffic independently of your current shell session
- this is much closer to how production systems are commonly exposed

A practical note:

- this pattern depends on cloud-provider integration, so it is normal in AKS, but it does **not** behave the same way in a local cluster unless you separately add tooling such as MetalLB or use a different exposure method

###### Clean up

If you only created this AKS-style example for testing, remove it with:

```bash
kubectl delete -f config/advanced/service-echo-aks-loadbalancer.yaml
```

#### Self-managed Kubernetes on servers or VMs

Examples include clusters built with:

- **kubeadm**
- distributions built around upstream Kubernetes installation workflows
- self-managed clusters on bare metal, VMs, or homelab infrastructure

What is different from local clusters:

- you are more responsible for the cluster itself
- networking, storage, upgrades, certificates, and control-plane health become much more your problem
- the environment can be much closer to production reality, but also more operationally demanding

What to expect:

- more flexibility
- more responsibility
- more places for infrastructure mistakes to matter

#### Lightweight local or edge-focused Kubernetes distributions

Other lightweight distributions you might encounter include:

- **k3s** - focuses on lightweight Kubernetes and is common in edge, lab, and small-server environments
- **k0s** - another lightweight Kubernetes distribution
- **microk8s** - focuses on an easy local or small-scale Kubernetes experience with its own packaging and addon style

These are not all trying to solve the exact same problem. Some emphasize small-footprint deployment, while others are designed for edge computing or specific use cases.

What to expect:

- the Kubernetes API surface is still broadly familiar
- installation model, defaults, networking, ingress setup, storage, and operational tooling can differ a lot

### 5.4.4 How to think about the differences

A practical comparison is:

- **Docker Desktop with Kubernetes**
  - simple GUI-based setup
  - strong integration with Docker workflows
- **managed cloud Kubernetes**
  - strong when you want Kubernetes with provider-managed infrastructure and production-oriented integrations
- **self-managed clusters**
  - strong when you want maximum control and are willing to own the operational complexity

### 5.4.5 What usually carries over from local clusters

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

That is the most important thing to remember: local clusters are not the end state for every Kubernetes user, but they are still a very good way to build the conceptual foundation.

When a cluster is not behaving the way you expected, it helps to think in layers instead of guessing randomly.

A useful troubleshooting order is:

1. **is the cluster running at all?**
2. **is `kubectl` talking to the cluster you think it is?**
3. **are the node and core system Pods healthy?**
4. **did your workload start, schedule, and become ready?**
5. **is networking or storage the actual problem?**

The goal of this section is not to turn you into a production SRE in one step. It is to give you a practical toolkit for diagnosing common Kubernetes problems.

### 5.1.1 First checks: cluster status and context

Start with the broadest questions first.

Useful commands:

```bash
# Check Docker Desktop is running with Kubernetes enabled
kubectl config current-context
kubectl cluster-info
kubectl get nodes -o wide
```

What they help you answer:

- is the cluster actually running?
- is `kubectl` pointing at the context you think it is?
- can `kubectl` reach the cluster control plane?
- is the node visible and reported as `Ready`?

Common problems these help catch:

- Docker Desktop: Kubernetes is disabled in settings
- `kubectl` is pointing at the wrong cluster
- the node is not ready
- the API server is not reachable from your shell

If the context appears stale after recreating a cluster:

```bash
kubectl config use-context <context-name>
```

### 5.1.2 Inspect the node and system components

If the cluster exists but still seems unhealthy, check the node and the core supporting Pods.

Useful commands:

```bash
# Get your node name first
kubectl get nodes

# Then describe it (replace <node-name> with docker-desktop)
kubectl describe node <node-name>
kubectl get pods -n kube-system -o wide
kubectl get events -A --sort-by=.lastTimestamp
```

What to look for:

- node conditions that are not healthy
- core Pods in `CrashLoopBackOff`, `ImagePullBackOff`, `Pending`, or repeated restart states
- recent warning events that mention scheduling, image pulls, probes, or storage issues

This is often where addon failures or cluster-level issues first become visible.

### 5.1.3 Diagnose a Pod that did not start correctly

If your workload exists but is not healthy, inspect the Pod directly.

Useful commands:

```bash
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

If the Pod has more than one container, you may need:

```bash
kubectl logs <pod-name> -n <namespace> -c <container-name>
```

What these commands help you answer:

- is the Pod `Pending`, `Running`, `CrashLoopBackOff`, `ImagePullBackOff`, or `Completed`?
- did the scheduler place it on a node?
- did image pulling fail?
- did readiness or liveness probes fail?
- did the application itself start and then crash?

A good beginner habit is:

- use `get` for the high-level state
- use `describe` for Kubernetes' explanation of what happened
- use `logs` for the application's own output

### 5.1.4 Using ephemeral debugging containers

Sometimes logs and `describe` output are still not enough. You may want to look at the running Pod from the inside with tools that the original image does not contain.

This is where **ephemeral containers** become useful.

Important distinction:

- in normal Kubernetes design, you do **not** edit a running Pod to add a regular application container
- the main Pod containers are supposed to come from the Pod spec created at launch time
- **ephemeral containers** are a special debugging feature that lets you attach a temporary debug container to an existing Pod

So yes, Kubernetes does have a built-in way to add a container to a running Pod, but that mechanism is specifically for debugging. It is not the normal pattern for evolving application behavior in place.

What ephemeral containers are good for:

- inspecting the network namespace of a live Pod
- checking shared filesystems or process state from inside the Pod context
- using tools like `sh`, `wget`, `curl`, `ss`, `ip`, or `nslookup` when the original image is too minimal to include them
- diagnosing problems in production-like images that are intentionally very small

When to avoid or not rely on them:

- when you actually need to change the workload design rather than debug it
- when the cluster's security policy or RBAC rules do not allow ephemeral containers
- when a normal `kubectl logs`, `kubectl describe`, or temporary debug Pod is already enough
- when you are tempted to treat the ephemeral container as a permanent part of the application

A few limitations to understand:

- ephemeral containers are for debugging, not normal service traffic
- they are not part of the original Pod's readiness/liveness design
- they are not how you scale application logic
- some environments may disable or restrict them
- attaching one does not "fix" the Pod spec; it only gives you a way to inspect a running Pod more closely

Useful command pattern:

```bash
kubectl debug -it pod/<pod-name> --image=nicolaka/netshoot --target=<container-name> -- sh
```

What this does:

- attaches a temporary debug container to an existing Pod
- uses the `nicolaka/netshoot` image, which contains many network-debugging tools
- targets one of the original Pod containers so the debug session joins the right Pod context

Simple demonstration with `sidecar-demo`:

```bash
kubectl debug -it pod/sidecar-demo --image=nicolaka/netshoot --target=web -- sh
```

Once inside the ephemeral container, useful checks include:

```sh
wget -qO- http://127.0.0.1
ls -l /usr/share/nginx/html
ip addr
```

Why this demonstration is useful:

- `wget -qO- http://127.0.0.1` helps prove you are sharing the Pod network context
- `ls -l /usr/share/nginx/html` helps you inspect what the nginx container is serving
- `ip addr` helps show the Pod-facing network view from inside the debug container

You can also use the same pattern against `echo-pod` when you want a minimal live target:

```bash
kubectl debug -it pod/echo-pod --image=nicolaka/netshoot --target=echo -- sh
```

A good rule of thumb is:

- use a **temporary debug Pod** when you simply need another client somewhere in the cluster
- use an **ephemeral container** when you need to inspect the inside of an already running Pod

### 5.1.5 Diagnose Deployment rollout problems

Deployments add another layer because Kubernetes is trying to maintain a desired number of Pods for you.

Useful commands:

```bash
kubectl get deployment -A
kubectl describe deployment <deployment-name> -n <namespace>
kubectl rollout status deployment/<deployment-name> -n <namespace>
kubectl get pods -n <namespace> -l app=<label>
```

What these help you answer:

- did the Deployment create a ReplicaSet?
- did the expected number of Pods appear?
- are the Pods stuck starting or failing health checks?
- does the selector actually match the Pods you expected it to manage?

This is especially useful when a Deployment exists but the application still does not seem reachable.

### 5.1.6 Diagnose Service and networking problems

If the Pods are healthy but traffic is not getting through, shift from workload troubleshooting to networking troubleshooting.

Useful commands:

```bash
kubectl get svc -A
kubectl describe svc <service-name> -n <namespace>
kubectl get endpoints -n <namespace> <service-name>
kubectl run netshoot --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh
```

What these help you answer:

- does the Service exist?
- does its selector match real Pods?
- does it have endpoints?
- can another Pod reach the Service by DNS name or IP?

Typical failure patterns:

- the Service selector does not match the Pod labels
- the Pods are not ready, so the Service has no usable endpoints
- the application is listening on a different port than the Service expects
- DNS or path assumptions are wrong

### 5.1.7 Diagnose Ingress and HTTP routing problems

If the Services work but HTTP routing still fails, inspect the ingress layer.

Useful commands:

```bash
kubectl get ingress -A
kubectl describe ingress <ingress-name> -n <namespace>
kubectl get svc -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100
```

What these help you answer:

- does the Ingress object exist with the rules you expected?
- is the ingress controller running?
- are you reaching the correct exposed port/path in your environment?
- is the controller reporting routing or backend errors?

A common beginner mistake is assuming an Ingress YAML problem when the real issue is that traffic is reaching the wrong port or host header.

### 5.1.8 Diagnose storage and PVC problems

When storage is involved, check both the claim and the workload using it.

Useful commands:

```bash
kubectl get pvc -A
kubectl describe pvc <claim-name> -n <namespace>
kubectl get storageclass
kubectl describe pod <pod-name> -n <namespace>
```

What these help you answer:

- is the PVC still `Pending`, or has it bound successfully?
- is there a default storage class?
- is the Pod failing because the volume could not be mounted?
- does the claim request match what the cluster can provide?

This matters because sometimes a Pod looks broken when the real failure is that its storage never became available.

### 5.1.9 High-value troubleshooting commands to remember

If you only remember a short list, remember these:

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl debug -it pod/<pod-name> --image=nicolaka/netshoot --target=<container-name> -- sh
kubectl get svc -A
kubectl get endpoints -A
kubectl get ingress -A
kubectl get pvc -A
kubectl get events -A --sort-by=.lastTimestamp
```

These commands cover a surprisingly large percentage of beginner and intermediate cluster problems.

### 5.1.10 Troubleshooting mindset

A few habits will save you time:

- do not start by changing random YAML fields
- confirm the cluster and context first
- read `describe` output instead of guessing
- check events when something feels mysterious
- isolate whether the problem is cluster-level, workload-level, network-level, or storage-level
- change one thing at a time when testing a fix

For local clusters especially, it is also fair to ask a very practical question:

- would it be faster and clearer to reset the cluster and restart?

Reset Kubernetes cluster from Docker Desktop Settings → Kubernetes → Reset Kubernetes Cluster

Sometimes the answer is yes, especially in a learning environment.

## 5.5 Shared storage with an NFS server pod

Earlier in the tutorial, you learned that node-local storage (like `hostPath` PVs) is tied to a specific node. This section demonstrates a practical pattern for working around that limitation: run an NFS server as a pod that serves node-local storage to other pods via the network.

**Why this pattern is useful:**

- Multiple pods can share the same storage without requiring cloud infrastructure
- Pods can be rescheduled while maintaining access to the same data
- Useful for multi-node local clusters or development environments
- Demonstrates how network filesystem mounting works in Kubernetes

**Architecture:**

```text
Node-local PV (hostPath: /nfs-data)
        |
        v
NFS server Pod (exports /nfs-data via NFS)
        |
        v
Service/nfs-server (stable endpoint: port 2049)
        |
        +----> Client Pod 1 (mounts NFS share at /data)
        +----> Client Pod 2 (mounts NFS share at /data)
```

### 5.5.1 Create the node-local PersistentVolume

First, create a PV backed by a directory on the node:

File: `config/03-nfs-demo/pv-nfs-data.yaml`

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-data-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /nfs-data
```

What this defines:

- `kind: PersistentVolume` creates a cluster storage resource
- `capacity.storage: 1Gi` specifies the size
- `accessModes: ReadWriteOnce` allows single-node mounting (the NFS server pod will mount it)
- `persistentVolumeReclaimPolicy: Retain` keeps the data even if the PVC is deleted
- `hostPath.path: /nfs-data` uses a directory on the node itself

Apply the PV:

```bash
kubectl apply -f config/03-nfs-demo/pv-nfs-data.yaml
```

### 5.5.2 Create the PersistentVolumeClaim

Now create a PVC that binds to the PV:

File: `config/03-nfs-demo/pvc-nfs-data.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-data-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Apply the PVC:

```bash
kubectl apply -f config/03-nfs-demo/pvc-nfs-data.yaml
kubectl get pvc nfs-data-pvc
```

Expected output shows `STATUS: Bound`:

```text
NAME          STATUS   VOLUME         CAPACITY   ACCESS MODES   STORAGECLASS   AGE
nfs-data-pvc  Bound    nfs-data-pv    1Gi        RWO                           <seconds>
```

### 5.5.3 Deploy the NFS server pod

Now deploy an NFS server that uses the PVC and exports it as an NFS share:

File: `config/03-nfs-demo/nfs-server.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-server
  template:
    metadata:
      labels:
        app: nfs-server
    spec:
      containers:
        - name: nfs-server
          image: gcr.io/google_containers/volume-nfs:latest
          ports:
            - name: nfs
              containerPort: 2049
            - name: mountd
              containerPort: 20048
            - name: rpcbind
              containerPort: 111
          securityContext:
            privileged: true
          volumeMounts:
            - name: nfs-data
              mountPath: /data
      volumes:
        - name: nfs-data
          persistentVolumeClaim:
            claimName: nfs-data-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: nfs-server
spec:
  selector:
    app: nfs-server
  ports:
    - name: nfs
      port: 2049
    - name: mountd
      port: 20048
    - name: rpcbind
      port: 111
  type: ClusterIP
```

What this defines:

- A Deployment running the `volume-nfs` container image
- The container runs as privileged (required for NFS server operation)
- The PVC is mounted at `/data` inside the container
- A Service exposes the NFS server on standard NFS ports (2049, 20048, 111)

Apply the NFS server:

```bash
kubectl apply -f config/03-nfs-demo/nfs-server.yaml
kubectl wait --for=condition=ready pod -l app=nfs-server --timeout=120s
```

### 5.5.4 Deploy client pods that use the NFS share

Now create pods that mount and use the NFS share:

File: `config/03-nfs-demo/nfs-client-writer.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nfs-client-writer
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c"]
      args:
        - |
          echo "NFS Client Writer - $(date)" > /data/writer.txt
          echo "This file was written by nfs-client-writer" >> /data/writer.txt
          echo "Content:" && cat /data/writer.txt
          echo "Sleeping for 5 minutes..."
          sleep 300
      volumeMounts:
        - name: nfs-share
          mountPath: /data
  volumes:
    - name: nfs-share
      nfs:
        server: nfs-server
        path: /
```

What this demonstrates:

- The pod mounts the NFS share using the `nfs` volume type
- `server: nfs-server` uses the Service DNS name
- `path: /` corresponds to the `/data` directory exported by the NFS server
- The pod writes a file that other pods can read

Apply the writer pod:

```bash
kubectl apply -f config/03-nfs-demo/nfs-client-writer.yaml
kubectl logs nfs-client-writer
```

Expected output:

```text
NFS Client Writer - <date>
This file was written by nfs-client-writer
Content:
NFS Client Writer - <date>
This file was written by nfs-client-writer
Sleeping for 5 minutes...
```

Now create a second pod that reads the file:

```bash
kubectl run nfs-client-reader --image=busybox:1.36 --restart=Never --rm -i -- sh -c "
  echo 'Installing NFS client...' &&
  apk add --no-cache nfs-client &&
  echo 'Mounting NFS share...' &&
  mkdir /mnt/nfs &&
  mount -t nfs nfs-server:/ /mnt/nfs &&
  echo 'Reading file from NFS share:' &&
  cat /mnt/nfs/writer.txt &&
  echo 'Done!'
"
```

Expected output shows the same content written by the first pod:

```text
Reading file from NFS share:
NFS Client Writer - <date>
This file was written by nfs-client-writer
Done!
```

### 5.5.5 What this demonstrates

- **Shared storage**: Multiple pods accessed the same file
- **Network filesystem**: The NFS protocol allowed remote file access
- **Service integration**: The NFS server was accessed through a stable Service DNS name
- **Separation of concerns**: The NFS server pod manages storage independently from client pods

### 5.5.6 Important limitations

- **Single node**: The underlying PV is still node-local via `hostPath`
- **Node affinity**: The NFS server pod must run on the node where the `/nfs-data` directory exists
- **Production considerations**: For production use, consider:
  - Network-attached storage (NAS) or cloud storage instead of `hostPath`
  - Proper NFS server configuration with authentication and security
  - Readiness probes and health checks for the NFS server

### 5.5.7 Clean up

Remove all the resources created in this demonstration:

```bash
kubectl delete pod nfs-client-writer
kubectl delete deployment nfs-server
kubectl delete service nfs-server
kubectl delete pvc nfs-data-pvc
kubectl delete pv nfs-data-pv
```

If you want to remove the node-local directory as well:

```bash
docker exec -it desktop-worker sh -c "rm -rf /nfs-data"
```

## 5.6 Local cluster extensions

Once you are comfortable with the basics of Pods, Services, Deployments, storage, and ingress, you may want to explore additional cluster features. Docker Desktop's Kubernetes can be extended with standard Kubernetes manifests and Helm charts.

### 5.6.1 Portainer - Visual management interface

Portainer provides a web-based UI for managing both Docker containers and Kubernetes resources. It integrates seamlessly with Docker Desktop.

**What it does:**

- Deploy and manage applications visually
- View logs, resource usage, and container stats
- Manage Docker volumes, networks, and images
- Inspect Kubernetes resources across namespaces

**Install Portainer:**

```bash
# Create the namespace
kubectl create namespace portainer

# Deploy Portainer
kubectl apply -n portainer -f https://raw.githubusercontent.com/portainer/k8s-yaml/main/manifests/portainer/portainer.yaml
```

Wait for Portainer to start:

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=portainer -n portainer --timeout=120s
```

**Access Portainer:**

Port-forward the service:

```bash
kubectl port-forward -n portainer svc/portainer 9443:9443
```

Open in your browser: https://localhost:9443

On first access, you'll be prompted to set an admin password.

**Why this matters for Docker Desktop:**

Portainer bridges the gap between Docker's container management and Kubernetes resources. You can see everything from containers to Deployments in one interface, which is especially helpful during the transition from Docker Compose to Kubernetes workflows.

**Clean up:**

```bash
kubectl delete -n portainer -f https://raw.githubusercontent.com/portainer/k8s-yaml/main/manifests/portainer/portainer.yaml
kubectl delete namespace portainer
```

---

### 5.6.2 MetalLB - LoadBalancer for local clusters

Local clusters don't have a cloud provider to allocate LoadBalancer IPs. MetalLB solves this by providing a network load-balancer implementation that works with standard Kubernetes LoadBalancer services.

**What it does:**

- Enables `type: LoadBalancer` services in local clusters
- Allocates IP addresses from a configurable pool
- Provides Layer 2 mode for simple local setups

**Install MetalLB:**

```bash
# Install MetalLB with manifest
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/main/config/manifests/metallb-native.yaml
```

**Configure IP address pool:**

Create a config map for the IP pool:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.1.240-192.168.1.250
EOF
```

**Test with a LoadBalancer service:**

```bash
kubectl create deployment test-lb --image=nginx:1.27-alpine
kubectl expose deployment test-lb --port=80 --type=LoadBalancer
kubectl get svc test-lb
```

You should see an EXTERNAL-IP assigned from the configured pool.

**Why this matters:**

MetalLB demonstrates how LoadBalancer services work in cloud environments. Understanding LoadBalancer vs Ingress vs NodePort is important for designing service exposure strategies.

**Clean up:**

```bash
kubectl delete deployment test-lb
kubectl delete service test-lb
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/main/config/manifests/metallb-native.yaml
```

---

### 5.6.3 Prometheus + Grafana - Monitoring stack

Prometheus collects metrics, and Grafana visualizes them. This combination is the de facto standard for Kubernetes monitoring.

**What it does:**

- Scrapes metrics from Kubernetes components and applications
- Stores time-series data for historical analysis
- Provides pre-built dashboards for cluster health
- Enables alerting on resource usage

**Install the Prometheus Operator:**

```bash
# Add the Prometheus Community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install the kube-prometheus-stack (includes Prometheus, Grafana, and dashboards)
helm install kube-prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
```

**Access Grafana:**

Port-forward to access Grafana:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80
```

Open: http://localhost:3000

Default credentials:
- Username: `admin`
- Password: run `kubectl get secret -n monitoring kube-prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode`

**Explore dashboards:**

Grafana comes with pre-configured Kubernetes dashboards. Navigate to:
- Dashboards → Browse → Kubernetes → Compute Resources / Pod
- Dashboards → Browse → Kubernetes → Networking / Cluster
- Dashboards → Browse → Kubernetes → Storage / Persistent Volumes

**Why this matters:**

Monitoring is essential for production Kubernetes. This local installation lets you practice with the same tools you'd use in production, helping you understand resource usage patterns and capacity planning.

**Clean up:**

```bash
helm uninstall kube-prometheus -n monitoring
kubectl delete namespace monitoring
```

---

### 5.6.4 cert-manager - Automatic TLS certificates

cert-manager automates the issuance and renewal of TLS certificates, integrating with Let's Encrypt for free HTTPS certificates.

**What it does:**

- Automatically provisions certificates from Let's Encrypt
- Renews certificates before they expire
- Integrates with Ingress resources for automatic HTTPS
- Supports multiple certificate sources (Let's Encrypt, Vault, self-signed)

**Install cert-manager:**

```bash
# Install cert-manager CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
```

**Create a self-signed issuer for testing:**

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
```

**Test with a certificate:**

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: tutorial
spec:
  secretName: test-cert-tls
  dnsNames:
  - test.example.local
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
EOF
```

Verify the certificate:

```bash
kubectl get certificate test-cert -n tutorial
kubectl describe secret test-cert-tls -n tutorial
```

**Why this matters:**

TLS certificate management is critical for production services. cert-manager shows how Kubernetes controllers can automate security operations that would otherwise be manual and error-prone.

**Clean up:**

```bash
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml
```

---

### 5.6.5 Loki - Log aggregation

Loki is a horizontally-scalable log aggregation system inspired by Prometheus. It's designed to be cost-effective and easy to operate.

**What it does:**

- Centralizes logs from all containers
- Provides full-text search and label-based querying
- Integrates with Grafana for log visualization
- Uses less storage than full-text logging solutions

**Install Loki:**

```bash
# Add Grafana Helm repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace loki

# Install Loki and Promtail
helm install loki grafana/loki-stack --namespace loki --set grafana.enabled=false --set promtail.enabled=true
```

**Configure Grafana data source:**

Port-forward Grafana (if not already running):

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80
```

In Grafana:
1. Go to Configuration → Data Sources
2. Add data source → Loki
3. URL: `http://loki.loki:3100`
4. Save and test

**View logs:**

Navigate to Explore → Select Loki datasource → Run query

Try these queries:
- `{namespace="tutorial"}` - All logs from tutorial namespace
- `{namespace="tutorial", container="api"}` - Specific container logs
- `{namespace="tutorial"} |= "error"` - Logs containing "error"

**Why this matters:**

Centralized logging is essential for debugging distributed applications. Unlike `kubectl logs`, which shows one pod at a time, Loki lets you query across all pods and correlate events.

**Clean up:**

```bash
helm uninstall loki -n loki
kubectl delete namespace loki
```

---

### 5.6.6 Additional extensions worth exploring

The following extensions are also valuable for Docker Desktop Kubernetes environments:

**Backup and Recovery:**
- [Velero](https://velero.io/) - Backup and restore cluster resources and persistent volumes

**Resource Management:**
- [Goldilocks](https://goldilocks.docs.fairwinds.com/) - Analyzes resource usage and provides right-sizing recommendations

**Developer Tools:**
- [k9s](https://k9scli.io/) - Terminal UI for Kubernetes (faster navigation than kubectl for many tasks)
- [Kube-shell](https://github.com/kube-shell/kube-shell) - Integrated shell with auto-completion

**Observability:**
- [Jaeger](https://www.jaegertracing.io/) - Distributed tracing platform
- [Kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) - Generates cluster resource metrics

**DNS and Networking:**
- [external-dns](https://github.com/kubernetes-sigs/external-dns) - Automatically create DNS records for Ingress resources

**Security:**
- [Trivy](https://aquasecurity.github.io/trivy/) - Container vulnerability scanner
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/) - Policy as code for Kubernetes

---

Throughout this tutorial, you've used `kubectl` to interact with a single local cluster. As you work with Kubernetes more, you'll likely need to manage multiple clusters: your local development cluster, test clusters, and production environments. The `kubectl config` command is how you manage these connections.

**Understanding kubeconfig:**

Kubernetes stores cluster connection information in a kubeconfig file, typically at `~/.kube/config`. This file contains:
- **Clusters**: API server endpoints and certificate authorities
- **Users**: authentication credentials (certificates, tokens)
- **Contexts**: combinations of a cluster, user, and namespace

A context is a named shortcut. Instead of specifying `--cluster=production --user=admin --namespace=app`, you just use `kubectl config use-context production`.

**Viewing configuration:**

See your current context:

```bash
kubectl config current-context
```

View all configured contexts:

```bash
kubectl config get-contexts
```

View the complete kubeconfig file:

```bash
kubectl config view
```

View just the cluster information:

```bash
kubectl config view --minify
```

The `--minify` flag shows only the current context's information, which is useful when debugging connection problems.

**Switching contexts:**

Switch to a different context:

```bash
kubectl config use-context <context-name>
```

After switching, all `kubectl` commands will target that cluster until you switch again. This is why you ran `kubectl config current-context` earlier in the tutorial—to verify which cluster you're targeting.

Set a default namespace for the current context:

```bash
kubectl config set-context --current --namespace=testing
```

Now `kubectl get pods` will show pods in the `testing` namespace by default, without needing `-n testing` on every command.

**Adding and removing clusters:**

Rename a context:

```bash
kubectl config rename-context old-name new-name
```

Delete a context:

```bash
kubectl config delete-context <context-name>
```

Delete a cluster:

```bash
kubectl config delete-cluster <cluster-name>
```

Set credentials:

```bash
kubectl config set-credentials <user-name> --client-certificate=<path> --client-key=<path>
```

Set a cluster endpoint:

```bash
kubectl config set-cluster <cluster-name> --server=https://kubernetes.example.com
```

**Common workflows:**

**Quick context switching:**

Create an alias or shell function to switch contexts quickly:

```bash
# Add to your .bashrc or .zshrc
kctx() {
  kubectl config use-context $1
}

# Usage: kctx docker-desktop
```

**View namespace for current context:**

```bash
kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}'
```

**List all clusters with their current context status:**

```bash
kubectl config get-contexts -o name
kubectl config current-context
```

**Multiple kubeconfig files:**

Instead of one large kubeconfig file, you can keep separate files and merge them when needed:

```bash
export KUBECONFIG=~/.kube/config:~/.kube/work-config:~/.kube/personal-config
kubectl config get-contexts
```

You can also merge files permanently:

```bash
kubectl config view --flatten > merged-config
mv merged-config ~/.kube/config
```

**Troubleshooting connection issues:**

When `kubectl` can't reach your cluster, start here:

```bash
# 1. What context am I using?
kubectl config current-context

# 2. What cluster does this context point to?
kubectl config view --minify

# 3. Can I reach the API server?
kubectl cluster-info

# 4. Is the certificate valid?
kubectl get nodes
```

Common issues:
- Wrong context: You're targeting a different cluster than you think
- Stale credentials: Certificates expired or tokens rotated
- VPN required: Production clusters often require VPN access
- Firewall: API server port blocked

**Best practices:**

- Use descriptive context names: `dev-cluster`, `staging-us-east`, `production-main`
- Keep separate kubeconfig files for work and personal clusters
- Use shell prompts or tools to show your current context (tools like `kube-ps1` or `kubectx` can help)
- Never commit kubeconfig files with credentials to version control

## 5.7 Managing kubeconfig and contexts

This tutorial includes a few small challenge prompts meant to slow the reader down just enough to think about what Kubernetes is doing.

These are not the only correct ways to reason about the exercises, but they provide useful reference answers if you got stuck.

### 5.8.1 Pod access challenge from section 2.5

Question:

- can you adapt the earlier in-cluster access pattern so it reaches `echo-pod` instead of `simple-echo-pod`?

One solution:

```bash
POD_IP=$(kubectl get pod echo-pod -o jsonpath='{.status.podIP}')
kubectl run netshoot-pod-check --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc "curl -fsS http://$POD_IP:5678"
```

Expected shape of response:

```text
hello from echo-pod at <pod-ip>
```

If that worked, you confirmed that `echo-pod` is reachable from inside the cluster the same way the simpler Pod was.

### 5.8.2 Namespace default challenge from section 2.11

Question:

- why does `kubectl get pods` show different results from `kubectl get pods -n default` after you changed the current context namespace?

Possible explanation:

- `kubectl get pods` now uses the context's default namespace, which you set to `tutorial`
- `kubectl get pods -n default` overrides that default and explicitly asks for objects in `default`
- this is a reminder that the current context can carry a namespace preference, but explicit `-n` flags still win

### 5.8.3 Label selector challenge from section 2.11

Question:

- what happens if you run `kubectl get pods -n tutorial -l tier=demo` before the Deployment exists?

Possible explanation:

- you likely get no results yet
- that is because the earlier standalone Pod used the `app=echo` label, but not `tier=demo`
- the `tier=demo` label appears later in the Deployment's Pod template

### 5.8.4 Deployment observation challenge from section 2.13

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

### 5.8.5 Ingress route prediction challenge from section 3.11

Questions:

- which backend should receive `/genkey/`?
- which backend should receive `/genkey/api`?
- which backend should receive `/journal/`?

Possible explanation:

- `/genkey/` should route to the `genkey-web` Service
- `/genkey/api` also reaches the `genkey-web` Service first in this tutorial's setup, and that frontend nginx then proxies the API path to the backend API Service
- `/journal/` should route to the `journal-web` Service

The key lesson is that Ingress routes to Services, and a Service or frontend proxy may then forward deeper into the application.

### 5.8.6 Dashboard Ingress challenge from section 3.11

Question:

Create an Ingress rule to expose the Kubernetes Dashboard through the ingress controller.

One solution:

There are multiple valid approaches. Here's one using a separate hostname:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: dashboard-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: dashboard.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
```

Apply the manifest:

```bash
kubectl apply -f dashboard-ingress.yaml
```

Get the ingress controller's NodePort and access the Dashboard:

```bash
NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
curl -H 'Host: dashboard.local' "http://localhost:$NODEPORT/"
```

**Note:** Other cluster environments may require different access methods.

Important notes about this solution:

- The Ingress object must be created in the `kubernetes-dashboard` namespace because that's where the Dashboard Service exists
- The host header `dashboard.local` must be used when accessing the URL, or the request won't match this Ingress rule
- The Dashboard Service listens on port 443 (HTTPS), which is why the backend service port is 443
- The `nginx.ingress.kubernetes.io/rewrite-target: /` annotation ensures requests are properly forwarded to the root path

Alternative approaches:

You could also use path-based routing instead of host-based:

```yaml
spec:
  ingressClassName: nginx
  rules:
  - host: tutorial.local
    http:
      paths:
      - path: /dashboard
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
```

This would make the Dashboard accessible at `http://tutorial.local/dashboard` instead of requiring a separate hostname. However, this approach has complications: the Dashboard expects to serve from the root path, so you'd need additional rewrite annotations and configuration.

Clean up when done:

```bash
kubectl delete -f dashboard-ingress.yaml
```

## 5.9 What is already ready for polish later

This version is meant to have the right **structure**, **teaching contrasts**, and **object ordering** first.

During a later polish phase, the highest-value upgrades will be:

- expected command output gathered from actually running the steps
- screenshots if desired
- stronger diagrams and request-flow sketches
- additional troubleshooting callouts after each multi-step example
- possibly replacing the key-generation demo with a safer interactive Flask example if you decide to do that later
