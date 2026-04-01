# conftest-policy_test.rego
# Unit tests for conftest-policy.rego
#
# Run all tests:
#   conftest verify --policy 01-scanners/configs/
#
# Run against fixture files:
#   conftest test 01-scanners/configs/tests/fixtures/bad-deployment.yaml   --policy 01-scanners/configs/
#   conftest test 01-scanners/configs/tests/fixtures/good-deployment.yaml  --policy 01-scanners/configs/
#   conftest test 01-scanners/configs/tests/fixtures/bad-plan.json         --policy 01-scanners/configs/
#   conftest test 01-scanners/configs/tests/fixtures/good-plan.json        --policy 01-scanners/configs/
#
# Generate plan JSON from Terraform and test it:
#   terraform plan -out=tfplan
#   terraform show -json tfplan > plan.json
#   conftest test plan.json --policy 01-scanners/configs/

package main

import future.keywords.if
import future.keywords.in

###############################################################################
# KUBERNETES — DENY TESTS (rules that MUST fire)
###############################################################################

test_deny_privileged_pod if {
    deny["Privileged container not allowed: bad-container"] with input as {
        "kind": "Pod",
        "spec": {"containers": [
            {"name": "bad-container", "securityContext": {"privileged": true}}
        ]}
    }
}

test_deny_privileged_deployment if {
    deny["Privileged container not allowed: bad-container"] with input as {
        "kind": "Deployment",
        "spec": {"template": {"spec": {"containers": [
            {"name": "bad-container", "securityContext": {"privileged": true}}
        ]}}}
    }
}

test_deny_root_pod if {
    deny["Containers must not run as root"] with input as {
        "kind": "Pod",
        "spec": {
            "containers": [{"name": "app", "image": "nginx:1.25"}]
        }
    }
}

test_deny_root_deployment if {
    deny["Containers must not run as root"] with input as {
        "kind": "Deployment",
        "spec": {"template": {"spec": {
            "containers": [{"name": "app", "image": "nginx:1.25"}]
        }}}
    }
}

test_deny_privilege_escalation if {
    deny["Privilege escalation not allowed: app"] with input as {
        "kind": "Pod",
        "spec": {"containers": [
            {"name": "app", "securityContext": {"allowPrivilegeEscalation": true}}
        ]}
    }
}

test_deny_latest_tag_pod if {
    deny[_] with input as {
        "kind": "Pod",
        "spec": {"containers": [
            {"name": "app", "image": "nginx:latest"}
        ]}
    }
}

test_deny_latest_tag_deployment if {
    deny[_] with input as {
        "kind": "Deployment",
        "spec": {"template": {"spec": {"containers": [
            {"name": "app", "image": "nginx:latest"}
        ]}}}
    }
}

test_deny_dangerous_capability_sys_admin if {
    deny[_] with input as {
        "kind": "Pod",
        "spec": {"containers": [
            {"name": "app", "securityContext": {"capabilities": {"add": ["SYS_ADMIN"]}}}
        ]}
    }
}

test_deny_dangerous_capability_net_admin if {
    deny[_] with input as {
        "kind": "Pod",
        "spec": {"containers": [
            {"name": "app", "securityContext": {"capabilities": {"add": ["NET_ADMIN"]}}}
        ]}
    }
}

test_deny_wildcard_clusterrole if {
    deny["ClusterRole grants wildcard permissions"] with input as {
        "kind": "ClusterRole",
        "rules": [{"verbs": ["*"], "resources": ["*"]}]
    }
}

test_deny_cluster_admin_binding if {
    deny["Binding to cluster-admin not allowed"] with input as {
        "kind": "ClusterRoleBinding",
        "roleRef": {"name": "cluster-admin"}
    }
}

###############################################################################
# KUBERNETES — WARN TESTS (rules that MUST warn)
###############################################################################

test_warn_missing_resource_limits if {
    warn[_] with input as {
        "kind": "Deployment",
        "spec": {"template": {"spec": {"containers": [
            {"name": "app", "image": "ghcr.io/org/app:v1.0"}
        ]}}}
    }
}

test_warn_missing_resource_requests if {
    warn[_] with input as {
        "kind": "Deployment",
        "spec": {"template": {"spec": {"containers": [
            {"name": "app", "image": "ghcr.io/org/app:v1.0"}
        ]}}}
    }
}

test_warn_missing_liveness_probe if {
    warn[_] with input as {
        "kind": "Deployment",
        "spec": {"template": {"spec": {"containers": [
            {
                "name": "app",
                "image": "ghcr.io/org/app:v1.0",
                "resources": {
                    "limits": {"cpu": "500m", "memory": "256Mi"},
                    "requests": {"cpu": "100m", "memory": "128Mi"}
                }
            }
        ]}}}
    }
}

test_warn_loadbalancer_service if {
    warn["LoadBalancer service creates external exposure - verify this is intended"] with input as {
        "kind": "Service",
        "spec": {"type": "LoadBalancer"}
    }
}

test_warn_nodeport_service if {
    warn["NodePort service exposes on all nodes - consider using ClusterIP + Ingress"] with input as {
        "kind": "Service",
        "spec": {"type": "NodePort"}
    }
}

