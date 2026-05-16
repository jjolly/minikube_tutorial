# Part 2. Typical cluster functionality and usage

This part introduces the Kubernetes objects and behaviors that form the day-to-day grammar of cluster work: Pods, Services, Deployments, namespaces, labels, configuration, secrets, and persistent storage. It matters because these are the building blocks used again and again in the application examples later in the tutorial. The goal here is to make the reader comfortable with the common patterns before those patterns are combined into larger systems.

## 2.1 Pods

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

### 2.2 Run a short-lived BusyBox pod

This first Pod is meant to be temporary and easy to inspect.

The image used here is `busybox:1.36`, which is a very small Linux userspace image often used for demonstrations, debugging, and simple shell commands.

Before you run the command, one small timing note matters:

- the Pod's shell command will print a message immediately
- then it will **sleep for 15 seconds**
- during that sleep time, the Pod still exists and can be inspected
- after the sleep ends, the shell command exits and the Pod's main work is finished

That pause is intentional. It gives you a short window to look at the Pod while it is alive.

**Pull the image first:**

In some cluster configurations, images may not pull automatically. To ensure the image is available locally before creating the Pod, pull it with your container runtime:

```bash
docker pull busybox:1.36
```

This step isn't strictly required in all environments, but it prevents the Pod from getting stuck in an `ImagePullBackOff` state while the image is being downloaded.

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

View detailed Pod information:

```bash
kubectl describe pod bb-demo
```

What `describe` shows that `get` does not:

- **Events** - A chronological log of what happened: when the Pod was scheduled, when the container started, when it finished
- **State transitions** - How the Pod moved from `Pending` to `Running` to `Succeeded`
- **Node information** - Which node the Pod was assigned to (useful in multi-node clusters)
- **Resource requests** - CPU and memory requested (if specified)
- **Labels and annotations** - Metadata attached to the Pod for organization and configuration
- **Restart count** - How many times the container has restarted (useful for debugging crashes)

The Events section is particularly valuable for troubleshooting. It tells the story of your Pod's life: was the image pulled successfully? Did the container start? Why did it fail? When you're debugging why something isn't working, `kubectl describe` is often more helpful than `kubectl get` because it shows what actually happened, not just the current state.

### Clean up

```bash
kubectl delete pod bb-demo
```

Why delete it if it may already be finished?

Because a finished Pod can still remain as a cluster object until you remove it. Deleting it keeps the tutorial environment tidy before moving on.

### 2.3 Create long-running Pods from YAML

The previous example created a short-lived Pod directly from the command line. This next section moves to a more typical Kubernetes workflow: define a Pod in YAML, apply it, and inspect the object Kubernetes creates.

To keep the learning curve reasonable, this section now uses **two Pod examples**:

1. a very simple YAML Pod
2. a slightly richer Pod that can report its own identity

The first keeps the YAML easy to read. The second sets up a more interesting response for the Service and Deployment sections that follow.

### 2.4 Simple YAML Pod first

Start with the simplest version.

File: `config/01-pods/pod-simple-echo.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: simple-echo-pod
  labels:
    app: simple-echo
spec:
  containers:
    - name: echo
      image: hashicorp/http-echo:1.0.0
      args:
        - "-text=hello from simple-echo-pod"
      ports:
        - containerPort: 5678
```

Apply the manifest:

```bash
kubectl apply -f config/01-pods/pod-simple-echo.yaml
```

What just happened:

- Kubernetes received the Pod definition from the YAML file
- it created a Pod object named `simple-echo-pod`
- the node then started a container from the `hashicorp/http-echo:1.0.0` image
- that container runs a tiny HTTP server which replies with the exact text you supplied in `args`

List the Pods:

```bash
kubectl get pods -o wide
```

Why this is a separate step:

- it lets you see whether the Pod is still starting or already running
- the `-o wide` output also shows extra details such as the Pod IP and the node it landed on

Describe the Pod in detail:

```bash
kubectl describe pod simple-echo-pod
```

Why this is useful:

- `describe` gives much more detail than `get`
- it is one of the first commands to use when a Pod does not behave the way you expect
- the `Events` section near the bottom is especially useful for startup and scheduling problems

Test the Pod from inside the cluster:

```bash
POD_IP=$(kubectl get pod simple-echo-pod -o jsonpath='{.status.podIP}')
kubectl run netshoot-pod-check --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc "curl -fsS http://$POD_IP:5678"
```

**PowerShell:**

```powershell
$POD_IP = kubectl get pod simple-echo-pod -o jsonpath='{.status.podIP}'
kubectl run netshoot-pod-check --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc "curl -fsS http://$($POD_IP):5678"
```

Why this is written as two commands:

- the first command asks Kubernetes for the Pod's current internal IP address
- the second command starts a temporary helper Pod and uses it to send an HTTP request to that IP from inside the cluster network

Why create `netshoot-pod-check` at all?

Because at this point in the tutorial, `simple-echo-pod` is only a Pod with an internal cluster IP. It is not yet behind a Service, and it is not automatically exposed to your host machine. The easiest way to prove that the Pod is really serving HTTP is to launch another temporary Pod **inside the cluster** and let that Pod act as the client.

Expected response:

```text
hello from simple-echo-pod
```

What just happened:

- Kubernetes started a short-lived helper Pod from the `nicolaka/netshoot` image
- that helper Pod ran `curl` against the internal IP of `simple-echo-pod`
- the request stayed inside the cluster network
- `simple-echo-pod` answered with the text configured in its container arguments
- the helper Pod was removed automatically afterward because of `--rm`

Small mental model:

```text
+------------------------------------------------------------------------+
|                               Kubernetes Node                          |
|                                                                        |
| +--------------------------+     HTTP GET      +---------------------+ |
| |      Kubernetes Pod      |  ---------------> |   Kubernetes Pod    | |
| |    netshoot-pod-check    |                   |   simple-echo-pod   | |
| |    netshoot container    |    hello from     | http-echo container | |
| | curl http://$POD_IP:5678 | <---------------  |     HTTP Server     | |
| +--------------------------+  simple-echo-pod  +---------------------+ |
+------------------------------------------------------------------------+
```

This is useful because it proves two things at once:

- the Pod is actually running an HTTP server
- Pods inside the cluster can talk to each other over the cluster network

### Clean up

```bash
kubectl delete pod simple-echo-pod
```

That keeps the first example self-contained before introducing the richer Pod used later.

### 2.5 Creating and observing Pods in different namespaces

