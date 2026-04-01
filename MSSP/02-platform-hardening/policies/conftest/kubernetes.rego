# =============================================================================
# GP-COPILOT - KUBERNETES CONFTEST POLICIES
# =============================================================================
# CKS-aligned admission policies for CI/CD validation
#
# Usage:
#   conftest test deployment.yaml --policy policies/conftest/
#
# =============================================================================

package kubernetes

import future.keywords.in
import future.keywords.contains
import future.keywords.if

# =============================================================================
# POD SECURITY STANDARDS (PSS)
# =============================================================================

# CRITICAL: Block privileged containers
deny[msg] {
    input.kind == "Pod"
    container := input.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf("CRITICAL: Container '%s' is privileged. This allows full host access.", [container.name])
}

deny[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job"]
    container := input.spec.template.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf("CRITICAL: Container '%s' in %s '%s' is privileged.", [container.name, input.kind, input.metadata.name])
}

# CRITICAL: Block privilege escalation
deny[msg] {
    input.kind == "Pod"
    container := input.spec.containers[_]
    container.securityContext.allowPrivilegeEscalation == true
    msg := sprintf("CRITICAL: Container '%s' allows privilege escalation.", [container.name])
}

deny[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job"]
    container := input.spec.template.spec.containers[_]
    container.securityContext.allowPrivilegeEscalation == true
    msg := sprintf("CRITICAL: Container '%s' allows privilege escalation.", [container.name])
}

# HIGH: Require runAsNonRoot
deny[msg] {
    input.kind == "Pod"
    not input.spec.securityContext.runAsNonRoot
    container := input.spec.containers[_]
    not container.securityContext.runAsNonRoot
    msg := sprintf("HIGH: Container '%s' may run as root. Set runAsNonRoot: true.", [container.name])
}

deny[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job"]
    not input.spec.template.spec.securityContext.runAsNonRoot
    container := input.spec.template.spec.containers[_]
    not container.securityContext.runAsNonRoot
    msg := sprintf("HIGH: Container '%s' may run as root.", [container.name])
}

# HIGH: Block hostNetwork
deny[msg] {
    input.kind == "Pod"
    input.spec.hostNetwork == true
    msg := "HIGH: Pod uses hostNetwork. This exposes host network interfaces."
}

deny[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet"]
    input.spec.template.spec.hostNetwork == true
    msg := sprintf("HIGH: %s '%s' uses hostNetwork.", [input.kind, input.metadata.name])
}

# HIGH: Block hostPID
deny[msg] {
    input.kind == "Pod"
    input.spec.hostPID == true
    msg := "HIGH: Pod uses hostPID. This exposes host process namespace."
}

# HIGH: Block hostIPC
deny[msg] {
    input.kind == "Pod"
    input.spec.hostIPC == true
    msg := "HIGH: Pod uses hostIPC. This exposes host IPC namespace."
}

# =============================================================================
# SUPPLY CHAIN SECURITY
# =============================================================================

# HIGH: Block :latest tag
deny[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job", "Pod"]
    containers := get_containers(input)
    container := containers[_]
    endswith(container.image, ":latest")
    msg := sprintf("HIGH: Container '%s' uses :latest tag. Pin to specific version.", [container.name])
}

deny[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job", "Pod"]
    containers := get_containers(input)
    container := containers[_]
    not contains(container.image, ":")
    msg := sprintf("HIGH: Container '%s' has no image tag. Pin to specific version.", [container.name])
}

# MEDIUM: Warn on untrusted registries
warn[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job", "Pod"]
    containers := get_containers(input)
    container := containers[_]
    not trusted_registry(container.image)
    msg := sprintf("MEDIUM: Container '%s' uses untrusted registry: %s", [container.name, container.image])
}

trusted_registry(image) {
    trusted_prefixes := [
        "gcr.io/",
        "us.gcr.io/",
        "eu.gcr.io/",
        "asia.gcr.io/",
        "ghcr.io/",
        "docker.io/library/",
        "registry.k8s.io/",
        "quay.io/",
        "public.ecr.aws/",
        # Add your trusted registries here
    ]
    prefix := trusted_prefixes[_]
    startswith(image, prefix)
}

trusted_registry(image) {
    # Allow images without explicit registry (defaults to Docker Hub)
    not contains(image, "/")
}

# =============================================================================
# RESOURCE MANAGEMENT
# =============================================================================

# MEDIUM: Require resource limits
warn[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job", "Pod"]
    containers := get_containers(input)
    container := containers[_]
    not container.resources.limits.memory
    msg := sprintf("MEDIUM: Container '%s' has no memory limit. Risk of OOM impact.", [container.name])
}