###############################################################################
# KUBERNETES — PASS TESTS (good manifests must NOT trigger deny)
###############################################################################

test_allow_hardened_deployment if {
    count(deny) == 0 with input as {
        "kind": "Deployment",
        "spec": {"template": {"spec": {
            "securityContext": {
                "runAsNonRoot": true,
                "runAsUser": 1000,
                "seccompProfile": {"type": "RuntimeDefault"}
            },
            "containers": [{
                "name": "app",
                "image": "ghcr.io/myorg/myapp:v1.2.3",
                "securityContext": {
                    "privileged": false,
                    "allowPrivilegeEscalation": false,
                    "readOnlyRootFilesystem": true,
                    "capabilities": {"drop": ["ALL"]}
                },
                "resources": {
                    "limits": {"cpu": "500m", "memory": "256Mi"},
                    "requests": {"cpu": "100m", "memory": "128Mi"}
                },
                "livenessProbe":  {"httpGet": {"path": "/health", "port": 8080}},
                "readinessProbe": {"httpGet": {"path": "/ready",  "port": 8080}}
            }]
        }}}
    }
}

test_allow_clusterrole_specific_verbs if {
    count(deny) == 0 with input as {
        "kind": "ClusterRole",
        "rules": [{"verbs": ["get", "list", "watch"], "resources": ["pods"]}]
    }
}

test_allow_clusterip_service if {
    count(deny) == 0 with input as {
        "kind": "Service",
        "spec": {"type": "ClusterIP"}
    }
}

###############################################################################
# TERRAFORM — HCL FORMAT DENY TESTS
# Matches: conftest test main.tf --policy 01-scanners/configs/
###############################################################################

test_deny_tf_hcl_s3_unencrypted if {
    deny[_] with input as {
        "resource": {
            "aws_s3_bucket": {
                "my-bucket": {
                    "bucket": "my-bucket"
                }
            }
        }
    }
}

test_deny_tf_hcl_s3_public_acl if {
    deny["S3 bucket has public ACL: my-bucket"] with input as {
        "resource": {
            "aws_s3_bucket": {
                "my-bucket": {
                    "bucket": "my-bucket",
                    "acl": "public-read",
                    "server_side_encryption_configuration": {"rule": {}}
                }
            }
        }
    }
}

test_deny_tf_hcl_sg_open_ingress if {
    deny["Security group allows ingress from 0.0.0.0/0: open-sg"] with input as {
        "resource": {
            "aws_security_group": {
                "open-sg": {
                    "ingress": [
                        {"cidr_blocks": ["0.0.0.0/0"], "from_port": 22, "to_port": 22, "protocol": "tcp"}
                    ]
                }
            }
        }
    }
}

test_allow_tf_hcl_s3_encrypted if {
    count(deny) == 0 with input as {
        "resource": {
            "aws_s3_bucket": {
                "my-bucket": {
                    "bucket": "my-bucket",
                    "acl": "private",
                    "server_side_encryption_configuration": {
                        "rule": {
                            "apply_server_side_encryption_by_default": {
                                "sse_algorithm": "aws:kms"
                            }
                        }
                    }
                }
            }
        }
    }
}

###############################################################################
# TERRAFORM — PLAN JSON FORMAT DENY TESTS
# Matches: terraform plan -out=tfplan && terraform show -json tfplan > plan.json
#          conftest test plan.json --policy 01-scanners/configs/
#
# Plan JSON structure:
#   input.resource_changes[*].address   — "aws_s3_bucket.my-bucket"
#   input.resource_changes[*].type      — "aws_s3_bucket"
#   input.resource_changes[*].change.actions  — ["create"] / ["update"] / ["delete"]
#   input.resource_changes[*].change.after    — desired end state (what Terraform will create)
###############################################################################

test_deny_plan_s3_unencrypted if {
    deny[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_s3_bucket.data",
            "type": "aws_s3_bucket",
            "name": "data",
            "change": {
                "actions": ["create"],
                "after": {
                    "bucket": "my-data-bucket",
                    "acl": "private"
                }
            }
        }]
    }
}

test_deny_plan_s3_empty_encryption_block if {
    deny[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_s3_bucket.data",
            "type": "aws_s3_bucket",
            "name": "data",
            "change": {
                "actions": ["create"],
                "after": {
                    "bucket": "my-data-bucket",
                    "server_side_encryption_configuration": []
                }
            }
        }]
    }
}

test_deny_plan_s3_public_acl if {
    deny[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_s3_bucket.public-data",
            "type": "aws_s3_bucket",
            "name": "public-data",
            "change": {
                "actions": ["create"],
                "after": {
                    "bucket": "public-bucket",
                    "acl": "public-read",
                    "server_side_encryption_configuration": [{"rule": {}}]
                }
            }
        }]
    }
}

test_deny_plan_s3_public_access_block_disabled if {
    deny[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_s3_bucket_public_access_block.data",
            "type": "aws_s3_bucket_public_access_block",
            "name": "data",
            "change": {
                "actions": ["create"],
                "after": {
                    "block_public_acls":   false,
                    "block_public_policy": true,
                    "ignore_public_acls":  true,
                    "restrict_public_buckets": true
                }
            }
        }]
    }
}

