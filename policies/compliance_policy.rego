package policies.compliance_policy

# Default allow for compliance policy
default allow = true

# Block images with compliance violations
allow = false if {
    has_compliance_violations
}

# PCI DSS compliance - block images with unencrypted sensitive data
allow = false if {
    requires_pci_dss
    not pci_dss_compliant
}

# GDPR compliance - block images processing personal data
allow = false if {
    processes_personal_data
    not gdpr_compliant
}

# Helper functions for compliance checks
has_compliance_violations if {
    requires_pci_dss
    not pci_dss_compliant
}

has_compliance_violations if {
    processes_personal_data
    not gdpr_compliant
}

# PCI DSS requirements
requires_pci_dss if {
    input.deployment_context.team == "payment"
    input.deployment_context.namespace == "production"
}

pci_dss_compliant if {
    input.scan_results.summary.critical == 0
    input.signature_verified == true
    approved_base_image(input.image)
}

# GDPR requirements
processes_personal_data if {
    input.deployment_context.team == "user-data"
    input.deployment_context.namespace == "production"
}

gdpr_compliant if {
    input.scan_results.summary.critical == 0
    input.signature_verified == true
    approved_base_image(input.image)
}

# Approved base images for compliance (subset of main approved list)
approved_base_images = {
    "alpine:3.18",
    "alpine:3.17",
    "registry.access.redhat.com/ubi8/ubi:latest",
    "registry.access.redhat.com/ubi9/ubi:latest",
    "debian:11",
    "debian:12"
}

approved_base_image(image) if {
    base_image := get_base_image(image)
    approved_base_images[base_image]
}

get_base_image(image) = base_image if {
    parts := split(image, "/")
    last_part := parts[count(parts)-1]
    base_image := last_part
}

# Reason for blocking
reason = "PCI DSS compliance violation: critical vulnerabilities or missing signature" if {
    requires_pci_dss
    not pci_dss_compliant
}

reason = "GDPR compliance violation: critical vulnerabilities or missing signature" if {
    processes_personal_data
    not gdpr_compliant
}

# Policy identifier
policy_id = "pci_dss_compliance" if {
    requires_pci_dss
    not pci_dss_compliant
}

policy_id = "gdpr_compliance" if {
    processes_personal_data
    not gdpr_compliant
}

# Severity
severity = "CRITICAL" if {
    requires_pci_dss
    not pci_dss_compliant
}

severity = "CRITICAL" if {
    processes_personal_data
    not gdpr_compliant
}