warn[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job", "Pod"]
    containers := get_containers(input)
    container := containers[_]
    not container.resources.limits.cpu
    msg := sprintf("MEDIUM: Container '%s' has no CPU limit.", [container.name])
}

# MEDIUM: Require resource requests
warn[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job", "Pod"]
    containers := get_containers(input)
    container := containers[_]
    not container.resources.requests.memory
    msg := sprintf("MEDIUM: Container '%s' has no memory request.", [container.name])
}

# =============================================================================
# CAPABILITY RESTRICTIONS
# =============================================================================

# HIGH: Drop all capabilities
warn[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job", "Pod"]
    containers := get_containers(input)
    container := containers[_]
    not drops_all_capabilities(container)
    msg := sprintf("HIGH: Container '%s' should drop all capabilities.", [container.name])
}

drops_all_capabilities(container) {
    container.securityContext.capabilities.drop[_] == "ALL"
}

# CRITICAL: Block dangerous capabilities
dangerous_capabilities := [
    "SYS_ADMIN",
    "NET_ADMIN",
    "SYS_PTRACE",
    "SYS_MODULE",
    "DAC_OVERRIDE",
    "SETUID",
    "SETGID",
]

deny[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job", "Pod"]
    containers := get_containers(input)
    container := containers[_]
    cap := container.securityContext.capabilities.add[_]
    cap in dangerous_capabilities
    msg := sprintf("CRITICAL: Container '%s' adds dangerous capability: %s", [container.name, cap])
}

# =============================================================================
# FILESYSTEM SECURITY
# =============================================================================

# MEDIUM: Recommend read-only root filesystem
warn[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job", "Pod"]
    containers := get_containers(input)
    container := containers[_]
    not container.securityContext.readOnlyRootFilesystem
    msg := sprintf("MEDIUM: Container '%s' should use readOnlyRootFilesystem.", [container.name])
}

# HIGH: Block hostPath volumes
deny[msg] {
    input.kind == "Pod"
    volume := input.spec.volumes[_]
    volume.hostPath
    msg := sprintf("HIGH: Pod uses hostPath volume '%s'. This exposes host filesystem.", [volume.name])
}

deny[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet"]
    volume := input.spec.template.spec.volumes[_]
    volume.hostPath
    msg := sprintf("HIGH: %s '%s' uses hostPath volume.", [input.kind, input.metadata.name])
}

# =============================================================================
# NETWORKING
# =============================================================================

# MEDIUM: Warn on Services with externalIPs
warn[msg] {
    input.kind == "Service"
    input.spec.externalIPs
    msg := sprintf("MEDIUM: Service '%s' uses externalIPs. Review if necessary.", [input.metadata.name])
}

# LOW: Recommend NetworkPolicy
warn[msg] {
    input.kind == "Namespace"
    msg := sprintf("LOW: Ensure NetworkPolicies exist for namespace '%s'.", [input.metadata.name])
}

# =============================================================================
# PROBES & AVAILABILITY
# =============================================================================

# MEDIUM: Require liveness probes
warn[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet"]
    containers := get_containers(input)
    container := containers[_]
    not container.livenessProbe
    msg := sprintf("MEDIUM: Container '%s' has no livenessProbe.", [container.name])
}

# MEDIUM: Require readiness probes
warn[msg] {
    input.kind in ["Deployment", "StatefulSet", "DaemonSet"]
    containers := get_containers(input)
    container := containers[_]
    not container.readinessProbe
    msg := sprintf("MEDIUM: Container '%s' has no readinessProbe.", [container.name])
}

# =============================================================================
# RBAC SECURITY
# =============================================================================

# HIGH: Block cluster-admin bindings
deny[msg] {
    input.kind == "ClusterRoleBinding"
    input.roleRef.name == "cluster-admin"
    msg := sprintf("HIGH: ClusterRoleBinding '%s' grants cluster-admin.", [input.metadata.name])
}

# MEDIUM: Warn on wildcard rules
warn[msg] {
    input.kind in ["Role", "ClusterRole"]
    rule := input.rules[_]
    rule.resources[_] == "*"
    rule.verbs[_] == "*"
    msg := sprintf("MEDIUM: %s '%s' has wildcard permissions.", [input.kind, input.metadata.name])
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

get_containers(resource) = containers {
    resource.kind == "Pod"
    containers := resource.spec.containers
}

get_containers(resource) = containers {
    resource.kind in ["Deployment", "StatefulSet", "DaemonSet", "Job"]
    containers := resource.spec.template.spec.containers
}
