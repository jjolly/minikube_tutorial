# Minikube Tutorial: From First Pods to a Reverse-Proxy Stack and Stateful Journal App

This tutorial is a progressive guide to learning Kubernetes on **minikube** running inside **WSL Linux**. It is aimed at a setup that should be general enough for **Ubuntu** and **openSUSE Leap** inside WSL.

The tutorial deliberately teaches by contrast in a few places:

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
- a Flask `/genkey` service behind nginx
- a React frontend under `/genkey` with a Flask API at `/genkey/api`
- a C# journal application backed by Microsoft SQL Server with persistent storage
- an Ingress route exposing both `/genkey` and `/journal`

---

## 0. What you are building and why

Minikube gives you a local Kubernetes cluster you can experiment with safely. On WSL, that means you can learn the Kubernetes object model and application deployment flow without renting cloud infrastructure first.

The tutorial introduces these Kubernetes ideas in this order:

1. Pods
2. Services
3. Networking
4. Namespaces
5. Labels
6. Deployments
7. kube-apiserver
8. Nodes and kubelet
9. etcd
10. metrics-server and `kubectl top`
11. Secrets
12. ConfigMaps
13. Persistent Volumes
14. RBAC
15. Ingress
16. Advanced topics: Gateway API options

---

## 1. Prerequisites

Assume you are starting at a Linux shell prompt and you are not yet sure what is installed, what is configured, or whether minikube is already running. This section is written for that situation.

You should assume only that:

- you can log in as a normal user
- you can use `sudo`
- you are working inside WSL on either Ubuntu or openSUSE Leap

If you already have some of these tools installed, the commands below are still useful because they help you verify what state the machine is in before you begin.

### 1.1 Check what is already installed

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

In a normal interactive shell, some of these commands may fail if the tool is not installed yet. That is fine. For example, you might see messages such as `docker: command not found` or no output from `which docker`.

That is not a problem. At this stage, you are only checking what is already present before installing anything.

### 1.2 Why this tutorial uses Docker as the minikube driver

Minikube can run on top of different drivers and container runtimes. In practice, beginners often encounter these options first:

- **Docker driver**
  - usually the easiest local learning path
  - familiar if you have seen container workflows before
  - works well in WSL-based development setups
- **Podman driver**
  - viable in some environments
  - attractive if you prefer a daemonless container tool
  - less common in beginner minikube walkthroughs, so you may find fewer examples that match exactly
- **KVM/libvirt or other VM-based drivers**
  - useful on full Linux systems
  - can be very solid
  - usually adds more host setup complexity than is helpful for a first tutorial in WSL
- **none driver / bare-metal style setups**
  - powerful but not a beginner path
  - easy to make host-level mistakes if you do not already understand the tradeoffs

This tutorial chooses **Docker** because it is usually the least surprising route for someone coming from a Windows background with only light Linux command-line experience.

Why Docker is a sensible default here:

- it is widely documented
- minikube works well with it in many WSL setups
- the idea of “build an image, then run it” stays consistent across the tutorial
- it avoids adding a second big conceptual hurdle while you are trying to learn Kubernetes itself

This is not a claim that Docker is the only good choice. It is simply the most practical teaching choice for this tutorial.

### 1.3 Why the Docker setup steps matter

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

For someone new to Linux, that last point is especially easy to miss: being added to a group does not always affect the shell you are already sitting in. `newgrp docker` is a convenient way to refresh that in-place.

### 1.4 Ubuntu packages

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

### 1.5 openSUSE Leap packages

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

### 1.6 Install kubectl

`kubectl` is the command-line client for the Kubernetes API server.

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

### 1.7 Install minikube

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version
```

### 1.8 Start and verify the cluster

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

If `kubectl` later appears to be talking to an old or stale minikube endpoint, here is what that usually looks like and how to recognize it.

A stale endpoint means `kubectl` is still using a kubeconfig entry that points at an older minikube API server address or certificate after minikube was restarted, recreated, or otherwise changed.

Common signs include:

- `kubectl` fails with connection errors such as `The connection to the server <ip>:<port> was refused`, `Unable to connect to the server`, or `i/o timeout`
- `kubectl` fails with TLS or certificate errors such as `x509: certificate is valid for ... not ...`
- `kubectl cluster-info` reports a control-plane address that does not match the current minikube instance
- `kubectl get pods -A` or similar commands show unexpected old state, empty results, or resources that do not match the cluster you just started

To check whether this is happening, compare what `kubectl` thinks the current cluster is with what minikube reports:

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

### 1.9 Enable ingress and metrics collection

The tutorial uses two minikube addons early:

```bash
minikube addons enable ingress
minikube addons enable metrics-server
```

Why these addons are enabled:

- **ingress** provides the nginx ingress controller used later in the tutorial
- **metrics-server** provides resource-usage data for commands such as `kubectl top`, which we will use later to inspect node and Pod CPU/memory usage

---

## 2. Tutorial layout

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
```

- `src/` contains application source code and Docker build inputs.
- `config/` contains Kubernetes manifests.
- `config/05-journal/step1-startup-init/` contains the first database-init approach.
- `config/05-journal/step2-job-init/` contains the improved database-init approach.

---

## 3. Pods

A **pod** is the smallest deployable unit in Kubernetes. A pod usually runs one application container, though it can run more than one when the containers are meant to cooperate tightly.

### 3.1 Run a short-lived BusyBox pod

A Pod can be started directly from the command line with `kubectl run`. That is convenient for quick experiments, but the Pod only lasts as long as the command running inside it lasts.

In this example, the command prints a message and then uses `sleep 15` to keep the Pod alive for a few extra seconds. That pause gives you time to inspect the Pod while it is still running, and then again after the command has completed.

```bash
kubectl run bb-demo --image=busybox:1.36 --restart=Never --command -- sh -c 'echo hello from kubernetes && sleep 15'
kubectl logs bb-demo
kubectl get pod bb-demo
kubectl delete pod bb-demo
```

A small but important detail: Pods started this way may remain visible in Kubernetes after their command has finished so you can still inspect their status and logs, but they are not something you "reuse". Once the original command is done, that Pod's job is over.

