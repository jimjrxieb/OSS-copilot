# gateway-api.rego — Policy-as-code for Gateway API resources
# Run in CI: conftest test manifests/ --policy policies/conftest/
#
# NIST 800-53: SC-7, SC-8, AC-6

package main

# Deny Gateway listeners on port 443 without HTTPS
deny[msg] {
    input.kind == "Gateway"
    listener := input.spec.listeners[_]
    listener.port == 443
    listener.protocol != "HTTPS"
    msg := sprintf("Gateway '%s' listener '%s' on port 443 must use protocol HTTPS (SC-8)", [input.metadata.name, listener.name])
}

# Deny Gateway listeners on port 443 without TLS certificateRefs
deny[msg] {
    input.kind == "Gateway"
    listener := input.spec.listeners[_]
    listener.port == 443
    listener.protocol == "HTTPS"
    not listener.tls.certificateRefs
    msg := sprintf("Gateway '%s' listener '%s' must specify tls.certificateRefs (SC-8)", [input.metadata.name, listener.name])
}

# Deny HTTPRoute with wildcard hostname
deny[msg] {
    input.kind == "HTTPRoute"
    hostname := input.spec.hostnames[_]
    hostname == "*"
    msg := sprintf("HTTPRoute '%s' must not use wildcard hostname '*' (SC-7)", [input.metadata.name])
}

# Warn: Gateway allowing routes from All namespaces (AC-6 violation)
warn[msg] {
    input.kind == "Gateway"
    listener := input.spec.listeners[_]
    listener.allowedRoutes.namespaces.from == "All"
    msg := sprintf("Gateway '%s' listener '%s' allows routes from ALL namespaces — restrict to Same or Selector (AC-6)", [input.metadata.name, listener.name])
}

# Warn: HTTP listener that is not a redirect-only route
warn[msg] {
    input.kind == "Gateway"
    listener := input.spec.listeners[_]
    listener.protocol == "HTTP"
    listener.port == 80
    listener.allowedRoutes.namespaces.from == "All"
    msg := sprintf("Gateway '%s' HTTP listener '%s' should only serve redirects to HTTPS (SC-8)", [input.metadata.name, listener.name])
}
