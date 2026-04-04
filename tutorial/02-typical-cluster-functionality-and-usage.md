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

Clean up the Pod:

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

Remove the simple example before moving on:

```bash
kubectl delete pod simple-echo-pod
```

That keeps the first example self-contained before introducing the richer Pod used later.

### 2.5 A Pod that can identify itself

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
      command:
        - /bin/sh
        - -c
      args:
        - exec /http-echo -text="hello from ${POD_NAME}" -listen=:5678
      ports:
        - containerPort: 5678
```

What is new here:

- `env` defines an environment variable named `POD_NAME`
- `valueFrom.fieldRef.fieldPath: metadata.name` tells Kubernetes to fill that variable with the Pod's own name
  - this `fieldRef` pattern is part of the Kubernetes **Downward API**, which lets a container learn selected information about the Pod it is running in
  - a few common `fieldPath` values worth knowing are:
    - `metadata.name`: the Pod's name
    - `metadata.namespace`: the namespace the Pod is running in
    - `spec.nodeName`: the node the Pod was scheduled onto
    - `status.podIP`: the Pod's internal cluster IP address
    - `metadata.labels['app']`: the value of a specific label, when present
    - `metadata.annotations['some-key']`: the value of a specific annotation, when present
  - the important idea is that Kubernetes can inject selected Pod metadata into the container environment without you hard-coding those values into the image
- `command` and `args` now run a shell first so `${POD_NAME}` can be expanded before starting `http-echo`

This is a little more complicated than the first example, but it becomes very useful later because the response can reflect the actual Pod identity.

Apply the richer Pod manifest:

```bash
kubectl apply -f config/01-pods/pod-echo.yaml
kubectl wait --for=condition=Ready pod/echo-pod --timeout=120s
```

Why these are grouped together:

- the first command creates the Pod
- the second waits until it is actually ready before you test it

### 2.6 Small challenge

In section 2.4, you already used a temporary helper Pod to access a running HTTP Pod from inside the cluster.

Before reading further, see if you can adapt that earlier two-command pattern yourself so it reaches **`echo-pod`** instead of **`simple-echo-pod`**.

Hints:

- you still need the Pod's internal IP address
- you still need the helper Pod to `curl` that IP from inside the cluster
- only a small part of the earlier command sequence needs to change

If you want to try it on your own first, stop here for a moment.

The answer appears at the start of the Services section, so you can check your work there if needed.

That little exercise is worth doing because it reinforces that Kubernetes is not doing anything magical yet. At this point, you are still reaching one specific Pod by its IP, just as before.

Then clean up the standalone Pod before moving on:

```bash
kubectl delete pod echo-pod
```

That cleanup is intentional because the next sections rebuild the same idea using Services and then Deployments.

## 2.7 Multi-container Pods and sidecars

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

### 2.7.1 Sidecar example: one container writes, one serves

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
            cat > /shared/index.html <<'EOF'
<!doctype html>
<html lang="en">
  <head><meta charset="utf-8" /><title>sidecar demo</title></head>
  <body>
    <h1>Sidecar demo</h1>
    <p>This page was written by the writer sidecar and served by nginx.</p>
  </body>
</html>
EOF
            sleep 30
          done
      volumeMounts:
        - name: shared-content
          mountPath: /shared
  volumes:
    - name: shared-content
      emptyDir: {}
```

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

For example:

```bash
kubectl delete pod sidecar-demo
```

That is a big part of the design lesson here: a multi-container Pod is one lifecycle unit, not a tiny cluster hiding inside a Pod.

### 2.7.2 Another tightly coupled pattern

A sidecar is not the only multi-container pattern. Another common one is sometimes called an **ambassador** or local proxy pattern, where one container acts as a closely coupled local proxy for the main application.

The important point is not the name of the pattern. The important question is whether the containers truly belong together.

A useful rule of thumb is:

- if the containers must share the same network identity, volumes, and lifecycle, a multi-container Pod can make sense
- if the containers should scale independently, roll out independently, or fail independently, they usually belong in separate Pods

## 2.8 Services

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

### 2.8 Answer to the section 2.5 challenge

If you tried the challenge from the previous section, the adapted command sequence looks like this:

```bash
POD_IP=$(kubectl get pod echo-pod -o jsonpath='{.status.podIP}')
kubectl run netshoot-pod-check --image=nicolaka/netshoot:latest --restart=Never --rm -i -- sh -lc "curl -fsS http://$POD_IP:5678"
```

Expected response:

```text
hello from echo-pod
```

If that worked, good — you have just confirmed that `echo-pod` is reachable from inside the cluster the same way the simpler Pod was.

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

Important timing note:

- this command keeps running in the foreground
- leave it open in that terminal while you test from a second terminal or browser

In a second terminal:

```bash
curl http://127.0.0.1:8080
```

Expected response:

```text
hello from echo-pod
```

That response now comes through the Service rather than from manually targeting the Pod IP.

## 2.9 Kubernetes networking

Kubernetes networking is built around a few expectations:

```text
Pod A  --DNS lookup-->  Service name
  |                      |
  |------HTTP/TCP------> Service virtual IP
                         |
                         v
                      backend Pod
```

This section demonstrates the idea that workloads inside the cluster usually talk to each other through Service names, not by discovering individual Pod IP addresses by hand.

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
hello from echo-pod
```

The important idea is that cluster-internal name resolution is now doing work for you.

## 2.10 Namespaces

A **namespace** groups resources so you can separate environments and reduce clutter.

File: `config/01-pods/namespace-tutorial.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tutorial
```

Create the namespace:

```bash
kubectl apply -f config/01-pods/namespace-tutorial.yaml
```

Move the echo resources into it:

```bash
kubectl apply -n tutorial -f config/01-pods/pod-echo.yaml
kubectl apply -n tutorial -f config/01-pods/service-echo.yaml
```

Inspect what now exists in that namespace:

```bash
kubectl get all -n tutorial
```

Why these steps are split up:

- first you create the namespace itself
- then you create objects inside it
- finally you inspect only that namespace so the output stays focused on tutorial resources

### 2.11 Contexts and changing the default namespace

Check the current context information:

```bash
kubectl config current-context
kubectl config view --minify
```

What these commands show:

- the first prints the name of the currently selected kubeconfig context
- the second shows the currently active cluster, user, and namespace settings in a smaller view

Set the current context to default to the `tutorial` namespace:

```bash
kubectl config set-context --current --namespace=tutorial
```

Verify the effect:

```bash
kubectl get pods
kubectl get svc
```

At this point, those commands should use `tutorial` by default.

### 2.12 Small challenge

Before moving on, try this yourself:

- run `kubectl get pods` without `-n tutorial`
- then run `kubectl get pods -n default`

Question to think about:

- which command shows your tutorial Pod, and why?

If the result is not what you expected, look back at `kubectl config set-context --current --namespace=tutorial` and `kubectl config view --minify`.

## 2.13 Labels

**Labels** are key/value pairs attached to objects. Kubernetes uses them heavily for selection.

Show Pod labels directly:

```bash
kubectl get pods -n tutorial --show-labels
```

Filter by one specific label:

```bash
kubectl get pods -n tutorial -l app=echo
```

Why this matters:

- the first command shows which labels are present
- the second command shows how Kubernetes can use labels to find matching objects
- later, Services and Deployments rely on this same idea

### 2.14 Small challenge

Try changing the selector yourself:

```bash
kubectl get pods -n tutorial -l tier=demo
```

Question to think about:

- do you get any results yet?
- if not, why not?

You can answer that by comparing the labels on the current Pod with the labels you will see later in the Deployment template.

## 2.15 Deployments

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
          command:
            - /bin/sh
            - -c
          args:
            - exec /http-echo -text="hello from ${POD_NAME}" -listen=:5678
          ports:
            - containerPort: 5678
```

