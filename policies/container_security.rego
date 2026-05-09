package container_security

import data.policies

# Default deny - explicit allow required
default allow = false

# Main decision logic
allow if {
    policies.vulnerability_policy.allow
    policies.signature_policy.allow
    policies.base_image_policy.allow
    policies.compliance_policy.allow
}

# Decision reason
reason = msg if {
    not policies.vulnerability_policy.allow
    msg := policies.vulnerability_policy.reason
}

reason = msg if {
    not policies.signature_policy.allow
    msg := policies.signature_policy.reason
}

reason = msg if {
    not policies.base_image_policy.allow
    msg := policies.base_image_policy.reason
}

reason = msg if {
    not policies.compliance_policy.allow
    msg := policies.compliance_policy.reason
}

# Policy ID for tracking
policy_id = id if {
    not allow
    id := policies.vulnerability_policy.policy_id
}

policy_id = id if {
    not allow
    id := policies.signature_policy.policy_id
}

policy_id = id if {
    not allow
    id := policies.base_image_policy.policy_id
}

policy_id = id if {
    not allow
    id := policies.compliance_policy.policy_id
}

# Severity level
severity = level if {
    not allow
    level := policies.vulnerability_policy.severity
}

severity = level if {
    not allow
    level := policies.signature_policy.severity
}

severity = level if {
    not allow
    level := policies.base_image_policy.severity
}

severity = level if {
    not allow
    level := policies.compliance_policy.severity
}
