# Part 1. Infrastructure and kubectl

This part gives you a first look at the core infrastructure that makes Kubernetes work, along with the fundamental commands you'll use throughout the tutorial. It matters because the rest of the tutorial assumes you have a functioning Kubernetes environment and at least a basic mental model of the control plane, nodes, and cluster services.

**Prerequisite:** You should have already set up your local cluster using **[Part 0. Cluster Setup](00-cluster-setup.md)** (either Docker Desktop with Kubernetes or Minikube).

## 1.1 Fundamental kubectl commands

Kubernetes is declarative: you tell it what you want, and it works toward that goal. The commands in this section are your primary interface to the cluster—reading state, understanding details, declaring changes, viewing output, removing resources, and debugging issues.

### 1.1.1 kubectl get: Reading cluster state

`kubectl get` is the most fundamental command for understanding what's running in your cluster. It reads the current state of objects from the API server and displays it in a human-readable form.

**Why this matters:**

- Kubernetes is declarative—you tell it what you want, and it works toward that goal
- `kubectl get` lets you observe the actual state and compare it to your intentions
- Almost every troubleshooting workflow starts with `kubectl get` to see what exists
- You'll use this command constantly: checking Pods, Services, Deployments, and more

Ask the API server for a live object in YAML form:

```bash
kubectl get nodes -o yaml | head -40
```

What this shows:

- real object data returned by the API server right now
- not just a short table, but structured cluster state in YAML form

Why this matters:

- it helps connect the idea of "Kubernetes objects" to the actual data the API server stores and returns
- later in the tutorial, you will create your own objects and inspect them in the same way

Full YAML output can become very large very quickly. `kubectl` has built-in output filtering options that let you pull out just the fields you care about.

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

**Machine-readable output with jq and yq:**

The `-o json` and `-o yaml` options produce structured output that's even more powerful when combined with dedicated parsing tools. While `jsonpath` works for simple cases, tools like `jq` (for JSON) and `yq` (for YAML) offer more expressive querying capabilities.

Get node names as JSON, then filter with jq:

```bash
kubectl get nodes -o json | jq -r '.items[].metadata.name'
```

Extract multiple fields using jq's built-in formatting:

```bash
kubectl get nodes -o json | jq -r '.items[] | [.metadata.name, .status.addresses[0].address] | @tsv'
```

Find all nodes that are marked as ready:

```bash
kubectl get nodes -o json | jq '.items[] | select(.status.conditions[].reason == "KubeletReady") | .metadata.name'
```

**PowerShell:** Escape the inner double quotes:

```powershell
kubectl get nodes -o json | jq '.items[] | select(.status.conditions[].reason == \"KubeletReady\") | .metadata.name'
```

Get pod names with their restart counts using array formatting:

```bash
kubectl get pods -A -o json | jq -r '.items[] | [.metadata.namespace, .metadata.name, .status.containerStatuses[0].restartCount] | @tsv'
```

Using yq for YAML filtering:

```bash
kubectl get nodes -o yaml | yq eval '.items[].metadata.name' -
```

**Why this approach is useful:**

- JSON and YAML are structured formats and these parsing tools understand the defined hierarchy
- `jq` and `yq` have powerful filtering, sorting, and transformation capabilities
- You can build complex queries that would be difficult or impossible with `jsonpath`
- These skills transfer to any tool that outputs JSON or YAML, not just kubectl

Installing `jq` and `yq` is not necessary for the tutorial. Both are widely used in production environments and a quick web search will find installation instructions if you want to explore them.

Common `kubectl get` patterns you'll use throughout the tutorial:

```bash
kubectl get pods                    # List pods in default namespace
kubectl get pods -n <namespace>     # List pods in specific namespace
kubectl get services                # List all services
kubectl get all                     # List all common resource types
kubectl get -f <file.yaml>          # Show objects defined in a file
```

### 1.1.2 kubectl describe: Understanding object details

`kubectl describe` gives you detailed information about a specific object. While `kubectl get` shows a high-level summary, `kubectl describe` provides the full story including status, events, and configuration.

**Why this matters:**

- When something isn't working, `describe` is often your first diagnostic tool
- It shows recent events that explain what happened to an object
- You can see labels, annotations, and other metadata not shown in `get` output
- Understanding why a Pod is pending, crashing, or failing usually starts here

The basic pattern:

```bash
kubectl describe <resource-type> <object-name>
```

Common describe patterns:

```bash
kubectl describe node <node-name>           # Detailed node information
kubectl describe pod <pod-name>             # Pod status, events, and configuration
kubectl describe service <service-name>     # Service endpoints and configuration
kubectl describe deployment <deployment-name>  # Deployment status and replica information
```

What `describe` shows that `get` does not:

- **Events** - A chronological log of what happened to the object (scheduling, pulling images, crashes, restarts)
- **Detailed status** - Current phase, conditions, and state transitions
- **Full configuration** - All labels, annotations, and spec details
- **Related resources** - For Services: endpoints; for Deployments: replica status

When troubleshooting, the workflow is often:

1. `kubectl get pods` - See what's running (or not running)
2. `kubectl describe pod <name>` - Understand why a Pod is in its current state
3. `kubectl logs <pod-name>` - Read the application's own output

This progression from summary to detail to logs is a core Kubernetes troubleshooting pattern.

### 1.1.3 kubectl logs: Viewing container output

`kubectl logs` displays the output from containers running in your Pods. This is your window into what your applications are actually doing—or why they're failing.

**Why this matters:**

- When a Pod crashes or behaves unexpectedly, the application logs often explain why
- You can see startup errors, configuration issues, and runtime problems
- Logs are essential for debugging—there's no `print` statement debugging in a distributed system
- Combined with `get` and `describe`, logs complete the core troubleshooting triad

The basic pattern:

```bash
kubectl logs <pod-name>
```

Common logs patterns:

```bash
kubectl logs <pod-name>                    # Logs from a single-container pod
kubectl logs <pod-name> -c <container-name>  # Logs from a specific container (multi-container pod)
kubectl logs <pod-name> --tail=50          # Only the last 50 lines
kubectl logs <pod-name> --follow           # Stream logs in real-time (like tail -f)
kubectl logs -l app=<app-name>             # Logs from all pods with a label
kubectl logs <deployment-name> --tail=1    # Logs from the newest pod in a deployment
```

Viewing logs for a crashed Pod:

When a Pod restarts repeatedly, you often need to see the logs from the *previous* attempt:

```bash
kubectl logs <pod-name> --previous
```

This shows what happened before the container crashed and Kubernetes restarted it.

Streaming logs in real-time:

```bash
kubectl logs <pod-name> --follow
```

Use this when you want to watch startup behavior or see errors as they occur. Press Ctrl-C to stop following.

### 1.1.4 kubectl apply: Declaring desired state

`kubectl apply` is how you tell Kubernetes what you want to exist. It reads YAML manifests and sends them to the API server, which then works to make the actual cluster match your declared state.

**Why this matters:**

- This is the primary way you'll create and update resources in Kubernetes
- Unlike imperative commands (`kubectl run`, `kubectl expose`), `apply` is declarative
- You can store YAML in files, track them in git, and reproduce your infrastructure
- The same YAML works the same way every time—no subtle differences from command-line flags

The basic pattern:

```bash
kubectl apply -f <file-or-directory>
```

What happens when you run `kubectl apply`:

1. `kubectl` reads your YAML file(s)
2. It sends the object definitions to the API server
3. The API server validates and stores the desired state
4. Controllers (like the Deployment controller) notice the new objects and begin working
5. The cluster creates or updates resources to match your declaration