Remove the earlier standalone Pod:

```bash
kubectl delete pod -n tutorial echo-pod --ignore-not-found
```

Why do this first?

Because the goal now is to let the Deployment manage the backend Pods instead of leaving the original manually created Pod around.

Apply the Deployment and wait for rollout:

```bash
kubectl apply -n tutorial -f config/01-pods/deployment-echo.yaml
kubectl rollout status deployment/echo-deployment -n tutorial
```

What these commands do:

- the first creates the Deployment object
- the second waits while Kubernetes creates the managed Pods and reports when the rollout is complete

Scale the Deployment to three replicas:

```bash
kubectl scale deployment/echo-deployment -n tutorial --replicas=3
kubectl rollout status deployment/echo-deployment -n tutorial
```

Why these are separate again:

- `scale` changes the desired number of replicas
- `rollout status` lets you watch Kubernetes converge toward that new desired state

Inspect the resulting Pods:

```bash
kubectl get pods -n tutorial -o wide
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

### 2.16 Small challenge

Before you continue, try answering this by observation:

- after scaling to 3 replicas, how many Pods do you expect `kubectl get pods -n tutorial` to show for this Deployment?
- which label would you use if you wanted to list only the Pods managed by this application?

One way to check yourself is:

```bash
kubectl get pods -n tutorial -l app=echo
```

If you want an extra stretch goal, run the Service through `port-forward` again and send a few requests. If the responses show different Pod names over time, that is strong evidence that the Service is distributing traffic across the available replicas rather than always choosing one fixed backend.

A concrete way to try that is:

```bash
kubectl port-forward -n tutorial service/echo-service 8080:80
```

Then, in another terminal:

```bash
for i in 1 2 3 4 5; do curl -s http://127.0.0.1:8080; done
```

Question to think about:

- how many distinct Pod names do you see?
- do the responses always come from the same replica, or not?

If you want a possible answer later, see the exercise solutions section at the end of the tutorial.

## 2.17 Secrets

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
kubectl get secret example-secret -n tutorial
kubectl describe secret example-secret -n tutorial
```

What to notice:

- the Secret exists as a Kubernetes object, much like a ConfigMap does
- Kubernetes knows the key names stored in it
- but you should think of the values as sensitive data that should not be handled as casually as normal config

This simple example is enough to make the journal database manifests later feel less surprising.

## 2.18 ConfigMaps

A **ConfigMap** stores non-secret configuration data.

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

ConfigMaps are useful for small files, app settings, and simple tutorial content.

## 2.19 Persistent Volumes and PersistentVolumeClaims

A **PersistentVolumeClaim** requests durable storage for a workload.

This is worth introducing as a core concept before the database examples, because it demonstrates a central Kubernetes idea: a Pod can go away while the storage survives.

### 2.20 Simple persistence demo

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

Apply it:

```bash
kubectl apply -f config/01-pods/pvc-demo.yaml
kubectl rollout status deployment/pvc-demo -n tutorial
kubectl get pvc -n tutorial
kubectl exec -n tutorial deploy/pvc-demo -- cat /data/hello.txt
```

Delete the Pod and let the Deployment bring up another one:

```bash
kubectl delete pod -n tutorial -l app=pvc-demo
kubectl rollout status deployment/pvc-demo -n tutorial
kubectl exec -n tutorial deploy/pvc-demo -- cat /data/hello.txt
```

What this demonstrates:

- the Pod changed
- the file did not disappear
- the storage survived Pod replacement

That is the core idea you will rely on later when SQL Server stores durable data.

### 2.21 Why this matters later

A PVC is a request, not the storage implementation itself. In minikube, a storage provisioner usually satisfies that request automatically and binds the claim to backing storage for you.

---
