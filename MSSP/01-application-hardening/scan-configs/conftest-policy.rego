# Conftest Policy for CI/CD
# OPA-based policy checks for Kubernetes manifests, Terraform, and Dockerfiles
# Docs: https://www.conftest.dev/

package main

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# DENY rules block the deployment
# WARN rules create warnings but don't block

###############################################################################
# KUBERNETES SECURITY POLICIES
###############################################################################

# Deny privileged containers
deny contains msg if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf("Privileged container not allowed: %s", [container.name])
}

deny contains msg if {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf("Privileged container not allowed: %s", [container.name])
}

# Deny running as root
deny contains msg if {
    input.kind == "Pod"
    not input.spec.securityContext.runAsNonRoot
    msg := "Containers must not run as root"
}

deny contains msg if {
    input.kind == "Deployment"
    not input.spec.template.spec.securityContext.runAsNonRoot
    msg := "Containers must not run as root"
}

# Deny privilege escalation
deny contains msg if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    container.securityContext.allowPrivilegeEscalation == true
    msg := sprintf("Privilege escalation not allowed: %s", [container.name])
}

# Deny missing resource limits
warn contains msg if {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not container.resources.limits
    msg := sprintf("Container missing resource limits: %s", [container.name])
}

# Deny missing resource requests
warn contains msg if {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not container.resources.requests
    msg := sprintf("Container missing resource requests: %s", [container.name])
}

# Deny latest tag
deny contains msg if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet"]
    container := input.spec.containers[_]
    endswith(container.image, ":latest")
    msg := sprintf("Image tag 'latest' not allowed: %s", [container.image])
}

deny contains msg if {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    endswith(container.image, ":latest")
    msg := sprintf("Image tag 'latest' not allowed: %s", [container.image])
}

# Deny untrusted registries
deny contains msg if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet"]
    container := input.spec.containers[_]
    not is_trusted_registry(container.image)
    msg := sprintf("Image from untrusted registry: %s", [container.image])
}

deny contains msg if {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not is_trusted_registry(container.image)
    msg := sprintf("Image from untrusted registry: %s", [container.image])
}

# Helper: Check if image is from trusted registry
is_trusted_registry(image) if {
    trusted_registries := [
        "docker.io/",
        "ghcr.io/",
        "gcr.io/",
        "registry.k8s.io/",
        "quay.io/",
    ]
    prefix := trusted_registries[_]
    startswith(image, prefix)
}

# Deny dangerous capabilities
deny contains msg if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    capability := container.securityContext.capabilities.add[_]
    capability in ["SYS_ADMIN", "NET_ADMIN", "SYS_MODULE"]
    msg := sprintf("Dangerous capability not allowed: %s in %s", [capability, container.name])
}

# Warn on missing probes
warn contains msg if {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not container.livenessProbe
    msg := sprintf("Container missing liveness probe: %s", [container.name])
}

warn contains msg if {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not container.readinessProbe
    msg := sprintf("Container missing readiness probe: %s", [container.name])
}

###############################################################################
# NETWORK POLICY CHECKS
###############################################################################

# Warn if no NetworkPolicy exists for namespace
warn contains msg if {
    input.kind == "Namespace"
    not has_network_policy
    msg := "Namespace should have a NetworkPolicy"
}

has_network_policy if {
    # This is a simplified check - in real usage, check against actual cluster state
    input.kind == "NetworkPolicy"
}

###############################################################################
# RBAC POLICY CHECKS
###############################################################################

# Deny overly permissive ClusterRole
deny contains msg if {
    input.kind == "ClusterRole"
    rule := input.rules[_]
    rule.verbs[_] == "*"
    rule.resources[_] == "*"
    msg := "ClusterRole grants wildcard permissions"
}

# Deny binding to cluster-admin
deny contains msg if {
    input.kind == "ClusterRoleBinding"
    input.roleRef.name == "cluster-admin"
    msg := "Binding to cluster-admin not allowed"
}

###############################################################################
# SERVICE POLICY CHECKS
###############################################################################

# Warn on LoadBalancer services (potential cost/exposure)
warn contains msg if {
    input.kind == "Service"
    input.spec.type == "LoadBalancer"
    msg := "LoadBalancer service creates external exposure - verify this is intended"
}

# Warn on NodePort services
warn contains msg if {
    input.kind == "Service"
    input.spec.type == "NodePort"
    msg := "NodePort service exposes on all nodes - consider using ClusterIP + Ingress"
}

###############################################################################
# TERRAFORM POLICY CHECKS — HCL CONFIG FORMAT
# Used when conftest runs directly against .tf files:
#   conftest test main.tf --policy policy/
###############################################################################

# Deny unencrypted S3 buckets
deny contains msg if {
    input.resource.aws_s3_bucket[name]
    bucket := input.resource.aws_s3_bucket[name]
    not bucket.server_side_encryption_configuration
    msg := sprintf("S3 bucket missing encryption: %s", [name])
}

# Deny public S3 buckets
deny contains msg if {
    input.resource.aws_s3_bucket[name]
    bucket := input.resource.aws_s3_bucket[name]
    bucket.acl == "public-read"
    msg := sprintf("S3 bucket has public ACL: %s", [name])
}

# Deny security groups with 0.0.0.0/0 ingress
deny contains msg if {
    input.resource.aws_security_group[name]
    sg := input.resource.aws_security_group[name]
    rule := sg.ingress[_]
    rule.cidr_blocks[_] == "0.0.0.0/0"
    msg := sprintf("Security group allows ingress from 0.0.0.0/0: %s", [name])
}