test_deny_plan_sg_open_ingress_ipv4 if {
    deny[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_security_group.web",
            "type": "aws_security_group",
            "name": "web",
            "change": {
                "actions": ["create"],
                "after": {
                    "name": "web-sg",
                    "ingress": [{
                        "cidr_blocks": ["0.0.0.0/0"],
                        "ipv6_cidr_blocks": [],
                        "from_port": 22,
                        "to_port": 22,
                        "protocol": "tcp",
                        "description": "SSH"
                    }]
                }
            }
        }]
    }
}

test_deny_plan_sg_open_ingress_ipv6 if {
    deny[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_security_group.web",
            "type": "aws_security_group",
            "name": "web",
            "change": {
                "actions": ["create"],
                "after": {
                    "name": "web-sg",
                    "ingress": [{
                        "cidr_blocks": [],
                        "ipv6_cidr_blocks": ["::/0"],
                        "from_port": 443,
                        "to_port": 443,
                        "protocol": "tcp"
                    }]
                }
            }
        }]
    }
}

test_deny_plan_rds_unencrypted if {
    deny[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_db_instance.postgres",
            "type": "aws_db_instance",
            "name": "postgres",
            "change": {
                "actions": ["create"],
                "after": {
                    "identifier": "prod-postgres",
                    "storage_encrypted": false,
                    "publicly_accessible": false
                }
            }
        }]
    }
}

test_deny_plan_rds_publicly_accessible if {
    deny[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_db_instance.postgres",
            "type": "aws_db_instance",
            "name": "postgres",
            "change": {
                "actions": ["create"],
                "after": {
                    "identifier": "prod-postgres",
                    "storage_encrypted": true,
                    "publicly_accessible": true
                }
            }
        }]
    }
}

test_deny_plan_iam_wildcard_action if {
    deny[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_iam_policy.admin",
            "type": "aws_iam_policy",
            "name": "admin",
            "change": {
                "actions": ["create"],
                "after": {
                    "name": "admin-policy",
                    "policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}"
                }
            }
        }]
    }
}

###############################################################################
# TERRAFORM — PLAN JSON FORMAT WARN TESTS
###############################################################################

test_warn_plan_sg_rule_open if {
    warn[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_security_group_rule.allow_all",
            "type": "aws_security_group_rule",
            "name": "allow_all",
            "change": {
                "actions": ["create"],
                "after": {
                    "type": "ingress",
                    "cidr_blocks": ["0.0.0.0/0"],
                    "from_port": 443,
                    "to_port": 443,
                    "protocol": "tcp"
                }
            }
        }]
    }
}

test_warn_plan_rds_no_deletion_protection if {
    warn[_] with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_db_instance.postgres",
            "type": "aws_db_instance",
            "name": "postgres",
            "change": {
                "actions": ["create"],
                "after": {
                    "identifier": "prod-postgres",
                    "storage_encrypted": true,
                    "publicly_accessible": false,
                    "deletion_protection": false
                }
            }
        }]
    }
}

###############################################################################
# TERRAFORM — PLAN JSON FORMAT PASS TESTS (good infra must NOT trigger deny)
###############################################################################

test_allow_plan_s3_fully_hardened if {
    count(deny) == 0 with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_s3_bucket.data",
            "type": "aws_s3_bucket",
            "name": "data",
            "change": {
                "actions": ["create"],
                "after": {
                    "bucket": "my-private-bucket",
                    "acl": "private",
                    "server_side_encryption_configuration": [{
                        "rule": [{
                            "apply_server_side_encryption_by_default": [{
                                "sse_algorithm": "aws:kms"
                            }]
                        }]
                    }]
                }
            }
        }]
    }
}

test_allow_plan_sg_restricted_ingress if {
    count(deny) == 0 with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_security_group.app",
            "type": "aws_security_group",
            "name": "app",
            "change": {
                "actions": ["create"],
                "after": {
                    "name": "app-sg",
                    "ingress": [{
                        "cidr_blocks": ["10.0.0.0/8"],
                        "ipv6_cidr_blocks": [],
                        "from_port": 8080,
                        "to_port": 8080,
                        "protocol": "tcp"
                    }]
                }
            }
        }]
    }
}

test_allow_plan_rds_hardened if {
    count(deny) == 0 with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_db_instance.postgres",
            "type": "aws_db_instance",
            "name": "postgres",
            "change": {
                "actions": ["create"],
                "after": {
                    "identifier": "prod-postgres",
                    "storage_encrypted": true,
                    "publicly_accessible": false,
                    "deletion_protection": true
                }
            }
        }]
    }
}

# DELETE actions must not trigger deny (Terraform destroying a resource is fine)
test_allow_plan_delete_action_skipped if {
    count(deny) == 0 with input as {
        "format_version": "1.1",
        "resource_changes": [{
            "address": "aws_s3_bucket.old-bucket",
            "type": "aws_s3_bucket",
            "name": "old-bucket",
            "change": {
                "actions": ["delete"],
                "after": null
            }
        }]
    }
}
