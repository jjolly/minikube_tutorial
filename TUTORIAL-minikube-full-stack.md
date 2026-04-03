# Minikube Tutorial: Modular Guide

This tutorial has been split into modules so it is easier to work through in stages.

The original material is organized into four parts:

1. **Installation and infrastructure**
2. **Typical cluster functionality and usage**
3. **Cluster usage examples**
4. **Advanced cluster usage**

Use this file as the entry point, then open the module you want.

## What you are building and why

Minikube gives you a local Kubernetes cluster you can experiment with safely. On WSL, that means you can learn the Kubernetes object model and application deployment flow without renting cloud infrastructure first.

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
  01-installation-and-infrastructure.md
  02-typical-cluster-functionality-and-usage.md
  03-cluster-usage-examples.md
  04-advanced-cluster-usage.md
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
scripts/
  reset-minikube-tutorial.sh
```

How to use this layout:

- `tutorial/` contains the four tutorial modules.
- `src/` contains application source code and Docker build inputs.
- `config/` contains Kubernetes manifests used by the tutorial.
- `config/05-journal/step1-startup-init/` contains the first database-init approach.
- `config/05-journal/step2-job-init/` contains the improved database-init approach.
- `scripts/reset-minikube-tutorial.sh` resets tutorial resources. It is intentionally destructive and requires explicit confirmation of the target context before proceeding.

## Modules

- [Part 1. Installation and infrastructure](tutorial/01-installation-and-infrastructure.md)
- [Part 2. Typical cluster functionality and usage](tutorial/02-typical-cluster-functionality-and-usage.md)
- [Part 3. Cluster usage examples](tutorial/03-cluster-usage-examples.md)
- [Part 4. Advanced cluster usage](tutorial/04-advanced-cluster-usage.md)

## Suggested reading order

If you are new to Kubernetes, read the modules in order.

If you are revisiting the tutorial later:

- start with **Part 1** if you need cluster setup or infrastructure refreshers
- jump to **Part 2** if you want core Kubernetes object behavior
- jump to **Part 3** if you want application-focused examples
- jump to **Part 4** if you want RBAC, gateway alternatives, exercise notes, or reset-script guidance