###############################################################################
# TERRAFORM POLICY CHECKS — PLAN JSON FORMAT
# Used when conftest runs against terraform plan output:
#   terraform plan -out=tfplan
#   terraform show -json tfplan > plan.json
#   conftest test plan.json --policy policy/
#
# Plan JSON structure: input.resource_changes[*].change.after
###############################################################################

# Helper: extract resource changes of a specific type being created or updated
tf_plan_resources(resource_type) := changes if {
    changes := [r |
        r := input.resource_changes[_]
        r.type == resource_type
        r.change.actions[_] in ["create", "update"]
    ]
}

# Deny unencrypted S3 buckets (plan JSON)
deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_s3_bucket")[_]
    after := r.change.after
    not after.server_side_encryption_configuration
    msg := sprintf("S3 bucket missing encryption (plan): %s", [r.address])
}

# Deny S3 buckets where encryption list is empty (plan JSON)
deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_s3_bucket")[_]
    after := r.change.after
    count(after.server_side_encryption_configuration) == 0
    msg := sprintf("S3 bucket missing encryption (plan): %s", [r.address])
}

# Deny public S3 buckets (plan JSON)
deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_s3_bucket")[_]
    r.change.after.acl == "public-read"
    msg := sprintf("S3 bucket has public ACL (plan): %s", [r.address])
}

# Deny S3 buckets with public access block disabled (plan JSON)
deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_s3_bucket_public_access_block")[_]
    after := r.change.after
    after.block_public_acls == false
    msg := sprintf("S3 public access block disabled (plan): %s", [r.address])
}

deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_s3_bucket_public_access_block")[_]
    after := r.change.after
    after.ignore_public_acls == false
    msg := sprintf("S3 ignoring public ACLs is disabled (plan): %s", [r.address])
}

# Deny security groups with 0.0.0.0/0 ingress (plan JSON)
deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_security_group")[_]
    rule := r.change.after.ingress[_]
    rule.cidr_blocks[_] == "0.0.0.0/0"
    msg := sprintf("Security group allows ingress from 0.0.0.0/0 (plan): %s", [r.address])
}

# Deny security groups with ::/0 IPv6 ingress (plan JSON)
deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_security_group")[_]
    rule := r.change.after.ingress[_]
    rule.ipv6_cidr_blocks[_] == "::/0"
    msg := sprintf("Security group allows IPv6 ingress from ::/0 (plan): %s", [r.address])
}

# Warn on security group rules open to the internet (plan JSON)
warn contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_security_group_rule")[_]
    r.change.after.type == "ingress"
    r.change.after.cidr_blocks[_] == "0.0.0.0/0"
    msg := sprintf("Security group rule open to internet (plan): %s", [r.address])
}

# Deny RDS instances without storage encryption (plan JSON)
deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_db_instance")[_]
    r.change.after.storage_encrypted == false
    msg := sprintf("RDS instance storage not encrypted (plan): %s", [r.address])
}

# Deny RDS instances that are publicly accessible (plan JSON)
deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_db_instance")[_]
    r.change.after.publicly_accessible == true
    msg := sprintf("RDS instance is publicly accessible (plan): %s", [r.address])
}

# Warn on missing deletion protection for RDS (plan JSON)
warn contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_db_instance")[_]
    r.change.after.deletion_protection == false
    msg := sprintf("RDS instance has no deletion protection (plan): %s", [r.address])
}

# Deny IAM policies with wildcard actions (plan JSON)
deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_iam_policy")[_]
    policy := json.unmarshal(r.change.after.policy)
    stmt := policy.Statement[_]
    stmt.Effect == "Allow"
    stmt.Action == "*"
    msg := sprintf("IAM policy grants wildcard Action (*) (plan): %s", [r.address])
}

# Deny IAM policies with wildcard resources under Allow (plan JSON)
deny contains msg if {
    input.resource_changes
    r := tf_plan_resources("aws_iam_policy")[_]
    policy := json.unmarshal(r.change.after.policy)
    stmt := policy.Statement[_]
    stmt.Effect == "Allow"
    stmt.Resource == "*"
    stmt.Action == "*"
    msg := sprintf("IAM policy allows * on * (plan): %s", [r.address])
}

###############################################################################
# DOCKERFILE POLICY CHECKS
###############################################################################

# Deny root user
deny contains msg if {
    input.Stages[_].Commands[_].Cmd == "user"
    input.Stages[_].Commands[_].Value[_] == "root"
    msg := "Dockerfile USER should not be root"
}

# Warn on latest base image
warn contains msg if {
    input.Stages[_].Commands[_].Cmd == "from"
    value := input.Stages[_].Commands[_].Value[0]
    endswith(value, ":latest")
    msg := sprintf("Base image uses :latest tag: %s", [value])
}

###############################################################################
# GITHUB ACTIONS POLICY CHECKS
###############################################################################

# Deny unpinned actions
deny contains msg if {
    input.jobs[job_name].steps[_].uses
    uses := input.jobs[job_name].steps[_].uses
    not contains(uses, "@")
    not contains(uses, "/")
    msg := sprintf("GitHub Action not pinned to version in job %s: %s", [job_name, uses])
}

# Warn on overly permissive permissions
warn contains msg if {
    input.permissions
    input.permissions == "write-all"
    msg := "Workflow has write-all permissions - scope down to specific permissions"
}
