package policies.base_image_policy

# Default allow for base image policy
default allow = true

# Block non-approved base images
allow = false if {
    not approved_base_image(input.image)
}

# Approved base images list
approved_base_images = {
    "alpine:latest",
    "alpine:3.18",
    "alpine:3.17",
    "ubuntu:20.04",
    "ubuntu:22.04",
    "debian:11",
    "debian:12",
    "registry.access.redhat.com/ubi8/ubi:latest",
    "registry.access.redhat.com/ubi9/ubi:latest",
    "mcr.microsoft.com/dotnet/runtime:7.0",
    "mcr.microsoft.com/dotnet/runtime:8.0",
    "node:18-alpine",
    "node:20-alpine",
    "python:3.11-slim",
    "python:3.12-slim",
    "golang:1.21-alpine",
    "golang:1.22-alpine"
}

# Check if image uses approved base image
approved_base_image(image) if {
    base_image := get_base_image(image)
    approved_base_images[base_image]
}

# Extract base image name (simplified - assumes format registry/image:tag)
get_base_image(image) = base_image if {
    parts := split(image, "/")
    last_part := parts[count(parts)-1]
    base_image := last_part
}

# Allow any image in development environment
allow = true if {
    input.deployment_context.environment == "dev"
    input.deployment_context.namespace == "development"
}

# Reason for blocking
reason = sprintf("Base image '%s' is not in approved list", [input.image]) if {
    not approved_base_image(input.image)
    not is_dev_environment
}

reason = "Base image restrictions apply in production environment" if {
    not approved_base_image(input.image)
    is_prod_environment
}

# Helper functions
is_dev_environment if {
    input.deployment_context.environment == "dev"
    input.deployment_context.namespace == "development"
}

is_prod_environment if {
    input.deployment_context.environment == "prod"
    input.deployment_context.namespace == "production"
}

# Policy identifier
policy_id = "approved_base_images" if {
    not allow
}

# Severity
severity = "HIGH" if {
    is_prod_environment
}

severity = "LOW" if {
    is_dev_environment
}
