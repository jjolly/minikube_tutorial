# Kubernetes Tutorial: Modular Guide

This tutorial has been split into modules so it is easier to work through in stages.

The original material is organized into six parts:

0. **Cluster Setup** - Set up your local Kubernetes environment
1. **Infrastructure and kubectl** - Learn about the Kubernetes control plane, nodes, and core services
2. **Typical cluster functionality and usage**
3. **Cluster usage examples**
4. **Multi-Node Local Clusters** - Explore multi-node scheduling and behavior
5. **Advanced cluster usage**

Use this file as the entry point, then open the module you want.

## What you are building and why

This tutorial gives you a local Kubernetes cluster you can experiment with safely. You can learn the Kubernetes object model and application deployment flow without renting cloud infrastructure first.

The goal of this tutorial is to show not only how to run things, but also how to reason about why Kubernetes uses these objects and patterns.

By the end, you will have:

- a simple pod and service
- a static nginx web page
- a small Flask service behind nginx
- a React frontend under `/genkey` with a Flask API at `/genkey/api`
- a C# journal application backed by Microsoft SQL Server with persistent storage
- an Ingress route exposing both `/genkey` and `/journal`

## Tutorial layout

This section helps you find the files used by the tutorial while you work.

```text
tutorial/
  00-cluster-setup.md
  01-infrastructure-and-kubectl.md
  02-typical-cluster-functionality-and-usage.md
  03-cluster-usage-examples.md
  04-multi-node-clusters.md
  05-advanced-cluster-usage.md
src/
  01-pods/
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

How to use this layout:

- `tutorial/` contains the six tutorial modules.
- `src/` contains application source code and other source-stage materials used by the examples.
- `config/` contains Kubernetes manifests used by the tutorial.
- the `01-` / `02-` / `03-` numbering in `src/` and `config/` represents **tutorial stage order**, not part number.
- `src/01-pods/` is present as a placeholder/explanation stage because the earliest examples use stock public images rather than custom application source code.
- `config/05-journal/step1-startup-init/` contains the first database-init approach.
- `config/05-journal/step2-job-init/` contains the improved database-init approach.
- if you want a full tutorial reset, see the reset instructions in **Part 0** for your chosen cluster type.

## Modules

- [Part 0. Cluster Setup](tutorial/00-cluster-setup.md) - Set up your local Kubernetes cluster
- [Part 1. Infrastructure and kubectl](tutorial/01-infrastructure-and-kubectl.md)
- [Part 2. Typical cluster functionality and usage](tutorial/02-typical-cluster-functionality-and-usage.md)
- [Part 3. Cluster usage examples](tutorial/03-cluster-usage-examples.md)
- [Part 4. Multi-Node Local Clusters](tutorial/04-multi-node-clusters.md)
- [Part 5. Advanced cluster usage](tutorial/05-advanced-cluster-usage.md)

## Suggested reading order

If you are new to Kubernetes, read the modules in order:

1. Start with **Part 0** to set up your local cluster
2. Continue with **Part 1** to understand Kubernetes infrastructure
3. Work through **Parts 2 and 3** for core concepts and examples
4. Try **Part 4** to see multi-node cluster behavior
5. Explore **Part 5** for advanced topics

If you are revisiting the tutorial later:

- start with **Part 0** if you need a different cluster setup
- jump to **Part 1** if you need infrastructure refreshers
- jump to **Part 2** if you want core Kubernetes object behavior
- jump to **Part 3** if you want application-focused examples
- jump to **Part 4** if you want to explore multi-node scheduling
- jump to **Part 5** if you want RBAC, gateway alternatives, or exercise notes