It is also useful to understand what Kubernetes does **not** do here. A Pod is not usually treated like a long-lived container that you manually stop, pause, and resume later. In this tutorial's model, once a Pod exists, it runs until the process inside it exits or until Kubernetes deletes the Pod. Later sections will show that higher-level controllers automate Pod creation and replacement for you, which is one of the key differences between working with raw Pods and working with Deployments.

### 3.2 Create a long-running pod from YAML

Pods can also be defined declaratively in YAML. That approach is better for repeatable configuration, and it works naturally for longer-running processes such as a web server that should stay up without you waiting for a one-shot shell command to finish.

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

What the fields are for:

- `apiVersion: v1` — says this object uses the core v1 Kubernetes API.
- `kind: Pod` — declares the object type.
- `metadata.name` — gives the object its cluster-local name.
- `metadata.labels` — attaches identifying key/value metadata for selection and grouping.
- `spec.containers` — lists containers that should run inside the pod.
- `image` — container image to launch.
- `args` — command arguments passed to the container entrypoint.
- `containerPort` — documents the port the container listens on.

Apply it:

```bash
kubectl apply -f config/01-pods/pod-echo.yaml
kubectl get pods -o wide
kubectl describe pod echo-pod
```

What you should observe:

- `kubectl apply` should report `pod/echo-pod created` the first time
- `kubectl get pods -o wide` should eventually show `echo-pod` in `Running`
- the pod should be scheduled onto your minikube node

Example shape of output:

```text
NAME       READY   STATUS    RESTARTS   AGE   IP           NODE
echo-pod   1/1     Running   0          23s   10.244.0.6   minikube
```

`kubectl describe pod echo-pod` produces much more detail. That can feel noisy the first time you see it, so here is a shortened example with guidance on what to focus on first:

```text
Name:             echo-pod
Namespace:        default
Node:             minikube/192.168.49.2
Start Time:       Wed, 01 Apr 2026 07:57:01 -0600
Labels:           app=echo
Status:           Running
IP:               10.244.0.56
Containers:
  echo:
    Image:         hashicorp/http-echo:1.0.0
    Port:          5678/TCP
    Args:
      -text=hello from echo-pod
    State:          Running
    Ready:          True
    Restart Count:  0
Conditions:
  Type                 Status
  Initialized          True
  Ready                True
  ContainersReady      True
  PodScheduled         True
Events:
  Type    Reason     Message
  ----    ------     -------
  Normal  Scheduled  Successfully assigned default/echo-pod to minikube
  Normal  Pulled     Container image "hashicorp/http-echo:1.0.0" already present on machine
  Normal  Created    Created container: echo
  Normal  Started    Started container echo
```

How to read this without getting overwhelmed:

- `Name`, `Namespace`, and `Labels`
  - identify which object you are looking at and how other Kubernetes objects may select it
- `Node`
  - shows which Kubernetes node is running the Pod
  - in this tutorial it should usually be `minikube`
- `Status`
  - the quick high-level state of the Pod
  - for this step, `Running` is what you want
- `IP`
  - the Pod's cluster-internal IP address
  - useful for understanding that Pods really do get their own network identity
- `Containers`
  - confirms the image, exposed port, startup arguments, and whether the container is actually running
  - `Ready: True` and `Restart Count: 0` are especially reassuring for a first example
- `Conditions`
  - Kubernetes' checklist for whether the Pod made it through scheduling and startup successfully
  - `PodScheduled=True`, `Initialized=True`, and `Ready=True` are the main first-pass signals to notice
- `Events`
  - often the most useful troubleshooting section
  - if something goes wrong, this is where you often first see why: image pull failures, scheduling problems, crash loops, and probe failures commonly show up here

For a first-time user, the most important habit is this: when a Pod does not behave the way you expected, look at `Status`, `Containers`, `Conditions`, and `Events` before worrying about the rest of the output.

At this point, the Pod is running an HTTP server, but reaching it directly is awkward. This can be demonstrated by attempting to access our running Pod's web server with a few commands.

First get the Pod IP:

```bash
kubectl get pod echo-pod -o wide
```

You will see a cluster-internal Pod IP, something like `10.244.0.56`.

In the next command, we are going to create a new temporary Pod whose only job is to act as a client and try to reach `echo-pod` over the cluster network.

A first-time user may reasonably ask: why are we about to create a second Pod just to reach the first one?

Because the `echo-pod` web server is not directly reachable from outside the cluster. To talk to it by IP, we need to send the request from **inside** the cluster network. A simple way to do that is to start a temporary second Pod that has `curl` available and use it as a test client.

```bash
POD_IP=$(kubectl get pod echo-pod -o jsonpath='{.status.podIP}')
kubectl run netshoot-pod-check --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc "curl -fsS http://$POD_IP:5678"
```

Expected response:

```text
hello from echo-pod
```

What this demonstrates:

- the first Pod really is serving HTTP traffic
- the Pod IP is usable from inside the cluster network
- reaching a Pod directly takes extra work and cluster-specific knowledge

Why this is not very useful as a general access pattern:

- you had to discover the Pod IP first
- that IP is internal to the cluster
- if the Pod is recreated, the IP may change
- you had to create a second Pod just to test the first one from inside the cluster
- other workloads should not have to track individual Pod addresses by hand

Before moving on, delete this standalone Pod so the next section can recreate it intentionally as the backend for the next networking step:

```bash
kubectl delete pod echo-pod
```

This cleanup keeps the first Pod example self-contained before the tutorial moves on to the next networking step.

This is a good place to call out another important Kubernetes mindset shift: Pods are simple running instances of processes. You generally do not "pause" or "stop" them the way you might with individual Docker containers. When a Pod has been defined, Kubernetes tries to create it. To stop that Pod, either let the program inside it exit or delete the Pod. In later sections, Kubernetes controllers will take over that create/remove cycle automatically.

---

## 4. Services

Pods are ephemeral. A pod can be recreated and receive a different IP address. A **Service** gives a stable virtual IP and DNS name that can target one or more matching pods.

Small mental model:

```text
client
  |
  v
Service (stable name / stable virtual IP)
  |
  v
Pod
```

