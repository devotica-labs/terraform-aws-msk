package main
import rego.v1

test_empty_plan_denied if {
    count(deny) > 0 with input as {"resource_changes": []}
}
test_insecure_cluster_denied if {
    count(deny) > 0 with input as {"resource_changes": [{"address": "aws_msk_cluster.bad", "type": "aws_msk_cluster", "mode": "managed", "change": {"after": {"tags": {}}}}]}
}
test_unencrypted_logs_rejected if {
    not secure_logs({"kms_key_id": "", "retention_in_days": 90})
}
test_encrypted_logs_accepted if {
    secure_logs({"kms_key_id": "arn:aws:kms:ap-south-1:123456789012:key/example", "retention_in_days": 90})
}

cluster(env, s3_enabled) := {
    "address": "aws_msk_cluster.this", "type": "aws_msk_cluster", "mode": "managed",
    "change": {"after": {
        "tags": {"Environment": env},
        "logging_info": [{"broker_logs": [{"s3": [{"enabled": s3_enabled}]}]}],
    }},
}

log_group(days) := {
    "address": "aws_cloudwatch_log_group.broker", "type": "aws_cloudwatch_log_group", "mode": "managed",
    "change": {"after": {"retention_in_days": days, "kms_key_id": "arn:aws:kms:ap-south-1:123456789012:key/example", "tags": {}}},
}

autoscaling := {"address": "aws_appautoscaling_policy.msk_storage[0]", "type": "aws_appautoscaling_policy", "mode": "managed", "change": {"after": {}}}

replicator := {"address": "aws_msk_replicator.this[0]", "type": "aws_msk_replicator", "mode": "managed", "change": {"after": {}}}

test_prod_without_autoscaling_denied if {
    "aws_msk_cluster.this: storage autoscaling must be enabled in prod" in deny with input as {"resource_changes": [cluster("prod", true), log_group(365)]}
}
test_staging_without_autoscaling_denied if {
    "aws_msk_cluster.this: storage autoscaling must be enabled in staging" in deny with input as {"resource_changes": [cluster("staging", false), log_group(365)]}
}
test_dev_without_autoscaling_allowed if {
    not "aws_msk_cluster.this: storage autoscaling must be enabled in dev" in deny with input as {"resource_changes": [cluster("dev", false), log_group(30)]}
}
test_prod_short_retention_denied if {
    "aws_cloudwatch_log_group.broker: log retention 90 days is below the 180-day minimum for prod" in deny with input as {"resource_changes": [cluster("prod", true), log_group(90), autoscaling]}
}
test_staging_180_retention_allowed if {
    count([m | some m in deny; contains(m, "below the 180-day minimum")]) == 0 with input as {"resource_changes": [cluster("staging", false), log_group(180), autoscaling]}
}
test_prod_without_s3_logs_denied if {
    "aws_msk_cluster.this: S3 broker log archive must be enabled in prod" in deny with input as {"resource_changes": [cluster("prod", false), log_group(365), autoscaling]}
}
test_staging_without_s3_logs_allowed if {
    count([m | some m in deny; contains(m, "S3 broker log archive")]) == 0 with input as {"resource_changes": [cluster("staging", false), log_group(365), autoscaling]}
}
test_prod_without_replicator_warns if {
    count(warn) == 1 with input as {"resource_changes": [cluster("prod", true), log_group(365), autoscaling]}
}
test_prod_with_replicator_no_warning if {
    count(warn) == 0 with input as {"resource_changes": [cluster("prod", true), log_group(365), autoscaling, replicator]}
}
