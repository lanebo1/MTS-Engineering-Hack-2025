package policies.signature_policy

# Default deny for signature policy - signatures required
default allow = false

# Allow if signature is verified
allow = true if {
    input.signature_verified == true
}

# Allow in development environments with warning
allow = true if {
    input.deployment_context.environment == "dev"
    input.deployment_context.namespace == "development"
}

# Reason for blocking
reason = "Image signature not verified" if {
    input.signature_verified != true
    not is_dev_environment
}

reason = "Image signature verification required for production" if {
    input.signature_verified != true
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
policy_id = "require_signature" if {
    not allow
}

# Severity
severity = "HIGH" if {
    is_prod_environment
}

severity = "MEDIUM" if {
    not is_prod_environment
}
