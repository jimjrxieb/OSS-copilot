# Playbook 03: Check Running Containers

> Your Dockerfiles might be hardened, but what's actually running in your cluster?
> This playbook audits live containers for security misconfigurations.
>
> **Time:** ~10 minutes
> **Prerequisites:** kubectl access to a Kubernetes cluster

---

## Why Runtime Checks Matter

You can have a perfect Dockerfile and still run an insecure container. Kubernetes
manifests can override security settings. Helm charts can set `privileged: true`.
Someone might have kubectl-patched a deployment months ago.

This playbook checks what's **actually running** — not what the Dockerfile says.

---

## Step 1: The 5-Minute Security Audit

Run these commands to get a quick picture of your cluster's container security:

```bash
# How many containers are running?
kubectl get pods --all-namespaces --no-headers | wc -l

# How many are running as root?
kubectl get pods --all-namespaces -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
root_pods = 0
total = 0
for pod in data.get('items', []):
    for c in pod['spec'].get('containers', []):
        total += 1
        sc = c.get('securityContext', {})
        if not sc.get('runAsNonRoot') and sc.get('runAsUser', 0) == 0:
            root_pods += 1
            ns = pod['metadata'].get('namespace', 'default')
            name = pod['metadata']['name']
            print(f'  ROOT: {ns}/{name}/{c[\"name\"]}')
print(f'\n{root_pods}/{total} containers potentially running as root')
"
```

---

## Step 2: The Full Container Security Checklist

Run the scan-runtime script for a comprehensive check:

```bash
# From the 03-container directory
./scan-runtime.sh
```

Or run these checks individually:

### Check 1: Privileged Containers

```bash
# Privileged containers have FULL host access — essentially root on the node
kubectl get pods --all-namespaces -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pod in data.get('items', []):
    ns = pod['metadata'].get('namespace', 'default')
    name = pod['metadata']['name']
    for c in pod['spec'].get('containers', []):
        sc = c.get('securityContext', {})
        if sc.get('privileged'):
            print(f'  PRIVILEGED: {ns}/{name}/{c[\"name\"]}')
"
```

**What to do:** Unless this is a system component (like Falco or a CNI plugin),
a privileged container is almost always a misconfiguration. Remove `privileged: true`
from the pod spec.

### Check 2: Containers Without Resource Limits

```bash
# No limits = a single container can starve the node
kubectl get pods --all-namespaces -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for pod in data.get('items', []):
    ns = pod['metadata'].get('namespace', 'default')
    name = pod['metadata']['name']
    for c in pod['spec'].get('containers', []):
        limits = c.get('resources', {}).get('limits')
        if not limits:
            count += 1
            print(f'  NO LIMITS: {ns}/{name}/{c[\"name\"]}')
print(f'\n{count} containers without resource limits')
"
```

**What to do:** Add resource limits to every container:
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### Check 3: Writable Root Filesystem

```bash
# Writable root = attacker can modify the container's filesystem
kubectl get pods --all-namespaces -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for pod in data.get('items', []):
    ns = pod['metadata'].get('namespace', 'default')
    name = pod['metadata']['name']
    for c in pod['spec'].get('containers', []):
        sc = c.get('securityContext', {})
        if not sc.get('readOnlyRootFilesystem'):
            count += 1
print(f'{count} containers with writable root filesystem')
print('(Set readOnlyRootFilesystem: true and use emptyDir for temp writes)')
"
```

### Check 4: Images Using :latest

```bash
# :latest means you don't know what version is running
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | grep -E ':latest|[^:0-9][^:]*$' | head -20
```

### Check 5: Containers That Can Escalate Privileges

```bash
kubectl get pods --all-namespaces -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for pod in data.get('items', []):
    ns = pod['metadata'].get('namespace', 'default')
    name = pod['metadata']['name']
    for c in pod['spec'].get('containers', []):
        sc = c.get('securityContext', {})
        if sc.get('allowPrivilegeEscalation', True):
            count += 1
print(f'{count} containers allow privilege escalation')
print('(Set allowPrivilegeEscalation: false)')
"
```

---

## Step 3: Score Your Cluster

After running all checks, fill in this scorecard:

```
Container Security Scorecard
─────────────────────────────
Date: ___________
Total containers: ___

Privileged containers:        ___  (target: 0, except system components)
Running as root:              ___  (target: 0)
No resource limits:           ___  (target: 0)
Writable root filesystem:    ___  (target: 0)
Using :latest tag:            ___  (target: 0)
Allow privilege escalation:   ___  (target: 0)
No capabilities dropped:     ___  (target: 0)
```

**A healthy cluster** has zeros across the board for application containers.
System components (kube-proxy, CNI plugins, Falco) are exceptions — they
legitimately need elevated permissions.

---

## Step 4: The Secure Pod Spec

Here's what a fully hardened container looks like in a Kubernetes manifest:

```yaml
containers:
  - name: my-app
    image: my-app:1.2.3          # Pinned version, never :latest
    securityContext:
      runAsNonRoot: true          # Can't run as root
      runAsUser: 1000             # Explicit non-root UID
      readOnlyRootFilesystem: true # Can't write to container filesystem
      allowPrivilegeEscalation: false  # Can't gain more privileges
      capabilities:
        drop: ["ALL"]            # Drop all Linux capabilities
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
    livenessProbe:               # Restart if unhealthy
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 10
    readinessProbe:              # Don't send traffic until ready
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
```

---

## Step 5: What This Doesn't Catch

These checks audit **configuration**. They don't detect:
- A container running a cryptominer that was downloaded after startup
- An attacker who exec'd into a container and is exfiltrating data
- A container making suspicious network connections

That's what runtime detection is for → [04-deploy-falco.md](04-deploy-falco.md)

---

## Next Steps

- Deploy Falco for runtime threat detection → [04-deploy-falco.md](04-deploy-falco.md)
- Add container scanning to CI → [05-container-ci.md](05-container-ci.md)