A simple example (you don't need to run this now):

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

This single command creates dozens of objects: Deployments, Services, ServiceAccounts, Roles, and more—all from one manifest.

**Extracting YAML from existing objects:**

You can retrieve the YAML definition of any object running in the cluster:

```bash
kubectl get <resource-type> <object-name> -o yaml
```

This is useful for:
- Understanding the full specification of an existing object
- Saving the current state before making changes
- Learning by examining working examples
- Migrating resources between clusters

Examples:

```bash
kubectl get pod my-pod -o yaml             # Get YAML for a specific pod
kubectl get deployment my-app -o yaml      # Get YAML for a deployment
kubectl get service web-service -o yaml     # Get YAML for a service
```

Note that the YAML returned by `kubectl get -o yaml` includes runtime-only fields that you wouldn't include in a source manifest. When reusing extracted YAML, you typically want to remove fields like `status`, `creationTimestamp`, `resourceVersion`, and `uid`.

**Cleaning YAML with kubectl-neat:**

The `kubectl-neat` tool automatically removes these runtime-only fields from YAML output. It transforms raw `kubectl get -o yaml` output into clean, source-control-ready YAML.

```bash
kubectl get pod my-pod -o yaml | kubectl neat
kubectl get deployment my-app -o yaml | kubectl neat
```

Installing `kubectl-neat` is not necessary for the tutorial. It's frequently used in production environments and available through common package managers if you want to explore it.

What `kubectl-neat` removes:

| Field | Reason to remove |
|-------|-----------------|
| `status` | Runtime state, computed from actual conditions |
| `metadata.creationTimestamp` | Automatically set when object is created |
| `metadata.resourceVersion` | Internal version tracking for optimistic concurrency |
| `metadata.uid` | Unique identifier assigned at creation |
| `managedFields` | Tracks which client modified which fields |

The cleaned YAML is suitable for saving to version control, using as a template, or migrating between environments.

### 1.1.5 kubectl delete: Removing resources

`kubectl delete` removes objects from the cluster. You'll use this throughout the tutorial to clean up exercises or remove resources that are no longer needed.

**Why this matters:**

- Clean up after experiments to keep your cluster manageable
- Remove broken resources before reapplying corrected manifests
- Delete entire namespaces to reset an application completely
- Understanding deletion helps you avoid accidentally removing production resources

The basic pattern:

```bash
kubectl delete <resource-type> <object-name>
```

Common delete patterns:

```bash
kubectl delete pod <pod-name>                          # Delete a specific pod
kubectl delete -f <file.yaml>                          # Delete everything defined in a file
kubectl delete -f <directory>/                         # Delete everything in a directory
kubectl delete all --all -n <namespace>                # Delete all objects in a namespace
kubectl delete namespace <namespace-name>              # Delete an entire namespace (careful!)
```

Deletion behavior by resource type:

- **Pods** are deleted immediately, though termination takes time to complete
- **Services** are deleted immediately, stopping routing to Pods
- **Deployments** are deleted, but the Pods they manage are terminated according to the deployment's shutdown behavior
- **Namespaces** delete everything inside them, but this can take time for resources with finalizers

Cascading deletion:

Some resources own other resources. When you delete a Deployment, Kubernetes can delete the Pods it manages. This is controlled by the `--cascade` flag:

```bash
kubectl delete deployment <name> --cascade=orphan  # Delete deployment but leave pods alone
kubectl delete deployment <name>                    # Default: delete deployment and managed pods
```

Force deletion (use with caution):

Sometimes a resource gets stuck and won't delete normally. You can force deletion:

```bash
kubectl delete pod <pod-name> --force --grace-period=0
```

This bypasses graceful shutdown and immediately removes the object from the API server. Use only when normal deletion fails.

### 1.1.6 kubectl exec: Running commands in containers

`kubectl exec` lets you run commands inside a running container. This is invaluable for debugging, inspecting the container environment, or running ad-hoc tools.

**Why this matters:**

- Verify your application's runtime environment (env vars, mounted files, network)
- Run diagnostic tools without rebuilding your container image
- Access shell or REPL tools for interactive debugging
- Test commands from within the cluster's network context

The basic pattern:

```bash
kubectl exec <pod-name> -- <command>
```

Common exec patterns:

```bash
kubectl exec <pod-name> -- ls /app              # List files in /app directory
kubectl exec <pod-name> -- env                  # Print environment variables
kubectl exec <pod-name> -- ps aux               # Show running processes
kubectl exec <pod-name> -- cat /config/file.yml # View a config file
kubectl exec <pod-name> -- curl localhost:8080  # Test HTTP endpoint from within pod
```

Interactive shell access:

For debugging, you often want an interactive shell inside the container:

```bash
kubectl exec <pod-name> --it -- /bin/bash       # Interactive bash shell
kubectl exec <pod-name> --it -- /bin/sh         # Interactive sh (for alpine/minimal images)
kubectl exec <pod-name> --it -- /bin/sh         # Try sh if bash isn't available
```

The `--it` flags combine `-i` (interactive, keep STDIN open) and `-t` (TTY, allocate a terminal). You'll need both for an interactive shell.

Multi-container Pods:

When a Pod has multiple containers, specify which one you want to exec into:

```bash
kubectl exec <pod-name> -c <container-name> -- /bin/bash
kubectl exec <pod-name> -c <sidecar> -- env
```

Without `-c`, kubectl execs into the first container in the Pod spec.

Debugging tips with exec:

**Check what's actually in the container:**

```bash
kubectl exec <pod-name> -- ls -la /              # Filesystem at root
kubectl exec <pod-name> -- which curl            # Is curl installed?
kubectl exec <pod-name> -- env | grep DATABASE   # Did the DATABASE_URL env var get set?
```

**Test network connectivity from within the cluster:**

```bash
kubectl exec <pod-name> -- curl -s http://service-name:8080/healthz
kubectl exec <pod-name> -- nslookup kubernetes.default.svc.cluster.local
```

**Verify volumes are mounted:**

```bash
kubectl exec <pod-name> -- ls -la /config         # ConfigMap volume?
kubectl exec <pod-name> -- mount | grep config    # All mounts
```

**Important limitations:**

- `kubectl exec` requires the container to be running. It won't work on crashed or pending Pods
- Some minimal containers don't include a shell at all—nothing to exec into
- The shell environment may be limited (no vim, limited command set)
- Changes made via exec are ephemeral—they disappear if the Pod restarts

## 1.2 Fundamental cluster components

Now that you understand the core kubectl commands, let's look at the infrastructure components those commands interact with. These are the pieces that make Kubernetes work: the API server that receives your requests, the nodes that run your containers, the storage that remembers everything, and the monitoring that tells you what's happening.

### 1.2.1 The cluster and the API server

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

The `kubectl config` command manages kubeconfig files, which store cluster connection information and authentication details. For more on managing multiple clusters and contexts, see **[Part 4, section 4.9: kubectl config and managing multiple clusters](04-advanced-cluster-usage.md#4.9-kubectl-config-and-managing-multiple-clusters)**.

Check the main cluster endpoints:

```bash
kubectl cluster-info
```

What this shows:

- the main control-plane and service endpoints for the current cluster

Why this matters:

- it is one of the quickest ways to confirm that the API server is reachable

### 1.2.2 Namespaces and setting the default namespace

A **namespace** groups resources so you can separate environments and reduce clutter.

Namespaces matter because they let you organize work by application, team, or environment. They also help limit the scope of your queries—instead of seeing every object in the cluster, you can focus on the resources that belong to a particular project.

**Important note about namespace configuration:**

Setting a default namespace is a **local configuration setting** stored in your kubeconfig file. This setting persists between sessions and across terminal windows. Once you set the default namespace to `tutorial`, that preference sticks until you explicitly change it again.

File: `config/01-pods/namespace-tutorial.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tutorial
```

What is new here:

- `kind: Namespace` creates a separate logical space inside the cluster
- `metadata.name: tutorial` names that namespace `tutorial`
- resources created in this namespace are kept separate from resources in `default` and other namespaces

Create the namespace:

```bash
kubectl apply -f config/01-pods/namespace-tutorial.yaml
```

List all namespaces in the cluster:

```bash
kubectl get namespaces
```

You will usually see several namespaces that already exist before you create your own.

Common namespaces to recognize:

- `default`
  - the default namespace for namespaced resources when you do not specify a different one
- `kube-system`
  - used for core Kubernetes system components such as DNS, control-plane helpers, and addon-related system Pods
- `kube-public`
  - a special namespace traditionally used for cluster information that may be readable by all users
- `kube-node-lease`
  - used for node lease objects that help Kubernetes track node heartbeats efficiently
- `ingress-nginx`
  - commonly created when the NGINX ingress addon or controller is installed; it contains the ingress controller resources rather than your application workloads

The important idea is that not every namespace is meant for application code. Some exist so Kubernetes and its addons can organize their own components separately from user workloads.

Set the current context to default to the `tutorial` namespace:

```bash
kubectl config set-context --current --namespace=tutorial
```

Verify the effect:

```bash
kubectl config view --minify
kubectl get pods
```

What these commands show:

- `kubectl config view --minify` displays the current context's cluster, user, and namespace settings
- `--minify` tells kubectl to show only the configuration associated with the current context instead of dumping every cluster, user, and context in the kubeconfig file
- `kubectl get pods` now lists Pods in the `tutorial` namespace by default, without needing `-n tutorial`

From this point forward, most tutorial examples will use the `tutorial` namespace by default. If you need to work in a different namespace, you can either:

- use the `-n <namespace>` flag with kubectl commands
- run `kubectl config set-context --current --namespace=<other-namespace>` to change your default

### 1.2.3 Cluster nodes and the kubelet process

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

### 1.2.4 etcd: Cluster state storage

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

### 1.2.5 metrics-server: Resource monitoring

The **metrics-server** collects resource-usage data from the cluster and makes it available through the Kubernetes metrics APIs.

```bash
kubectl get pods -n kube-system
kubectl top nodes
```

Later, after you create workloads in the `tutorial` namespace, `kubectl top pods -n tutorial` becomes more interesting.