This is one of the most important mental-model shifts in Kubernetes:

- you usually do **not** build application communication around Pod IPs
- you usually build it around **Services**

Pods come and go. Services give other workloads a stable way to find the current healthy backend Pods.

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

What the fields are for:

- `kind: Service` — declares a stable network endpoint.
- `selector` — chooses pods with matching labels.
  - in this example, `app: echo` matches the earlier `echo-pod`, because that Pod was created with the label `app: echo`
  - this label match is what makes the Service send traffic to that Pod
- `port` — port exposed by the Service.
- `targetPort` — port on the selected pods.

Before creating the Service, recreate the Pod so there is actually a matching backend for the Service to target:

```bash
kubectl apply -f config/01-pods/pod-echo.yaml
kubectl wait --for=condition=Ready pod/echo-pod --timeout=120s
kubectl apply -f config/01-pods/service-echo.yaml
kubectl port-forward service/echo-service 8080:80
```

Leave that port-forward running in the first terminal. In a second terminal, test the Service:

```bash
curl http://127.0.0.1:8080
```

If you are using WSL, you can also open a Windows browser to:

```text
http://localhost:8080
```

That is a useful early demonstration that the Kubernetes environment you are working with inside WSL can still be reached conveniently from the Windows side through the forwarded localhost port. The same pattern will make later web-based examples easier to test.

What you should observe:

- the Service should be created immediately
- `kubectl port-forward` should hold the terminal open while forwarding traffic
- the `curl` request should return the text served by the container through the Service

Expected response:

```text
hello from echo-pod
```

This is an important moment in the tutorial: you are no longer talking to the Pod directly. You are talking to a stable Service endpoint that selects the Pod.

Troubleshooting:

- if `curl` cannot connect, make sure `kubectl port-forward` is still running in the foreground
- if the Service exists but does not answer, run `kubectl get pods --show-labels` and confirm the Pod still has `app=echo`
- if needed, inspect the Service selector with `kubectl get svc echo-service -o yaml`

---

## 5. Kubernetes networking

Kubernetes networking is built around a few expectations:

```text
Pod A  --DNS lookup-->  Service name
  |                      |
  |------HTTP/TCP------> Service virtual IP
                         |
                         v
                      backend Pod
```

- every pod gets an IP
- pods can usually talk directly to other pods
- Services provide stable names and virtual IPs
- cluster DNS resolves Service names automatically

Test from a temporary shell pod:

```bash
kubectl run netshoot --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc 'nslookup echo-service && curl -fsS http://echo-service'
```

What you should observe:

- `nslookup echo-service` should resolve the Service name using cluster DNS
- `curl http://echo-service` should return the same echo text as before
- this demonstrates that Pods inside the cluster can reach Services by DNS name instead of hard-coded IP addresses

Expected response from `curl`:

```text
hello from echo-pod
```

Troubleshooting:

- if `nslookup echo-service` fails, check that you are still inside the temporary shell pod and that the Service exists in the same namespace
- if DNS resolves but `curl` fails, verify that the backend Pod is running and that the Service selector matches it
- if the temporary pod exits too quickly, rerun the `kubectl run netshoot ...` command and test again

---

## 6. Namespaces

A **namespace** groups resources so you can separate environments and reduce clutter.

Up to this point, you have been working in the default namespace without saying much about it. That is convenient for the first few examples, but real Kubernetes usage quickly becomes harder to follow if everything is left in `default`.

Namespaces help by giving related resources their own named space inside the cluster. In practice, that means:

- you can group tutorial resources separately from system resources
- you can avoid mixing unrelated workloads together
- you can run the same kinds of objects in different namespaces without name collisions between those namespaces
- commands become easier to reason about because you can ask specifically for the objects in one namespace
- access control often becomes easier to manage because permissions are very commonly granted within a namespace boundary rather than across the whole cluster

That last point becomes especially important when RBAC is introduced later. In real clusters, namespaces are often a major part of how teams separate ownership and control who can view or change which resources.

In this section, you are creating a new namespace named `tutorial` and then recreating the echo Pod and Service inside it.

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

What to notice here:

- `-n tutorial` tells `kubectl` to create or query objects in the `tutorial` namespace instead of `default`
- the Pod and Service names are still `echo-pod` and `echo-service`, but now they live inside `tutorial`
- `kubectl get all -n tutorial` should show only the resources in that namespace, which makes the output easier to focus on

This is another habit worth building early: when you read Kubernetes commands and YAML, pay attention not just to the object name, but also to which namespace it lives in.

### 6.1 Contexts and changing the default namespace

So far, the tutorial has used `-n tutorial` explicitly. That is a good habit when learning because it makes the target namespace obvious.

Kubernetes also has the idea of a **context** in your kubeconfig. A context can store several defaults at once, including:

- which cluster you are talking to
- which user or credential set you are using
- which namespace `kubectl` should use by default

You can inspect your current context with:

```bash
kubectl config current-context
kubectl config view --minify
```

If you want your current context to default to the `tutorial` namespace, you can set it like this:

```bash
kubectl config set-context --current --namespace=tutorial
```

After that, commands such as `kubectl get pods` will use `tutorial` by default until you change the context or override it with `-n`.

You can confirm the effect with:

```bash
kubectl get pods
kubectl get svc
```

For a beginner tutorial, it is still often clearer to keep writing `-n tutorial` in commands. But it is worth knowing that context defaults exist, because in real Kubernetes work they are used constantly.

---

## 7. Labels

**Labels** are key/value pairs attached to objects. Kubernetes uses them heavily for selection.

Examples:

- a Service uses labels to decide which pods are backends
- a Deployment uses labels to identify the pods it manages
- operators use labels to filter resources

You have already seen one important label use earlier in the Service section. The `echo-service` Service selected Pods with the label `app: echo`, which is how it knew that `echo-pod` was one of its backends.

You are also about to see labels again in the Deployment section. They are extremely common in normal Kubernetes usage, so it is worth getting into the habit of looking for them in YAML and command output.

```bash
kubectl get pods -n tutorial --show-labels
kubectl get pods -n tutorial -l app=echo
```

---

## 8. Deployments

A **Deployment** manages rollout for a stateless application.

