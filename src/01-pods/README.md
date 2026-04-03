# Stage 01: Pods and early core Kubernetes objects

This stage does not include custom application source code.

Instead, the early examples use existing public container images such as:

- `busybox:1.36`
- `hashicorp/http-echo:1.0.0`
- `nicolaka/netshoot:latest`

That is why this directory contains explanatory notes rather than application code.

Related manifests live in:

- `config/01-pods/`

Those manifests cover the early core Kubernetes examples used in the tutorial, including:

- short-lived Pods
- long-running Pods from YAML
- Services
- namespaces
- labels
- Deployments
- the simple PVC persistence demo

The `01-` / `02-` / `03-` numbering in both `src/` and `config/` represents tutorial stage order, not part number. The `tutorial/` directory is organized by the four large tutorial parts, while `src/` and `config/` are organized by example stage.
