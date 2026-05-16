# Advanced Topics: Gateway and Gateway API Options

The main tutorial uses a standard ingress controller because it is the simplest reliable path for the core lessons. This advanced section is where you compare more capable alternatives.

A useful way to study these options is to keep the same application intent across all of them:

- route `/genkey` to the `genkey-web` Service
- route `/journal` to the `journal-web` Service
- optionally add filters, policies, or more advanced traffic rules depending on the gateway implementation

---

## 1. NGINX Gateway Fabric

### Why you might choose it

- strong continuity with nginx-based ingress concepts
- good for HTTP routing examples
- easier conceptual bridge if you already understand nginx

### Limitations

- more installation work than the standard ingress controller used in the main tutorial
- still requires you to install Gateway API CRDs and the gateway controller

### Example configuration

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: nginx-gateway
  namespace: tutorial
spec:
  gatewayClassName: nginx
  listeners:
    - name: http
      protocol: HTTP
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx-routes
  namespace: tutorial
spec:
  parentRefs:
    - name: nginx-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /genkey
      backendRefs:
        - name: genkey-web
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /journal
      backendRefs:
        - name: journal-web
          port: 80
```

### What this configuration demonstrates

- a single HTTP listener on port 80
- path-based routing to two Services
- a model that feels close to Ingress, but uses the Gateway API object structure

---

## 2. Envoy Gateway

### Why you might choose it

- modern Gateway API story
- strong ecosystem momentum
- good for showing traffic-management concepts beyond basic ingress routing

### Limitations

- more infrastructure to install and understand
- heavier than the core tutorial path

### Example configuration

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-gateway
  namespace: tutorial
spec:
  gatewayClassName: envoy
  listeners:
    - name: http
      protocol: HTTP
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: envoy-routes
  namespace: tutorial
spec:
  parentRefs:
    - name: envoy-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /genkey
      backendRefs:
        - name: genkey-web
          port: 80
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Tutorial-Gateway
                value: envoy
    - matches:
        - path:
            type: PathPrefix
            value: /journal
      backendRefs:
        - name: journal-web
          port: 80
```

### What this configuration demonstrates

- the same two path routes as the nginx example
- a Gateway API filter that modifies request headers
- a more explicitly policy-oriented style that fits Envoy’s strengths

---

## 3. Cilium Gateway API

### Why you might choose it

- good if you also want to study networking, policy, and service routing in more depth
- natural fit when Cilium is already your CNI and dataplane

### Limitations

- introduces Cilium-specific concepts beyond the scope of the core tutorial
- more surface area than most first-pass learners need

### Example configuration

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: cilium-gateway
  namespace: tutorial
spec:
  gatewayClassName: cilium
  listeners:
    - name: http
      protocol: HTTP
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: cilium-routes
  namespace: tutorial
spec:
  parentRefs:
    - name: cilium-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /genkey
      backendRefs:
        - name: genkey-web
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /journal
      backendRefs:
        - name: journal-web
          port: 80
```

### What this configuration demonstrates

- the same basic routing model as the other Gateway API examples
- the fact that much of Gateway API is portable across implementations
- how the main differences often come from installation model, policy extensions, and operational ecosystem rather than basic route syntax alone

---

## 4. Istio Gateway API support

### Why you might choose it

- powerful traffic management
- useful if you specifically want to learn service mesh concepts later

### Limitations

- very easy for a Kubernetes tutorial to turn into an Istio tutorial by accident
- significantly more conceptual and operational overhead

### Example configuration

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-gateway
  namespace: tutorial
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      protocol: HTTP
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: istio-routes
  namespace: tutorial
spec:
  parentRefs:
    - name: istio-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /genkey
      backendRefs:
        - name: genkey-web
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /journal
      backendRefs:
        - name: journal-web
          port: 80
```

### What this configuration demonstrates

- the same Gateway API route model can sit on top of a much richer service-mesh platform
- Istio becomes interesting when you want features like mesh-wide policy, mTLS, richer traffic shaping, and workload identity controls

---

## 5. Contrasting the gateway choices

### Common ground

All four examples above demonstrate:

- an HTTP Gateway listener on port 80
- path-based routing for `/genkey` and `/journal`
- separation between gateway infrastructure objects and application routing objects

### Main differences

**NGINX Gateway Fabric**
- best when you want continuity with nginx concepts
- easiest mental transition from Ingress

**Envoy Gateway**
- best when you want a modern Gateway-first story
- stronger fit for demonstrating filters and policy-oriented routing features

**Cilium Gateway API**
- best when your interests include networking and dataplane architecture
- more about the broader networking stack than just HTTP entry routing

**Istio Gateway API support**
- best when the real goal is eventually learning service mesh
- likely too much for the core tutorial path

---

## 6. Recommendation for this tutorial

For the main body of the tutorial:

- keep **Ingress** as the default runnable path

For a future advanced follow-on section:

- choose **NGINX Gateway Fabric** if you want the easiest conceptual progression from nginx ingress
- choose **Envoy Gateway** if you want the strongest Gateway API teaching story