You already learned about namespaces in **[Part 1, section 1.2.2: Namespaces and setting the default namespace](01-infrastructure-and-kubectl.md#1.2.2-namespaces-and-setting-the-default-namespace)**, and you set your default namespace to `tutorial`. This section shows how namespaces affect Pod creation and visibility.

Create a Pod in the `default` namespace:

```bash
kubectl run demo-default -n default --image=busybox:1.36 --restart=Never --command -- sh -c 'echo "hello from default namespace" && sleep 30'
```

List Pods in the `tutorial` namespace (your default):

```bash
kubectl get pods
```

List Pods in the `default` namespace:

```bash
kubectl get pods -n default
```

What this demonstrates:

- The Pod you created with `-n default` exists in the `default` namespace
- Your default context is still set to `tutorial`, so `kubectl get pods` without a namespace flag only shows Pods in `tutorial`
- The Pod in `default` is completely isolated from the `tutorial` namespace—it has a different name, different visibility, and no connection to your tutorial resources

Now create a Pod with the same name in the `tutorial` namespace:

```bash
kubectl run demo-default --image=busybox:1.36 --restart=Never --command -- sh -c 'echo "hello from tutorial namespace" && sleep 30'
```

List Pods in both namespaces:

```bash
kubectl get pods
kubectl get pods -n default
```

What this shows:

- Namespaces allow the same object name to exist in different namespaces
- Each Pod is completely separate from the other, even though they share the same name
- The `-n` flag lets you work with objects in any namespace, not just your default

Check the logs of each Pod to see the different messages:

```bash
kubectl logs demo-default
kubectl logs demo-default -n default
```

Expected output:

```text
hello from tutorial namespace       # from the tutorial namespace Pod
hello from default namespace        # from the default namespace Pod
```

This namespace isolation is important for several reasons:

- **Team separation**: Different teams can work in their own namespaces without naming conflicts
- **Environment separation**: Development, staging, and production can coexist in the same cluster
- **Resource isolation**: Resource quotas and policies can be applied per namespace
- **Visibility**: Users can be limited to seeing only specific namespaces

Clean up both Pods:

```bash
kubectl delete pod demo-default
kubectl delete pod demo-default -n default
```

### 2.6 A Pod that can identify itself

Now switch to the Pod that the rest of the tutorial will use.

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
      env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      args:
        - "-text=hello from $(POD_NAME) at $(POD_IP)"
      ports:
        - containerPort: 5678
```

What is new here:

- `env` defines environment variables named `POD_NAME` and `POD_IP`
- `valueFrom.fieldRef.fieldPath: metadata.name` tells Kubernetes to fill one variable with the Pod's own name
  - this `fieldRef` pattern is part of the Kubernetes **Downward API**, which lets a container learn selected information about the Pod it is running in
  - a few common `fieldPath` values worth knowing are:
    - `metadata.name`: the Pod's name
    - `metadata.namespace`: the namespace the Pod is running in
    - `spec.nodeName`: the node the Pod was scheduled onto
    - `status.podIP`: the Pod's internal cluster IP address
    - `metadata.labels['app']`: the value of a specific label, when present
    - `metadata.annotations['some-key']`: the value of a specific annotation, when present
  - the important idea is that Kubernetes can inject selected Pod metadata into the container environment without you hard-coding those values into the image
- `valueFrom.fieldRef.fieldPath: status.podIP` tells Kubernetes to fill another variable with the Pod's internal cluster IP address
- `args` now use Kubernetes variable expansion so `$(POD_NAME)` and `$(POD_IP)` are resolved without requiring a shell inside the image

This is a little more complicated than the first example, but it becomes very useful later because the response can reflect the actual Pod identity.

Apply the richer Pod manifest:

```bash
kubectl apply -f config/01-pods/pod-echo.yaml
kubectl wait --for=condition=Ready pod/echo-pod --timeout=120s
```

Why these are grouped together:

- the first command creates the Pod
- the second waits until it is actually ready before you test it

### 2.7 Small challenge

In section 2.4, you already used a temporary helper Pod to access a running HTTP Pod from inside the cluster.

Before reading further, see if you can adapt that earlier two-command pattern yourself so it reaches **`echo-pod`** instead of **`simple-echo-pod`**.

Hints:

- you still need the Pod's internal IP address
- you still need the helper Pod to `curl` that IP from inside the cluster
- only a small part of the earlier command sequence needs to change

If you want to try it on your own first, stop here for a moment.

A possible answer appears later in the exercise notes section in **Part 4, section 4.9**, so you can check your work there if needed.

That little exercise is worth doing because it reinforces that Kubernetes is not doing anything magical yet. At this point, you are still reaching one specific Pod by its IP, just as before.

### Clean up

```bash
kubectl delete pod echo-pod
```

That cleanup is intentional because the next sections rebuild the same idea using Services and then Deployments.

## 2.8 Multi-container Pods and sidecars

So far, every Pod in the tutorial has contained exactly one container. That is the most common beginner-friendly example, but Kubernetes Pods are allowed to run **more than one container**.

This only makes sense when the containers are **tightly coupled**. In practice, that means they need to share something important enough that they really belong together in one Pod:

- the same Pod IP address and network namespace
- the same mounted volumes
- the same basic lifecycle as one unit

If two pieces of software are independent enough that you would want to scale, restart, or deploy them separately, they usually should **not** be placed in the same Pod.

A classic example of a tightly coupled relationship is a **sidecar**. A sidecar container supports the main application container by doing something like:

- writing or transforming files
- shipping logs
- handling local proxy duties
- adapting data for another system

### 2.8.1 Sidecar example: one container writes, one serves

File: `config/01-pods/pod-sidecar-demo.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-demo
  labels:
    app: sidecar-demo
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports:
        - containerPort: 80
      volumeMounts:
        - name: shared-content
          mountPath: /usr/share/nginx/html
    - name: writer
      image: busybox:1.36
      command:
        - /bin/sh
        - -c
        - |
          while true; do
            printf '%s\n' \
              '<!doctype html>' \
              '<html lang="en">' \
              '  <head><meta charset="utf-8" /><title>sidecar demo</title></head>' \
              '  <body>' \
              '    <h1>Sidecar demo</h1>' \
              '    <p>This page was written by the writer sidecar and served by nginx.</p>' \
              '  </body>' \
              '</html>' \
              > /shared/index.html
            sleep 30
          done
      volumeMounts:
        - name: shared-content
          mountPath: /shared
  volumes:
    - name: shared-content
      emptyDir: {}
```

What is new here:

- `containers` now contains **two container definitions** instead of one
- `name: web` names the nginx container that serves the page
- `image: nginx:1.27-alpine` uses nginx as a lightweight web server
- `ports.containerPort: 80` declares the port nginx listens on inside the container
- `volumeMounts` appears for the first time and mounts shared storage into a container
- `mountPath: /usr/share/nginx/html` places that shared storage at nginx's default web root
- `name: writer` names the helper sidecar container
- `image: busybox:1.36` uses a small image to run a simple shell loop
- `command` overrides the container's default startup command
- the shell loop writes HTML into `/shared/index.html` every 30 seconds
- the second `volumeMounts` entry mounts the same shared storage into the writer container at `/shared`
- `volumes` defines storage available to the Pod as a whole
- `emptyDir: {}` creates temporary Pod-local storage that both containers can share for as long as the Pod exists
  - the empty YAML map indicates the use of default values for the `emptyDir` option
  - the map can contain options that modify how `emptyDir` is used, but this example does not need any of them

Apply it:

```bash
kubectl apply -f config/01-pods/pod-sidecar-demo.yaml
kubectl get pod sidecar-demo -o wide
kubectl describe pod sidecar-demo
```

What this demonstrates:

- the Pod still has **one Pod IP**, even though it has two containers inside it
- both containers share the same network namespace, so local networking is shared too
- both containers share the same `emptyDir` volume
- one container writes content to the shared volume, and the other serves that content over HTTP
- both containers belong to the same Pod lifecycle

One especially useful check is to access nginx from the **writer** container over `localhost`:

```bash
kubectl exec sidecar-demo -c writer -- wget -qO- http://127.0.0.1
```

Why this is interesting:

- `writer` is not the nginx container
- but it can still reach nginx over `127.0.0.1` because both containers share the Pod's network namespace

Test the Pod from inside the cluster:

```bash
POD_IP=$(kubectl get pod sidecar-demo -o jsonpath='{.status.podIP}')
kubectl run netshoot-sidecar-check --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc "curl -fsS http://$POD_IP"
```

**PowerShell:**

```powershell
$POD_IP = kubectl get pod sidecar-demo -o jsonpath='{.status.podIP}'
kubectl run netshoot-sidecar-check --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc "curl -fsS http://$($POD_IP)"
```

Expected response shape:

```html
<!doctype html>
<html lang="en">
  <head><meta charset="utf-8" /><title>sidecar demo</title></head>
  <body>
    <h1>Sidecar demo</h1>
    <p>This page was written by the writer sidecar and served by nginx.</p>
  </body>
</html>
```

A few especially important details to notice:

- Kubernetes reports the Pod IP, not a separate IP per container
- both containers can see the same shared files because they mount the same volume
- if you delete the Pod, both containers go away together

### Clean up

```bash
kubectl delete pod sidecar-demo
```

That is a big part of the design lesson here: a multi-container Pod is one lifecycle unit, not a tiny cluster hiding inside a Pod.

### 2.8.2 Another tightly coupled pattern

A sidecar is not the only multi-container pattern. Another common one is sometimes called an **ambassador** or local proxy pattern, where one container acts as a closely coupled local proxy for the main application.

The important point is not the name of the pattern. The important question is whether the containers truly belong together.

A useful rule of thumb is:

- if the containers must share the same network identity, volumes, and lifecycle, a multi-container Pod can make sense
- if the containers should scale independently, roll out independently, or fail independently, they usually belong in separate Pods

## 2.9 Services

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

What is new here:

- `kind: Service` creates a stable network endpoint in front of matching Pods
- `metadata.name: echo-service` gives the Service its name
- `selector.app: echo` tells the Service to send traffic to Pods with the label `app: echo`
- `ports` defines how the Service listens and forwards traffic
- `port: 80` exposes the Service on port 80
- `targetPort: 5678` forwards that traffic to port 5678 on the selected Pods

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

Why this step is needed here:

- the Service exists inside the Kubernetes cluster network, not automatically on your host machine
- `kubectl port-forward` creates a temporary tunnel from your local machine to the Service inside the cluster
- that lets you test the Service from your browser or with local `curl` without creating an external exposure method such as a NodePort, LoadBalancer, or Ingress
- this makes `port-forward` a good fit for quick access during a tutorial, but production-oriented systems usually rely on a more durable exposure method such as a load balancer or ingress path instead
- if you did **not** use `port-forward`, you would usually need to test from inside the cluster with another Pod, or you would need to expose the Service using some other Kubernetes networking method
- for one example of a production-style exposure method, see **Part 4, section 4.6.3, "AKS example: exposing a Service with `type: LoadBalancer`"**

Important timing note:

- this command keeps running in the foreground
- leave it open in that terminal while you test from a second terminal or browser

In a second terminal:

```bash
curl http://127.0.0.1:8080
```

Expected response:

```text
hello from echo-pod at <pod-ip>
```

That response now comes through the Service rather than from manually targeting the Pod IP.

## 2.10 Kubernetes networking

Kubernetes networking is built around a few expectations:

```text
DNS lookup

+------------------+        query: echo-service        +------------------+
| netshoot Pod     | --------------------------------> | cluster DNS      |
| temporary client | <-------------------------------- | returns Service  |
+------------------+        reply: Service IP          +------------------+

HTTP flow

+------------------+      request to Service name/IP   +------------------+
| netshoot Pod     | --------------------------------> | echo-service     |
| temporary client | <-------------------------------- | stable front door|
+------------------+      response via same path       +---------+--------+
                                                               |
                                                               | forwards / load-balances
                                                               v
                                                        +------------------+
                                                        | backend Pod       |
                                                        | echo-pod          |
                                                        +------------------+
```

This section demonstrates the idea that workloads inside the cluster usually talk to each other through Service names, not by discovering individual Pod IP addresses by hand.

A Service gives clients a stable name and virtual IP, but it is not itself the backend application. Instead, Kubernetes uses the Service definition as routing and load-balancing configuration: traffic sent to the Service is forwarded to one of the Pods selected by that Service.

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
hello from echo-pod at <pod-ip>
```

The important idea is that cluster-internal name resolution is now doing work for you.

## 2.11 Labels

**Labels** are key/value pairs attached to objects. Kubernetes uses them heavily for selection.

Show Pod labels directly:

```bash
kubectl get pods --show-labels
```

Filter by one specific label:

```bash
kubectl get pods -l app=echo
```

Why this matters:

- the first command shows which labels are present
- the second command shows how Kubernetes can use labels to find matching objects
- later, Services and Deployments rely on this same idea

### 2.12 Small challenge

Try changing the selector yourself:

```bash
kubectl get pods -l tier=demo
```

Question to think about:

- do you get any results yet?
- if not, why not?

You can answer that by comparing the labels on the current Pod with the labels you will see later in the Deployment template.

## 2.13 Deployments

A **Deployment** manages rollout for a stateless application.

A standalone Pod is useful for learning, but it is not the usual way to keep an application running. A Deployment describes the desired state for a replaceable set of Pods and lets Kubernetes maintain that state for you.

This example now keeps the self-identifying behavior from the earlier `echo-pod`. That means each replica created by the Deployment can answer with its own Pod name, which makes it much easier to see that the Service is sending traffic to a changing set of backend Pods rather than to one fixed machine.

It is also worth connecting this to the earlier multi-container Pod discussion. Deployments scale **Pods**, not individual containers inside a Pod. That means if one Pod template contains two containers and you scale the Deployment to three replicas, Kubernetes will run three Pods and a total of six containers from that template. This is one reason multi-container Pods should be reserved for tightly coupled workloads rather than loosely related processes that ought to scale independently.

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
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          args:
            - "-text=hello from $(POD_NAME) at $(POD_IP)"
          ports:
            - containerPort: 5678
```

What is new here:

- `apiVersion: apps/v1` uses the Kubernetes API group for controller-managed workloads
- `kind: Deployment` creates a Deployment rather than a standalone Pod
- `metadata.name: echo-deployment` names the Deployment
- `metadata.labels.app: echo` labels the Deployment object itself
- `spec.replicas: 2` asks Kubernetes to keep two Pod replicas running
- `selector.matchLabels.app: echo` tells the Deployment which Pods belong to it
- `template` defines the Pod template used to create each replica
- `template.metadata.labels` applies labels to every Pod created by this Deployment
- `tier: demo` and `lesson: deployments` are extra descriptive labels for filtering and organization
- `containers` defines the container each replica will run
- `env` defines environment variables named `POD_NAME` and `POD_IP`
- `env.valueFrom.fieldRef.fieldPath: metadata.name` fills `POD_NAME` with each Pod's own name
- `env.valueFrom.fieldRef.fieldPath: status.podIP` fills `POD_IP` with each Pod's internal cluster IP address
- `args` uses Kubernetes variable expansion so `$(POD_NAME)` and `$(POD_IP)` are resolved by the container runtime without requiring a shell inside the image
- `ports.containerPort: 5678` declares the application port inside each container

Remove the earlier standalone Pod:

```bash
kubectl delete pod echo-pod --ignore-not-found
```

Why do this first?

Because the goal now is to let the Deployment manage the backend Pods instead of leaving the original manually created Pod around.

Apply the Deployment and wait for rollout:

```bash
kubectl apply -f config/01-pods/deployment-echo.yaml
kubectl rollout status deployment/echo-deployment
```

What these commands do:

- the first creates the Deployment object
- the second waits while Kubernetes creates the managed Pods and reports when the rollout is complete

Scale the Deployment to three replicas:

```bash
kubectl scale deployment/echo-deployment --replicas=3
kubectl rollout status deployment/echo-deployment
```

Why these are separate again:

- `scale` changes the desired number of replicas
- `rollout status` lets you watch Kubernetes converge toward that new desired state

Inspect the resulting Pods:

```bash
kubectl get pods -o wide
```

Because the Service still selects `app: echo`, it can target the new Pods without changing the Service definition.

If you port-forward the Service again and send repeated requests, you may now see different Pod names in the responses. That is one of the nicest ways to make the Deployment-plus-Service pattern feel concrete.

For example, different requests might return values shaped like:

```text
hello from echo-deployment-7d8c6c9f5b-abc12
hello from echo-deployment-7d8c6c9f5b-def34
hello from echo-deployment-7d8c6c9f5b-ghi56
```

The exact names will be different in your cluster, but the important point is that each response can come from a different replica.

### 2.14 Small challenge

Before you continue, try answering this by observation:

- after scaling to 3 replicas, how many Pods do you expect `kubectl get pods` to show for this Deployment?
- which label would you use if you wanted to list only the Pods managed by this application?

One way to check yourself is:

```bash
kubectl get pods -l app=echo
```

If you want an extra stretch goal, run the Service through `port-forward` again and send a few requests. If the responses show different Pod names over time, that is strong evidence that the Service is distributing traffic across the available replicas rather than always choosing one fixed backend.

A concrete way to try that is:

```bash
kubectl port-forward service/echo-service 8080:80
```

Then, in another terminal:

```bash
for i in 1 2 3 4 5; do curl -s http://127.0.0.1:8080; done
```

Question to think about:

- how many distinct Pod names do you see?
- do the responses always come from the same replica, or not?

If you want a possible answer later, see the exercise solutions section at the end of the tutorial.

## 2.15 ConfigMaps

A **ConfigMap** stores non-secret configuration data.

**Why this matters:**

- ConfigMaps let you separate configuration from application code
- You can change configuration without rebuilding container images
- Multiple environments can use different ConfigMaps with the same application
- Configuration can be version-controlled and reviewed alongside your manifests

Example:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-config
data:
  app-mode: tutorial
  index.html: |
    <h1>Hello from a ConfigMap</h1>
```

What is new here:

- `kind: ConfigMap` creates a Kubernetes object for non-secret configuration
- `metadata.name: example-config` gives the ConfigMap its name
- `data` stores ordinary key/value configuration entries
- `app-mode: tutorial` stores a simple configuration value
- `index.html: |` stores a small multiline text file inside the ConfigMap

Apply the ConfigMap:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-config
data:
  app-mode: tutorial
  greeting-message: "Hello from ConfigMap"
EOF
```

Inspect what exists:

```bash
kubectl get configmap example-config
kubectl describe configmap example-config
```

### Using a ConfigMap in a Pod

ConfigMaps become useful when you actually consume them in a Pod. There are three common ways:

1. **Environment variables** - single key/value pairs as env vars
2. **EnvFrom** - all keys as environment variables
3. **Volume mounting** - mount ConfigMap data as files

Here's a Pod that demonstrates environment variable usage:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: configmap-demo
spec:
  containers:
    - name: demo
      image: busybox:1.36
      command: ["sh", "-c", "echo APP_MODE is $APP_MODE && echo GREETING is $GREETING && sleep 300"]
      env:
        - name: APP_MODE
          valueFrom:
            configMapKeyRef:
              name: example-config
              key: app-mode
        - name: GREETING
          valueFrom:
            configMapKeyRef:
              name: example-config
              key: greeting-message
EOF
```

Check the Pod's output to see the ConfigMap values:

```bash
kubectl logs configmap-demo
```

Expected output:

```text
APP_MODE is tutorial
GREETING is Hello from ConfigMap
```

What this demonstrates:

- The Pod didn't have the configuration hardcoded
- The ConfigMap values were injected as environment variables at runtime
- You can change the ConfigMap and the Pod would see new values on restart (though running Pods don't auto-update env vars)

Clean up:

```bash
kubectl delete pod configmap-demo
kubectl delete configmap example-config
```

## 2.16 Secrets

A **Secret** stores sensitive values such as passwords, tokens, and connection strings.

A useful first lesson is simply that Kubernetes treats secret data differently from ordinary configuration. You will use that idea later when the journal application needs database credentials.

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

What is new here:

- `kind: Secret` creates a Kubernetes object for sensitive values
- `metadata.name: example-secret` gives the Secret its name
- `metadata.namespace: tutorial` places the Secret in the `tutorial` namespace
- `type: Opaque` means this is a general-purpose Secret
- `stringData` lets you provide secret values as plain text in the manifest
- `username` and `password` are the keys stored in that Secret

Apply the Secret:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: example-secret
  namespace: tutorial
type: Opaque
stringData:
  username: demo
  password: super-secret-value
EOF
```

Inspect what exists:

```bash
kubectl get secret example-secret
kubectl describe secret example-secret
```

What to notice:

- the Secret exists as a Kubernetes object, much like a ConfigMap does
- Kubernetes knows the key names stored in it
- but you should think of the values as sensitive data that should not be handled as casually as normal config

### Using a Secret in a Pod

Secrets become useful when you consume them in a Pod. Like ConfigMaps, you can use Secrets as environment variables or mounted volumes.

Volume mounting is generally more secure for sensitive data because:

- Secret values don't appear in environment variable listings
- They're not visible in process inspection tools like `ps`
- Applications can read them only when explicitly needed

Here's a Pod that demonstrates Secret usage via volume mounting:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: secret-demo
spec:
  containers:
    - name: demo
      image: busybox:1.36
      command: ["sh", "-c", "echo Reading credentials from file... && cat /etc/secrets/username && echo Connecting as $(cat /etc/secrets/username) to database... && sleep 300"]
      volumeMounts:
        - name: secret-volume
          mountPath: /etc/secrets
          readOnly: true
  volumes:
    - name: secret-volume
      secret:
        secretName: example-secret
EOF
```

Check the Pod's output to see the Secret values:

```bash
kubectl logs secret-demo
```

Expected output:

```text
Reading credentials from file...
demo
Connecting as demo to database...
```

Verify the mounted files:

```bash
kubectl exec secret-demo -- ls -la /etc/secrets
kubectl exec secret-demo -- cat /etc/secrets/username
```

What this demonstrates:

- Each key in the Secret becomes a file in the mounted directory
- The file contents are the Secret values (automatically decoded from base64)
- The volume is mounted read-only, preventing accidental modification
- Files contain only the raw secret values, not base64 encoding

Important security note:

- Secret data is base64-encoded in the API server, but this is **not encryption**—anyone with API access can decode it
- Volume mounting keeps secrets out of environment listings, but they're still visible to anyone who can exec into the container
- For production use, consider encryption at rest and more sophisticated secret management systems

Clean up:

```bash
kubectl delete pod secret-demo
kubectl delete secret example-secret
```

This simple example is enough to make the journal database manifests later feel less surprising.

## 2.17 Persistent Volumes and PersistentVolumeClaims

A **PersistentVolume (PV)** represents storage made available to the cluster. A **PersistentVolumeClaim (PVC)** is a request to use some of that storage.

That difference matters:

- a **PV** is the storage resource itself, or at least Kubernetes' representation of it
- a **PVC** is what a workload asks for when it needs storage
- a Pod usually uses storage by referencing a **PVC**, not by referencing a PV directly

A useful mental model is:

- **PV** = supply
- **PVC** = demand

When a PVC is created, Kubernetes tries to bind it to a suitable PV.

There are two broad ways that can happen:

- **dynamic provisioning**
  - this is common in local development environments or managed cloud clusters
  - a storage provisioner automatically creates backing storage when a PVC is requested
  - this is the most convenient path for tutorials because you do not need to define the PV yourself first
- **static provisioning**
  - an administrator creates a PV ahead of time
  - later, a PVC can bind to that existing PV if the request matches what the PV offers
  - this is more common when you want tighter control over existing storage or specific storage characteristics

A simple example of a manually defined PV looks like this:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: demo-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /data/demo-pv
```

What this PV example means:

- `kind: PersistentVolume` creates a cluster storage resource
- `capacity.storage: 1Gi` says the PV offers 1 GiB of storage
- `accessModes: ReadWriteOnce` describes how it can be mounted
- `hostPath` uses a directory on the node itself as the backing storage

That `hostPath` pattern is useful for a simple lab, but it is not usually the right storage approach for production systems.

### Node-local storage vs. network storage

**Node-local storage** (`hostPath` or `local` PV type):

- The storage exists only on a specific node
- Pods using that storage must be scheduled on that same node (Kubernetes enforces this with `nodeAffinity`)
- If the node goes down, the storage and any pods using it are unavailable on other nodes
- Useful for single-node clusters, temporary data, or cached data that can be recreated

**Network storage** (NFS, cloud block storage, CSI drivers):

- Storage is accessible from multiple nodes
- Pods can move between nodes while maintaining access to the same data
- More complex to set up but required for stateful workloads in multi-node clusters
- Examples: NFS, AWS EBS, Azure Disk, Google Persistent Disk, Ceph, GlusterFS

Your local Docker Desktop cluster has only one node, so node-local storage works fine for learning. In a production multi-node cluster, database workloads typically use network-backed storage classes so pods can be rescheduled while maintaining data access.

Other ways PVs can be backed include:

- local node disks
- NFS or other network filesystems
- cloud block storage provided by platforms such as Azure, AWS, or Google Cloud
- CSI-based storage drivers that integrate Kubernetes with external storage systems

How a PVC uses a PV:

- the PVC asks for storage size and access characteristics
- Kubernetes looks for a matching PV, or asks a provisioner to create one dynamically
- once the PVC is bound, a Pod can mount that claim as a volume
- the Pod uses the mounted storage without needing to know the implementation details of the underlying PV

This is worth introducing as a core concept before the database examples, because it demonstrates a central Kubernetes idea: a Pod can go away while the storage survives.

### 2.18 Simple persistence demo

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

What is new here:

- `kind: PersistentVolumeClaim` creates a request for persistent storage
- `metadata.name: demo-shared-data` gives the storage claim its name
- `metadata.namespace: tutorial` places that claim in the `tutorial` namespace
- `accessModes: ReadWriteOnce` asks for storage that can be mounted read-write by one node at a time
- `resources.requests.storage: 1Gi` requests 1 GiB of storage
- `---` separates the PVC manifest from the Deployment manifest in the same file
- the second `kind: Deployment` creates the workload that will use that storage
- `metadata.name: pvc-demo` names the Deployment
- `spec.replicas: 1` keeps one Pod replica running
- `selector.matchLabels.app: pvc-demo` tells the Deployment which Pods belong to it
- `template.metadata.labels.app: pvc-demo` gives the Pod the label that matches the selector
- `containers[0].command` runs a shell script that creates a file if it does not already exist
- `volumeMounts.mountPath: /data` makes the mounted storage available inside the container at `/data`
- `volumes.persistentVolumeClaim.claimName: demo-shared-data` connects the Pod to the PVC created earlier in the file

Apply it:

```bash
kubectl apply -f config/01-pods/pvc-demo.yaml
kubectl rollout status deployment/pvc-demo
kubectl get pvc
kubectl exec deploy/pvc-demo -- cat /data/hello.txt
```

Delete the Pod and let the Deployment bring up another one:

```bash
kubectl delete pod -l app=pvc-demo
kubectl rollout status deployment/pvc-demo
kubectl exec deploy/pvc-demo -- cat /data/hello.txt
```

What this demonstrates:

- the Pod changed
- the file did not disappear
- the storage survived Pod replacement

That is the core idea you will rely on later when SQL Server stores durable data.

### Clean up

If you do not want to keep this demo workload and claim after the exercise, remove them with:

```bash
kubectl delete -f config/01-pods/pvc-demo.yaml
```

If your storage class uses `Delete` reclaim behavior, the backing storage is usually removed automatically when the claim is deleted. In other environments, cleanup behavior can differ.

A PVC is a request, not the storage implementation itself. In local development environments, a storage provisioner usually satisfies that request automatically and binds the claim to backing storage for you.

## 2.20 Understanding the complete Kubernetes object hierarchy

Throughout Part 2, you have learned about Pods, Deployments, Services, ConfigMaps, Secrets, and PersistentVolumeClaims. These objects don't exist in isolation—they form a hierarchy where higher-level objects create and manage lower-level objects.

This section walks through the complete chain from Deployment down to Container and Storage, using `kubectl describe` at each level. This is also where we examine **ReplicaSets**, which you may have noticed in your cluster but haven't been explicitly discussed yet.

### 2.20.1 Kubernetes controllers and their responsibilities

Before creating resources, it helps to understand which Kubernetes components do what:

| Component | What it does |
|-----------|--------------|
| **API Server** | Accepts YAML/commands, validates them, stores state in etcd |
| **etcd** | Key-value store holding all cluster state (Deployments, Pods, Services, etc.) |
| **Deployment controller** | Watches Deployments, creates/updates ReplicaSets to match desired state |
| **ReplicaSet controller** | Watches ReplicaSets, creates/deletes Pods to maintain replica count |
| **kube-scheduler** | Watches unscheduled Pods, assigns them to nodes based on resources/affinity |
| **kubelet** | Runs on each node, manages Pod lifecycle, reports status to API server |
| **kube-proxy** | Manages network rules for Services, load-balances traffic to Pods |
| **PersistentVolume controller** | Binds PVCs to PVs, provisions storage if using dynamic provisioning |
| **Container runtime** (containerd/docker) | Pulls images, starts/stops containers on the node |

### 2.20.2 Setup: Create a Deployment with all components

First, let's create a Deployment that uses ConfigMaps, Secrets, and PVCs so we can trace through everything:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: hierarchy-config
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head><title>Hierarchy Demo</title></head>
    <body>
      <h1>Kubernetes Hierarchy Demo</h1>
      <p>This page is served from a ConfigMap!</p>
    </body>
    </html>
---
apiVersion: v1
kind: Secret
metadata:
  name: hierarchy-secret
type: Opaque
stringData:
  username: admin
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hierarchy-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hierarchy-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hierarchy
  template:
    metadata:
      labels:
        app: hierarchy
    spec:
      containers:
        - name: main
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          env:
            - name: APP_USER
              valueFrom:
                secretKeyRef:
                  name: hierarchy-secret
                  key: username
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
            - name: data
              mountPath: /data
        - name: sidecar
          image: busybox:1.36
          env:
            - name: SECRET_USER
              valueFrom:
                secretKeyRef:
                  name: hierarchy-secret
                  key: username
          command: ["sh", "-c", "while true; do echo \"Running as user: $SECRET_USER\"; sleep 60; done"]
      volumes:
        - name: html
          configMap:
            name: hierarchy-config
        - name: data
          persistentVolumeClaim:
            claimName: hierarchy-data
EOF
```

Wait for everything to be ready:

```bash
kubectl rollout status deployment/hierarchy-demo
kubectl get all -l app=hierarchy
```

Verify the resources are working:

**Test the HTML page served from ConfigMap:**

```bash
POD=$(kubectl get pods -l app=hierarchy -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward pod/$POD 8080:80
```

In another terminal:

```bash
curl http://127.0.0.1:8080
```

Expected response: HTML page served from the ConfigMap

**Check the sidecar printing the secret username:**

```bash
kubectl logs $POD -c sidecar
```

Expected output: `Running as user: admin`

**Verify the PVC is mounted:**

```bash
kubectl exec $POD -- ls -la /data
```

### 2.20.3 The complete hierarchy tree

Here's how all the pieces fit together for the resources we just created:

```text
Deployment/hierarchy-demo                      (managed by Deployment controller)
    |
    | (selector: app=hierarchy)
    |
    v
ReplicaSet/hierarchy-demo-85b94c6f7d          (managed by ReplicaSet controller)
    |
    | (pod template with labels: app=hierarchy)
    |
    +----> Pod/hierarchy-demo-85b94c6f7d-abc12
    |         |
    |         | (controlled by: ReplicaSet/hierarchy-demo-85b94c6f7d)
    |         | (scheduled by: kube-scheduler)
    |         | (monitored by: kubelet)
    |         |
    |         +----> Container/main             (nginx:1.27-alpine)
    |         |         |
    |         |         | (env: APP_USER from Secret/hierarchy-secret)
    |         |         | (mounts: html → ConfigMap/hierarchy-config)
    |         |         | (mounts: data → PVC/hierarchy-data)
    |         |
    |         +----> Container/sidecar           (busybox:1.36)
    |                   |
    |                   | (env: SECRET_USER from Secret/hierarchy-secret)
    |
    +----> Pod/hierarchy-demo-85b94c6f7d-def34
              |
              | (uses same PVC, ConfigMap, Secret as sibling pod)
              |
              +----> Container/main
              +----> Container/sidecar

ConfigMap/hierarchy-config                     (stored in etcd, mounted to /usr/share/nginx/html)
    |
    | (data: index.html - HTML page served by nginx)
    |
    +----> Mounted into both Pods as read-only files

Secret/hierarchy-secret                        (stored in etcd, injected as env vars)
    |
    | (data: username=admin)
    |
    +----> Injected into main containers as APP_USER
    +----> Injected into sidecar containers as SECRET_USER

PVC/hierarchy-data                             (managed by PersistentVolume controller)
    |
    | (bound to PV)
    |
    v
PersistentVolume/pvc-<uuid>                   (backed by storage provisioner)
    |
    | (100Mi, ReadWriteOnce)
    |
    +----> Mounted into both Pods at /data
```

**Key relationships shown in this tree:**

- **Deployment → ReplicaSet:** One-to-many. Deployment can have multiple ReplicaSets during rolling updates.
- **ReplicaSet → Pod:** One-to-many. ReplicaSet maintains a specific number of Pod replicas.
- **Pod → Container:** One-to-many. A Pod can contain multiple containers that share the same lifecycle.
- **ConfigMap/Secret → Pod:** Many-to-many. Multiple Pods can reference the same ConfigMap or Secret.
- **PVC → PV:** One-to-one. Each PVC binds to exactly one PV.
- **PVC → Pod:** Many-to-many. Multiple Pods can mount the same PVC (if access mode allows).

### 2.20.4 Level 1: The Deployment

Start at the top. The Deployment is the declarative entry point:

```bash
kubectl describe deployment hierarchy-demo
```

**Key output sections and what they mean:**

**Name and Namespace:**
- `Name: hierarchy-demo` - Your Deployment's identifier
- `Namespace: tutorial` - Isolation boundary

**Replicas:**
- `Replicas: 2 desired | 2 updated | 2 total | 2 available | 0 unavailable`
- This shows the **Deployment controller** has successfully created 2 replicas

**Selector:**
- `Selector: app=hierarchy`
- This label selector is how the Deployment finds its child ReplicaSets
- **Who uses this:** The Deployment controller queries the API server for ReplicaSets matching this selector

**Strategy:**
- `StrategyType: RollingUpdate`
- `RollingUpdate: max unavailable=25%, max surge=25%`
- This controls how the Deployment controller performs updates

**Pod Template:**
- Shows the template used to create Pods
- **Who uses this:** The Deployment controller creates a ReplicaSet with this template hashed into its name

**NewReplicaSet:**
- `NewReplicaSet: hierarchy-demo-<hash>` (e.g., `hierarchy-demo-85b94c6f7d`)
- **Who creates this:** The Deployment controller created this ReplicaSet
- The hash comes from the Pod template contents—if the template changes, a new ReplicaSet with a different hash is created

**Events:**
```
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  15m   deployment-controller  Scaled up replica set hierarchy-demo-85b94c6f7d to 2
```
- **Who writes this:** The Deployment controller

**Next step:** Note the ReplicaSet name from "NewReplicaSet"—that's our next level down.

### 2.20.5 Level 2: The ReplicaSet

The ReplicaSet is the reconciliation layer that ensures the right number of Pods exist:

```bash
kubectl get replicaset -l app=hierarchy
REPLICASET=$(kubectl get replicaset -l app=hierarchy -o jsonpath='{.items[0].metadata.name}')
kubectl describe replicaset $REPLICASET
```

**Key output sections:**

**Owner References:**
- Shows it's owned by the Deployment `hierarchy-demo`
- **Who sets this:** The Deployment controller when creating the ReplicaSet

**Replicas:**
- `Replicas: 2 current / 2 desired`
- **Who maintains this:** The ReplicaSet controller constantly reconciles Pod count

**Pod Template:**
- Same template from the Deployment (stored in the ReplicaSet spec)
- **Who uses this:** The ReplicaSet controller creates Pods matching this template

**Events:**
```
Events:
  Type    Reason            Age   From                    Message
  ----    ------            ----  ----                    -------
  Normal  SuccessfulCreate  15m   replicaset-controller  Created pod: hierarchy-demo-85b94c6f7d-abc12
  Normal  SuccessfulCreate  15m   replicaset-controller  Created pod: hierarchy-demo-85b94c6f7d-def34
```
- **Who writes this:** The ReplicaSet controller

**Next step:** The Events show the Pod names that were created—those are our next level.

### 2.20.6 Level 3: The Pod

The Pod is the execution unit—the thing actually running on a node:

```bash
kubectl get pods -l app=hierarchy
POD=$(kubectl get pods -l app=hierarchy -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $POD
```

**Key output sections:**

**Controlled By:**
- `Controlled By: ReplicaSet/hierarchy-demo-85b94c6f7d`
- **Who set this:** The ReplicaSet controller when creating the Pod

**Node:**
- `Node: desktop-worker/172.18.0.2` (or similar)
- **Who assigned this:** kube-scheduler chose this node based on resources, affinity, taints/tolerations

**Priority and Priority Class:**
- Influences scheduling order when resources are scarce

**Labels:**
- `app=hierarchy` - matches the ReplicaSet selector
- **Who uses this:** The ReplicaSet controller queries for Pods with these labels

**Status:**
- `Phase: Running`
- `Conditions:` with PodReady, Initialized, PodScheduled, etc.
- **Who updates this:** kubelet on the node reports Pod status to API server

**IP:**
- `IP: 10.244.0.45` - The Pod's unique IP within the cluster
- **Who assigns this:** The kubelet (with help from the CNI plugin)

**Containers:**
- Lists `main` and `sidecar` containers
- Each shows State, Ready, Restart Count, etc.
- **Who manages these:** kubelet tells the container runtime to start/stop containers

**Mounts:**
- Shows ConfigMap mounts at `/etc/config`, PVC at `/data`
- **Who performs these mounts:** kubelet mounts these before starting the container

**Volumes:**
- Shows the volume definitions
- `config` → ConfigMap `hierarchy-config`
- `data` → PersistentVolumeClaim `hierarchy-data`

**Events:**
```
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  15m   default-scheduler  Successfully assigned tutorial/hierarchy-demo-85b94c6f7d-abc12 to desktop-worker
  Normal  Pulling    15m   kubelet            Pulling image "nginx:1.27-alpine"
  Normal  Pulled     15m   kubelet            Successfully pulled image "nginx:1.27-alpine"
  Normal  Created    15m   kubelet            Created container main
  Normal  Started    15m   kubelet            Started container main
```
- **Who writes this:** kubelet (reporting what it's doing)

**Next step:** Look at the Containers section for container-level details, or check the PVC binding.

### 2.20.7 Level 4: The Container

Within the Pod's `describe` output, find the Containers section. Each container has detailed status:

```
Containers:
  main:
    Container ID:  containerd://abc123...
    Image:         nginx:1.27-alpine
    Image ID:      docker.io/library/nginx@sha256:...
    State:         Running
      Started:      Wed, 14 May 2026 10:30:00 -0600
    Ready:         True
    Restart Count:  0
    Environment:
      APP_USER:     admin  (from Secret)
    Mounts:
      /etc/config from config (rw)
      /data from data (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-... (ro)
```

**Who does what at this level:**

- **Container ID:** Assigned by container runtime when starting the container
- **State updates:** kubelet polls container runtime and reports to API server
- **Environment variables:** kubelet injects these from Secret/ConfigMap before starting container
- **Mounts:** kubelet performs these mounts before starting container
- **Restart:** kubelet restarts crashed containers based on restart policy

### 2.20.8 Level 5: PersistentVolumeClaim and PersistentVolume

The PVC shows how storage is provisioned and bound:

```bash
kubectl describe pvc hierarchy-data
```

**Key output:**

**Status:**
- `Status: Bound` - Successfully bound to a PV
- **Who bound it:** PersistentVolume controller watched for matching PVs and created the binding

**Volume:**
- `Volume: pvc-<uuid>` - The name of the bound PV
- If using dynamic provisioning, this PV was created automatically

**Capacity:**
- `Capacity: 100Mi` - Requested and granted size

**Access Modes:**
- `Access Modes: RWO` - ReadWriteOnce

**Events:**
```
Events:
  Type    Reason                Age   From                             Message
  ----    ------                ----  ----                             -------
  Normal  Provisioning          15m   persistentvolume-controller  Waiting for a volume to be created
  Normal  ProvisioningSucceeded  15m   persistentvolume-controller  Successfully provisioned volume pvc-123
```
- **Who writes this:** PersistentVolume controller and external provisioner

You can also describe the bound PV:

```bash
PV=$(kubectl get pvc hierarchy-data -o jsonpath='{.spec.volumeName}')
kubectl describe pv $PV
```

### 2.20.9 Level 6: ConfigMap and Secret

**ConfigMap:**

```bash
kubectl describe configmap hierarchy-config
```

**What you'll see:**
- **Data:** Shows `index.html` with the HTML content
- **Who stores this:** API server stored this in etcd when you applied the manifest
- **Who uses it:** kubelet mounts this as a file at `/usr/share/nginx/html` in the main container

**Verify it's being served:**

```bash
kubectl port-forward deployment/hierarchy-demo 8080:80
# In another terminal:
curl http://127.0.0.1:8080
```

**Secret:**

```bash
kubectl describe secret hierarchy-secret
```

**What you'll see:**
- **Data:** Shows the `username` key (value is base64-encoded)
- **Who stores this:** API server stored this in etcd
- **Important:** Secret data is NOT encrypted in etcd by default—only base64-encoded
- **Who uses it:** kubelet injects these as environment variables:
  - `APP_USER` in the main container
  - `SECRET_USER` in the sidecar container

**Verify the sidecar is using the secret:**

```bash
kubectl logs deployment/hierarchy-demo -c sidecar
```

Expected output: `Running as user: admin` (repeated every 60 seconds)

### 2.20.10 Tracing the request path

When you `kubectl apply` a Deployment, here's the request flow:

1. **kubectl → API Server:** Your YAML is sent to the API server
2. **API Server → etcd:** API server validates and stores the Deployment object
3. **Deployment Controller:** Watches etcd, notices new Deployment
4. **Deployment Controller → API Server:** Creates a ReplicaSet
5. **ReplicaSet Controller:** Watches etcd, notices new ReplicaSet
6. **ReplicaSet Controller → API Server:** Creates Pod objects
7. **kube-scheduler:** Watches for unscheduled Pods, assigns to nodes
8. **kubelet:** Watches for Pods assigned to its node, tells container runtime to start containers
9. **Container Runtime:** Pulls images, starts containers
10. **kubelet → API Server:** Reports Pod and container status back

### 2.20.11 Why ReplicaSets are usually hidden

You may have noticed we haven't needed to work with ReplicaSets directly in most of the tutorial. Here's why:

- **Deployments are the higher-level abstraction:** You almost always want Deployments for rolling updates and rollbacks
- **ReplicaSets are an implementation detail:** The Deployment controller creates and manages them for you
- **Direct ReplicaSet use is rare:** Only when you need the simpler reconciliation behavior without Deployment features
- **kubectl scales Deployments automatically:** When you scale a Deployment, it handles the ReplicaSet for you

If you do need to work with ReplicaSets directly (for debugging or advanced scenarios):
```bash
kubectl get replicasets
kubectl describe replicaset <name>
kubectl scale replicaset <name> --replicas=3
```

### 2.20.12 The complete picture

Putting it all together, here's how a single request flows through the Kubernetes control plane and onto a node:

```text
User Action:
  kubectl apply -f deployment.yaml
       |
       v
API Server (validates, stores in etcd)
       |
       v
Controller Manager notices new Deployment
  |-- Deployment Controller creates ReplicaSet
  |-- ReplicaSet Controller creates Pods
       |
       v
Scheduler notices unscheduled Pods
  |-- kube-scheduler assigns Pods to nodes
       |
       v
Kubelet on each node
  |-- Watches for Pods assigned to that node
  |-- Pulls images
  |-- Mounts volumes (from PV provisioner, ConfigMap, Secret)
  |-- Starts containers via container runtime
  |-- Reports status back to API Server
       |
       v
Running Application
```

### Clean up

```bash
kubectl delete deployment hierarchy-demo
kubectl delete pvc hierarchy-data
kubectl delete configmap hierarchy-config
kubectl delete secret hierarchy-secret
```

---
