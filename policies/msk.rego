package main
import rego.v1

required_tags := {"Environment", "Project", "Owner", "CostCenter", "ManagedBy", "Repo"}

regulated_environments := {"prod", "staging"}

resources := [rc | some rc in input.resource_changes; rc.mode == "managed"; rc.change.after != null]

clusters := [rc | some rc in resources; rc.type == "aws_msk_cluster"]

environment(rc) := object.get(object.get(rc.change.after, "tags", {}), "Environment", "")

deny contains "No MSK cluster in plan" if {
    count(clusters) == 0
}

deny contains sprintf("%s missing tag %s", [rc.address, key]) if {
    some rc in resources
    rc.type in {"aws_msk_cluster", "aws_cloudwatch_log_group", "aws_security_group"}
    some key in required_tags
    object.get(object.get(rc.change.after, "tags", {}), key, "") == ""
}

secure_msk(v) if {
    v.client_authentication[0].sasl[0].iam == true
    v.client_authentication[0].sasl[0].scram == false
    v.client_authentication[0].unauthenticated == false
    v.encryption_info[0].encryption_in_transit[0].client_broker == "TLS"
    v.encryption_info[0].encryption_in_transit[0].in_cluster == true
    startswith(v.encryption_info[0].encryption_at_rest_kms_key_arn, "arn:")
    v.broker_node_group_info[0].connectivity_info[0].public_access[0].type == "DISABLED"
    startswith(v.broker_node_group_info[0].instance_type, "kafka.m")
    v.logging_info[0].broker_logs[0].cloudwatch_logs[0].enabled == true
}

deny contains sprintf("%s violates private IAM/TLS/KMS/logging baseline", [rc.address]) if {
    some rc in clusters
    not secure_msk(rc.change.after)
}

secure_logs(v) if {
    startswith(v.kms_key_id, "arn:")
    v.retention_in_days > 0
}

deny contains sprintf("%s requires a CMK and finite retention", [rc.address]) if {
    some rc in resources
    rc.type == "aws_cloudwatch_log_group"
    not secure_logs(rc.change.after)
}

# storage_autoscaling_enabled = false removes the scaling policy from the plan.
deny contains sprintf("%s: storage autoscaling must be enabled in %s", [rc.address, environment(rc)]) if {
    some rc in clusters
    environment(rc) in regulated_environments
    count([p | some p in resources; p.type == "aws_appautoscaling_policy"]) == 0
}

deny contains sprintf("%s: log retention %d days is below the 180-day minimum for %s", [lg.address, lg.change.after.retention_in_days, environment(rc)]) if {
    some rc in clusters
    environment(rc) in regulated_environments
    some lg in resources
    lg.type == "aws_cloudwatch_log_group"
    lg.change.after.retention_in_days < 180
}

s3_logs_enabled(v) if {
    v.logging_info[0].broker_logs[0].s3[0].enabled == true
}

deny contains sprintf("%s: S3 broker log archive must be enabled in prod", [rc.address]) if {
    some rc in clusters
    environment(rc) == "prod"
    not s3_logs_enabled(rc.change.after)
}

warn contains sprintf("%s: no MSK Replicator in prod; confirm the DR plan covers this cluster", [rc.address]) if {
    some rc in clusters
    environment(rc) == "prod"
    count([r | some r in resources; r.type == "aws_msk_replicator"]) == 0
}