A **stateless application** is one where an individual application instance does not hold the only copy of important long-term data inside its own process or filesystem. If the container restarts, another identical instance can usually take over.

Examples of stateless applications:

- nginx serving static files from an image or ConfigMap
- a C# API that stores durable data in SQL Server

Why is the C# API still considered stateless even though it works with durable data?

Because the durable data lives in **SQL Server**, not inside the API container itself. The API can be replaced, restarted, or scaled out, and another identical API replica can still serve requests as long as it can reach the database.

A container having a writable filesystem does **not** automatically make the workload stateful. What matters is whether that replica owns important durable data that must survive the replacement of that replica.

A stateful application, by contrast, keeps important durable state locally or depends on stable identity. SQL Server storing database files is the clearest stateful example in this tutorial.

A useful rule of thumb is:

- if you can replace one replica with another identical replica without losing the application's durable data, that part is usually **stateless**
- if the workload itself owns the durable storage or needs a stable identity, it is usually **stateful**

> **Contrast:** A Deployment can create Pods that mount storage, but that does not make Deployment the best mental model for every persistent workload. In this section, we use Deployments to learn rollout, replacement, and scaling with a clearly replaceable application. Later, [Persistent Volumes](#17-persistent-volumes) introduces durable storage, and the journal database shows what changes when part of the system is stateful.

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

What the important fields do:

- `replicas` — desired number of pod copies. If one pod disappears, the Deployment tries to bring the actual state back to this desired state.
- `selector.matchLabels` — tells the Deployment which pods belong to it. This must match the labels in the pod template.
- `template` — pod template used for each replica.
- `template.metadata.labels` — labels applied to every pod the Deployment creates. Services and other controllers often depend on these labels.
- `template.spec.containers` — describes the container or containers each replica should run.
- `ports.containerPort` — documents the port the application listens on inside the container.

A subtle but important point: the Deployment does not directly run containers. It manages a ReplicaSet, and the ReplicaSet creates Pods from the `template` section. That is why the `template` block is the heart of a Deployment manifest.

```bash
kubectl delete pod -n tutorial echo-pod --ignore-not-found
kubectl apply -n tutorial -f config/01-pods/deployment-echo.yaml
kubectl rollout status deployment/echo-deployment -n tutorial
kubectl scale deployment/echo-deployment -n tutorial --replicas=3
kubectl rollout status deployment/echo-deployment -n tutorial
```

What you should observe:

- the old standalone Pod is removed before the Deployment takes over
- the Deployment creates replacement Pods under ReplicaSet control
- after scaling, you should see three running replicas

A useful verification command is:

```bash
kubectl get pods -n tutorial -o wide
```

Example shape of output after scaling:

```text
NAME                               READY   STATUS    RESTARTS   AGE
echo-deployment-...                1/1     Running   0          ...
echo-deployment-...                1/1     Running   0          ...
echo-deployment-...                1/1     Running   0          ...
```

Because the Deployment reuses the label `app: echo`, the earlier `echo-service` Service can still target these new Pods. That is the important separation of concerns: the Service stays stable while the set of backend Pods changes underneath it.

Test that by forwarding the same Service again:

```bash
kubectl port-forward -n tutorial service/echo-service 8080:80
```

Leave that port-forward running in one terminal. In another terminal:

```bash
curl http://127.0.0.1:8080
```

If you are using WSL, you can also open a Windows browser to:

```text
http://localhost:8080
```

Expected response:

```text
hello from echo-deployment
```

This is the point where Kubernetes starts managing a desired replica count for you instead of just running a single unmanaged Pod, while clients can keep using the same stable Service endpoint.

---

## 9. kube-apiserver

The **kube-apiserver** is the front door to the cluster. `kubectl`, controllers, and other cluster components all interact with Kubernetes by talking to the API server.

```bash
kubectl api-resources | head -40
kubectl api-versions
kubectl config current-context
kubectl cluster-info
kubectl get deployment echo-deployment -n tutorial -o yaml
```

---

## 10. Nodes and kubelet

A **node** is a machine that runs workloads. In minikube, you typically have one node. The **kubelet** is the agent on that node that makes sure the assigned containers actually run.

```bash
kubectl get nodes -o wide
kubectl describe node minikube
kubectl get pods -n kube-system -o wide
```

---

## 11. etcd

**etcd** is the key-value store that holds cluster state. When you create a namespace, secret, deployment, or service, the desired state is stored through the API server and backed by etcd.

```bash
kubectl get pods -n kube-system
```

Look for an `etcd-*` pod in the control plane.

---

## 12. metrics-server and `kubectl top`

Earlier, the tutorial enabled the `metrics-server` addon. This is where it becomes useful.

The metrics-server collects resource-usage data from the cluster and makes it available through the Kubernetes metrics APIs. The most common way you will notice it is through the `kubectl top` commands.

Small mental model:

```text
node / kubelet metrics
        |
        v
   metrics-server
        |
        v
    Kubernetes metrics API
        |
        v
     kubectl top
```

Why this matters in this tutorial:

- it gives you a way to inspect actual CPU and memory usage
- it helps make `requests` and `limits` feel concrete instead of decorative
- it gives you another way to understand what your cluster is doing while workloads are running

### Verify that metrics-server is working

```bash
kubectl get pods -n kube-system
kubectl top nodes
kubectl top pods -n tutorial
```

What you should observe:

- `kubectl top nodes` should show CPU and memory usage for the minikube node
- `kubectl top pods -n tutorial` should show resource usage for Pods in your tutorial namespace once you have workloads running there

Example shape of output:

```text
NAME       CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
minikube   429m         10%    1903Mi          24%
```

```text
NAME                                 CPU(cores)   MEMORY(bytes)
static-nginx-...                     1m           6Mi
genkey-api-...                       2m           28Mi
journal-api-...                      5m           74Mi
journal-db-...                       98m          834Mi
```

### How to interpret what you are seeing

A few practical observations:

- a tiny nginx Pod will usually show very low CPU and memory usage
- the journal database typically uses much more memory than the simple frontend examples
- the numbers you see here are **current usage**, not the same thing as requested or limited resources in YAML

That distinction matters:

- **requests** tell Kubernetes what resources a Pod expects to need for scheduling
- **limits** tell Kubernetes the upper bound it may use before throttling or enforcement
- `kubectl top` shows what the workload is actually using right now

Those three ideas are related, but they are not interchangeable.

### Troubleshooting

- if `kubectl top` says metrics are not available yet, wait a minute and try again
- if you do not see tutorial Pods in `kubectl top pods -n tutorial`, make sure you have actually deployed workloads in the `tutorial` namespace first
- if the addon seems unhealthy, inspect `kube-system` Pods and look for a metrics-server Pod that is still starting or failing

---

## 13. Secrets

A **Secret** stores sensitive values such as passwords, tokens, and connection strings.

Conceptually, this section fits well after etcd because Secrets are Kubernetes objects too. They are stored as part of cluster state, even though they are handled separately from ordinary configuration data.

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

Field intent:

- `type: Opaque` — generic Secret type.
- `stringData` — convenient plaintext input that Kubernetes converts into the stored Secret form.

We will use Secrets for SQL Server credentials later in the tutorial.

---

## 13. ConfigMaps

A **ConfigMap** stores non-secret configuration data.

Typical ConfigMap use cases:

- small application config files
- environment-specific settings
- small static content for simple demonstrations

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

Field intent:

- `data` — key/value content stored in the ConfigMap.
- multiline entries under `data` are useful when storing small files.

We will first use ConfigMaps for a static web page because they are very easy to inspect and teach. Later we will contrast that with building frontend assets into an image.

---

## 14. Static nginx web page using a ConfigMap

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

**Why use a ConfigMap here?**

Because it is a great teaching tool:

- you can see the HTML directly in YAML
- you can mount the content into nginx without building an image
- it shows how Kubernetes can inject files into a container at runtime

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

Pay attention to these fields:

- `ConfigMap.data.index.html` — stores the page content.
- `Deployment.spec.selector.matchLabels` — tells the Deployment which Pods it owns.
- `template.metadata.labels` — labels that connect the Pod to both the Deployment and the Service.
- `containers.image` — the nginx image that will serve the mounted file.
- `volumeMounts.mountPath` — where the file appears inside the container filesystem.
- `volumeMounts.subPath` — mounts just one file from the ConfigMap to the nginx document root instead of mounting the entire ConfigMap directory there.
- `volumes.configMap.name` — connects the pod to the ConfigMap.
- `Service.spec.selector` — tells the Service which Pods should receive traffic.

This example is useful because it shows three different layers working together:

1. a ConfigMap stores content
2. a Deployment runs nginx and mounts that content
3. a Service gives you a stable way to reach the nginx Pod

```bash
kubectl apply -f config/02-static-nginx/static-site.yaml
kubectl port-forward -n tutorial service/static-nginx 8080:80
```

In another terminal, request the page directly:

```bash
curl http://127.0.0.1:8080
```

What you should observe:

- the Deployment and Service should be created
- the forwarded request should return HTML from nginx
- the page content should match the HTML stored in the ConfigMap

Expected response:

```html
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
```

This is your first example of Kubernetes injecting file content into a container at runtime.

Troubleshooting:

- if the page does not load, check `kubectl get pods -n tutorial` and make sure `static-nginx` is `Running`
- if nginx is running but the page content is wrong, inspect the mounted ConfigMap with `kubectl get configmap static-site-content -n tutorial -o yaml`
- if port-forward fails, confirm the Service exists with `kubectl get svc -n tutorial`

---

## 15. Basic Flask `/genkey` service behind nginx

This stage introduces a reverse proxy and service-to-service routing.

Architecture:

- `genkey-basic-api` — Flask app serving `/genkey`
- `genkey-basic-proxy` — nginx reverse proxy

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

Leave that port-forward running in the first terminal. In a second terminal, call the proxied API:

```bash
curl http://127.0.0.1:8081/genkey
```

What you should observe:

- both the API Deployment and nginx proxy Deployment should become available
- the response should be JSON rather than plain text or HTML
- the JSON should contain generated SSH key material

Expected response shape:

```json
{
  "privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----...",
  "publicKey": "ssh-ed25519 AAAA..."
}
```

This stage matters because it shows:

- Service-to-Service communication by DNS name
- nginx acting as a reverse proxy inside the cluster
- container image build and local deployment

Troubleshooting:

- if the API pod is stuck in `ImagePullBackOff`, the image probably was not built into minikube successfully; rebuild it and recheck the Deployment
- if `/genkey` returns an nginx error instead of JSON, inspect both the proxy pod logs and the API pod logs
- if the API is running but key generation fails, check the container logs for `ssh-keygen`-related errors

---

## 16. Richer frontend: built image instead of ConfigMap assets

Now we revisit frontend delivery with a better packaging model.

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

Earlier, the ConfigMap-mounted static site was useful because it taught ConfigMaps clearly. But for a richer frontend application, packaging the frontend into an image is a better pattern.

### Why a built image is better here

**ConfigMap-mounted assets**
- simple for tiny examples
- easy to inspect
- good for teaching ConfigMaps
- awkward for larger frontends
- not a normal packaging strategy for serious UI deployments

**Built frontend image**
- versioned artifact
- cleaner deployment manifests
- source tree matches what actually runs
- better reproducibility
- more realistic operational model

### Build the React frontend image and Flask backend image

```bash
cd src/04-genkey-full/backend
minikube image build -t genkey-api:0.1.0 .
cd ..
minikube image build -f Dockerfile.frontend -t genkey-web:0.1.0 .
cd ../..
```

Apply the image-based manifests:

```bash
kubectl apply -f config/04-genkey-full/image-based/
kubectl port-forward -n tutorial service/genkey-web 8082:80
```

Leave that port-forward running in the first terminal.

Open:

- `http://127.0.0.1:8082/genkey/`

In a second terminal, you can also verify the proxied API path through the frontend entrypoint:

```bash
curl http://127.0.0.1:8082/genkey/api
```

What you should observe:

- `/genkey/` should return HTML for the frontend shell
- `/genkey/api` should return JSON with generated key material
- the nginx frontend image is now serving the UI and proxying API requests to the backend Service

Expected response shapes:

```html
<!doctype html>
<html lang="en">
  <head>
    <title>GenKey UI</title>
    ...
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
```

```json
{
  "algorithm": "ed25519",
  "publicKey": "ssh-ed25519 AAAA...",
  "privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----..."
}
```

At this point you have seen both patterns:

1. ConfigMap-mounted static files
2. built frontend image

The tutorial uses both on purpose so the reader understands the difference.

Troubleshooting:

- if `genkey-web` enters `ImagePullBackOff`, the frontend image likely was not built with the correct working directory or Dockerfile path
- the working build command used in verification was:

```bash
cd src/04-genkey-full
minikube image build -f Dockerfile.frontend -t genkey-web:0.1.0 .
```

- if `/genkey/` loads but `/genkey/api` returns 404, make sure you are testing through the frontend entrypoint and not calling the backend with the wrong path

---

## 17. Persistent Volumes

A **PersistentVolumeClaim** requests durable storage for a workload.

Earlier, the Deployments section focused on replaceable stateless replicas. Here we switch to the other side of the contrast: SQL Server is stateful because it owns durable database files that should survive Pod restarts and replacement.

We need this for SQL Server because the journal database is stateful and should survive pod restarts.

Example file: `config/05-journal/step1-startup-init/01-pvc.yaml`

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

Field intent:

- `metadata.name` — the claim name other Kubernetes objects will reference.
- `accessModes` — how the volume may be mounted. `ReadWriteOnce` means one node can mount it for read/write use at a time, which is a common fit for a single SQL Server instance.
- `resources.requests.storage` — requested storage size.

A PVC is a request, not the storage implementation itself. In minikube, a storage provisioner usually satisfies that request automatically and binds the claim to backing storage for you.

---

## 18. Journal application, first approach: schema init inside API startup

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

- SQL Server runs in the cluster
- the API starts with elevated DB privileges
- the API checks and creates the schema at startup
- the web frontend talks to the API through nginx

This is a very real pattern in small systems, and it is worth seeing first.

### Why show this approach first?

Because it is understandable and practical:

- fewer Kubernetes objects
- the schema logic is visible in the application itself
- easy to reason about as a first implementation

### Important limitation

This approach is **not optimal** because the API runtime now needs privileges that are broader than it needs for normal request handling.

It also creates a startup race:

- SQL Server may still be starting when the API tries to connect
- the API may fail on its first start if the database is not ready yet
- Kubernetes may restart the API pod until the database becomes reachable

That behavior is useful to observe because it shows one of the real operational drawbacks of schema creation during app startup.

### Build the journal API image

```bash
cd src/05-journal/api
minikube image build -t journal-api:0.1.0 .
cd ../../..
```

### Apply the first-step manifests in phases

Apply the Secret, persistent volume claim, database Deployment, and database Service first:

```bash
kubectl apply -f config/05-journal/step1-startup-init/00-secret.yaml
kubectl apply -f config/05-journal/step1-startup-init/01-pvc.yaml
kubectl apply -f config/05-journal/step1-startup-init/02-db-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/03-db-service.yaml
```

Now monitor SQL Server until it is actually ready:

```bash
kubectl get pods -n tutorial -w
kubectl rollout status deployment/journal-db -n tutorial
```

When you are satisfied that the database is up, apply the API and web resources:

```bash
kubectl apply -f config/05-journal/step1-startup-init/04-api-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/05-api-service.yaml
kubectl apply -f config/05-journal/step1-startup-init/06-web-assets-configmap.yaml
kubectl apply -f config/05-journal/step1-startup-init/07-web-nginx-configmap.yaml
kubectl apply -f config/05-journal/step1-startup-init/08-web-deployment.yaml
kubectl apply -f config/05-journal/step1-startup-init/09-web-service.yaml
```

### How to monitor this step safely

Watch the API pod and logs before moving on. Run these in separate terminals, because the first two commands keep streaming output:

```bash
kubectl get pods -n tutorial -w
kubectl logs -n tutorial -l app=journal-api --tail=100
kubectl rollout status deployment/journal-api -n tutorial
```

What can happen here:

- **best case**: SQL Server is ready in time, and the API starts cleanly
- **common race case**: the API starts too early, fails to connect, and restarts
- **continue only when** the `journal-api` Deployment reports successfully rolled out and the pod is `Running` and `Ready`

If the database became ready after the API had already failed several times, a manual restart is a simple way to continue cleanly:

```bash
kubectl rollout restart deployment/journal-api -n tutorial
kubectl rollout status deployment/journal-api -n tutorial
```

After the API is healthy, confirm it explicitly:

```bash
kubectl port-forward -n tutorial service/journal-api 8084:8080
```

Leave that port-forward running in one terminal. In another terminal:

```bash
curl http://127.0.0.1:8084/healthz
```

Expected healthy response:

```json
{"status":"ok","autoMigrate":true}
```

That `autoMigrate: true` value matters. It tells you that this first approach is still using API-startup schema management.

In another terminal, you can then expose the web frontend:

```bash
kubectl port-forward -n tutorial service/journal-web 8083:80
```

Open:

- `http://127.0.0.1:8083/journal/`

You can also confirm that the API can now write and read data:

```bash
curl -X POST http://127.0.0.1:8084/api/entries   -H 'Content-Type: application/json'   -d '{"title":"first entry","body":"created during startup-init verification"}'

curl http://127.0.0.1:8084/api/entries
```

Expected response shape:

```json
{"id":1}
```

```json
[
  {
    "id": 1,
    "title": "first entry",
    "body": "created during startup-init verification",
    "createdAt": "..."
  }
]
```

### Important YAML ideas in this step

The step 1 manifests are worth reading carefully because each object has a clear purpose:

- `00-secret.yaml`
  - stores the SQL Server `sa` password
  - stores the admin-capable connection string used by the API during schema creation
- `01-pvc.yaml`
  - requests durable storage for SQL Server data files
- `02-db-deployment.yaml`
  - runs the SQL Server container
  - uses environment variables from the Secret
  - mounts the PVC so database files survive Pod recreation
  - includes readiness and liveness probes so Kubernetes can tell when the database is actually serving
- `03-db-service.yaml`
  - gives SQL Server a stable in-cluster DNS name: `journal-db`
- `04-api-deployment.yaml`
  - runs the C# API
  - injects the admin connection string from the Secret
  - sets `Journal__AutoMigrate=true`, which is the key flag that turns startup schema creation on
- `05-api-service.yaml`
  - exposes the API on a stable ClusterIP Service
- `06-web-assets-configmap.yaml`
  - stores the simple journal frontend files
- `07-web-nginx-configmap.yaml`
  - stores the nginx configuration that serves `/journal/` and proxies `/journal/api/`
- `08-web-deployment.yaml`
  - runs nginx for the journal frontend
  - mounts both the web assets and the nginx config
- `09-web-service.yaml`
  - gives the frontend a stable Service endpoint

### What this step is demonstrating

- Secrets carrying SQL credentials
- PVC-backed SQL Server storage
- application-driven schema bootstrap
- nginx serving the journal UI and proxying `/journal/api/`
- how startup ordering problems appear in real clusters

### Why this is not the end state

Startup-based schema creation mixes deployment concerns into the API runtime:

- the API needs elevated privileges
- startup behavior becomes more complex
- multiple replicas can complicate initialization workflows
- database bootstrap and request serving are different operational concerns
- the database readiness race becomes part of normal application startup

That leads directly to the improved approach in the next section.

---

## 19. Journal application, improved approach: dedicated database-init Job

Now we split schema initialization away from the API.

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

In this version:

- SQL Server still starts with persistent storage
- a dedicated **Job** initializes the database schema
- the Job also creates a less-privileged application login
- the API runs with the application login instead of elevated schema-management privileges

### Why this approach is better

**Startup init inside API**
- simpler first implementation
- fewer cluster objects
- easier for a first pass
- but mixes bootstrap and runtime responsibilities
- and gives the API broader DB privileges than it should need

**Dedicated Job**
- clearer separation of concerns
- easier to observe and debug independently
- better security posture
- better cluster deployment strategy
- better teaching example for real Kubernetes workflows

The key conceptual difference is this:

- startup-init treats schema management as part of the application's normal boot path
- Job-based init treats schema management as a separate cluster task with its own lifecycle

That separation is usually healthier. It makes failures easier to locate, limits privileges in the steady-state API, and better matches how Kubernetes wants you to model one-time setup work.

### Apply the improved manifests

If you already ran the startup-init version in this same namespace, remove it before applying the improved version. This avoids in-place replacement races where a second SQL Server pod briefly tries to start against the same PVC.

```bash
kubectl delete -f config/05-journal/step1-startup-init/
```

Now apply the improved manifests:

```bash
kubectl apply -f config/05-journal/step2-job-init/
kubectl get pods,jobs -n tutorial
kubectl wait --for=condition=complete job/journal-db-init -n tutorial --timeout=600s
kubectl logs -n tutorial job/journal-db-init
kubectl port-forward -n tutorial service/journal-web 8084:80
```

What you should observe:

- the SQL Server Deployment should become available
- the `journal-db-init` Job should move to `Complete`
- the API should start with `autoMigrate` disabled because schema management has been separated out

Leave the journal web port-forward running in its own terminal.

A useful direct health check is:

```bash
kubectl port-forward -n tutorial service/journal-api 8085:8080
```

In another terminal:

```bash
curl http://127.0.0.1:8085/healthz
```

Expected healthy response:

```json
{"status":"ok","autoMigrate":false}
```

You can also verify end-to-end CRUD behavior:

```bash
curl -X POST http://127.0.0.1:8085/api/entries   -H 'Content-Type: application/json'   -d '{"title":"job init entry","body":"created during job-init verification"}'

curl http://127.0.0.1:8085/api/entries
```

Open:

- `http://127.0.0.1:8084/journal/`

### Important YAML ideas in this step

The step 2 manifests are similar to step 1, but the differences matter a lot:

- `00-secret.yaml`
  - still stores the `sa` password
  - now also stores the application user's password and the lower-privilege application connection string
- `01-pvc.yaml`
  - still requests durable SQL Server storage
- `02-db-deployment.yaml` and `03-db-service.yaml`
  - still run and expose SQL Server in the cluster
- `04-schema-configmap.yaml`
  - stores the SQL initialization script template that creates the database schema and lower-privilege login
- `05-db-init-job.yaml`
  - runs once instead of living forever like a Deployment
  - waits for SQL Server to become reachable
  - renders the SQL template with Secret-backed values
  - applies schema setup separately from the API lifecycle
- `06-api-deployment.yaml`
  - runs the same API image as before
  - now uses the application connection string instead of the admin one
  - sets `Journal__AutoMigrate=false`, which is the key sign that schema creation is no longer part of normal API startup
- `07-api-service.yaml`, `08-web-assets-configmap.yaml`, `09-web-nginx-configmap.yaml`, `10-web-deployment.yaml`, and `11-web-service.yaml`
  - serve the same frontend role as in step 1

When comparing step 1 and step 2 YAML, the most important lesson is not just that there is a Job now. It is that the API manifest itself has become simpler and safer because database bootstrap logic moved out of it.

### What the improved step teaches

- Jobs as one-time cluster tasks
- privilege separation between schema management and normal app runtime
- a more maintainable deployment model for stateful applications

Troubleshooting:

- if the Job does not complete, inspect it with `kubectl describe job journal-db-init -n tutorial` and read its logs with `kubectl logs job/journal-db-init -n tutorial`
- if the API fails after the Job completed, verify that the Secret-backed application connection string matches the login created by the initialization script
- if the web UI loads but no data operations work, check the API pod logs rather than the web pod first

---

## 20. RBAC

**RBAC** controls who can do what in Kubernetes.

This is where namespaces become especially important. In everyday Kubernetes usage, namespaces are one of the main boundaries used to control access. A common pattern is not "can this user touch the cluster?" but rather "what can this user do inside this namespace?"

That is why this example uses a `Role` and `RoleBinding` in the `tutorial` namespace instead of jumping straight to cluster-wide permissions. It demonstrates the more common and safer pattern: grant only the permissions needed, and grant them only in the namespace where they are needed.

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

Important field explanations:

- `ServiceAccount` — an identity for workloads or API clients inside the cluster.
- `Role` — a namespace-scoped permission set.
  - this namespace scoping is a big deal: a `Role` in `tutorial` does not automatically grant the same access in `default`, `kube-system`, or any other namespace
- `rules[].apiGroups` — selects which API groups the rule applies to. `""` means the core API group.
- `rules[].resources` — which resource types may be accessed.
- `rules[].verbs` — which actions are allowed.
- `RoleBinding` — connects a subject, such as a ServiceAccount, to a Role.
- `subjects[]` — the identity receiving the permissions.
- `roleRef` — the Role being granted.

```bash
kubectl apply -f config/05-journal/12-rbac-readonly.yaml
kubectl auth can-i list pods --as=system:serviceaccount:tutorial:tutorial-reader -n tutorial
kubectl auth can-i create deployments --as=system:serviceaccount:tutorial:tutorial-reader -n tutorial || true
```

The second command should print `no`. The `|| true` keeps that expected denial from looking like a shell-script failure.

That expected `no` is part of the lesson: the identity has read-only access in the `tutorial` namespace, not broad write access across the cluster.

---

## 21. Ingress

Ingress is the main HTTP exposure strategy for the core tutorial because it is minikube-friendly and easy to enable with the ingress addon.

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
        |                 |
        v                 v
   genkey frontend     journal frontend
```

File: `config/05-journal/13-ingress.yaml`

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

Why this is the main path:

- easy to explain
- easy to enable in minikube
- sufficient for the tutorial’s HTTP routing goals

Important field explanations:

- `metadata.name` — the name of the Ingress object itself.
- `metadata.namespace` — places the Ingress in the same namespace as the backend Services it references.
- `spec.ingressClassName` — tells Kubernetes which ingress controller should implement this Ingress. Here it is the nginx ingress controller.
- `rules[].host` — the expected HTTP host header for these routes.
- `rules[].http.paths[].path` — the URL prefix to match.
- `pathType: Prefix` — tells the controller to treat `/genkey` and `/journal` as path prefixes rather than exact full-path matches.
- `backend.service.name` — the Service that should receive traffic for that path.
- `backend.service.port.number` — the Service port to send traffic to.

This manifest is doing path-based routing, not direct Pod routing. Ingress sends traffic to Services, and the Services then send traffic to Pods.

Apply it:

```bash
kubectl apply -f config/05-journal/13-ingress.yaml
kubectl get ingress -n tutorial
```

Expected `kubectl get ingress` shape:

```text
NAME               CLASS   HOSTS            ADDRESS   PORTS   AGE
tutorial-ingress   nginx   tutorial.local             80      ...
```

### Important note about testing Ingress on minikube

The Ingress resource describes routing rules, but the exact way you reach the ingress controller depends on how minikube exposes it in your environment.

In the live verification pass for this tutorial, the reliable test path was through the ingress controller's **NodePort** with the correct `Host` header.

Get the minikube IP and the controller's HTTP NodePort:

```bash
MINIKUBE_IP=$(minikube ip)
NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
echo "$MINIKUBE_IP"
echo "$NODEPORT"
```

Then test the routes with the expected host header:

```bash
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/genkey/"
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/genkey/api"
curl -H 'Host: tutorial.local' "http://$MINIKUBE_IP:$NODEPORT/journal/"
```

Expected response shapes:

- `/genkey/` returns the frontend HTML shell with `<title>GenKey UI</title>`
- `/genkey/api` returns JSON with `algorithm`, `publicKey`, and `privateKey`
- `/journal/` returns the journal frontend HTML shell with `<title>Journal App</title>`

This is the final proof that a single ingress entrypoint can route to multiple backend Services by path.

### What can go wrong

If you instead try something like this:

```bash
curl -H 'Host: tutorial.local' "http://$(minikube ip)/genkey/"
```

you may get a default `404 Not Found` response depending on how the ingress controller is exposed in your local environment.

That does **not** necessarily mean your Ingress object is wrong. It may only mean you are reaching the wrong port or exposure path.

### How to confirm whether Ingress itself is healthy

```bash
kubectl describe ingress tutorial-ingress -n tutorial
kubectl get svc -n ingress-nginx
kubectl get endpoints -n tutorial genkey-web journal-web
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100
```

If the Ingress describes the expected rules and the backend Services have endpoints, the next thing to check is usually **how** you are reaching the ingress controller, not the YAML itself.

Troubleshooting summary:

- `404 Not Found` from nginx can mean you reached the ingress controller on the wrong port, not that the Ingress rule is invalid
- missing endpoints usually means the backend Service selectors do not currently match healthy Pods
- if the ingress controller is not ready, wait for the addon to finish creating the controller Pod before testing routes

---

## 22. Advanced topics: Gateway and alternatives to Ingress

The main tutorial intentionally stays with Ingress. But there are more advanced options worth considering after the core lessons are complete.

See:

- `config/advanced/gateway-options.md`

Summary of options:

### NGINX Gateway Fabric
- Benefits: familiar nginx ecosystem, natural follow-on from Ingress.
- Limitations: extra install and controller setup.

### Envoy Gateway
- Benefits: strong modern Gateway API story, good long-term relevance.
- Limitations: heavier than the basic tutorial path.

### Cilium Gateway API
- Benefits: powerful if you also want to learn deeper networking.
- Limitations: adds a lot of extra surface area.

### Istio Gateway API support
- Benefits: very capable traffic management.
- Limitations: too much overhead for the core minikube tutorial.

### Recommendation

Keep the main tutorial on **Ingress**.

If you later want one advanced Gateway-focused extension, the best first options are:

1. **NGINX Gateway Fabric**
2. **Envoy Gateway**

---

## 23. What is already ready for polish later

This version is meant to have the right **structure** and **teaching contrasts** first.

During the polish phase, the highest-value upgrades will be:

- expected command output gathered from actually running the steps
- stronger explanations after each YAML block
- diagrams or request-flow sketches
- better “what you should observe now” callouts
- screenshots if desired
- deeper explanations of each Kubernetes field where helpful

