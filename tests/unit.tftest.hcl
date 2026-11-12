mock_provider "aws" {
  source = "./tests/mocks"
}
variables {
  name                        = "msk-test"
  environment                 = "prod"
  kafka_version               = "3.7.x.kraft"
  broker_instance_type        = "kafka.m7g.large"
  number_of_broker_nodes      = 3
  availability_zone_count     = 3
  broker_storage_gb           = 500
  storage_mode                = "TIERED"
  vpc_id                      = "vpc-11111111"
  private_subnet_ids          = ["subnet-11111111", "subnet-22222222", "subnet-33333333"]
  log_retention_days          = 365
  msk_kms_key_arn             = "arn:aws:kms:ap-south-1:123456789012:key/11111111-1111-1111-1111-111111111111"
  cloudwatch_logs_kms_key_arn = "arn:aws:kms:ap-south-1:123456789012:key/22222222-2222-2222-2222-222222222222"
  s3_logs_enabled             = true
  s3_logs_bucket              = "log-archive-test"
  alarm_sns_topic_arn         = "arn:aws:sns:ap-south-1:123456789012:alerts"
  tags                        = { Project = "msk", Owner = "platform", CostCenter = "engineering", Repo = "terraform-aws-msk" }
}
override_data {
  target = data.aws_subnet.selected["subnet-11111111"]
  values = { availability_zone_id = "aps1-az1", vpc_id = "vpc-11111111", map_public_ip_on_launch = false }
}
override_data {
  target = data.aws_subnet.selected["subnet-22222222"]
  values = { availability_zone_id = "aps1-az2", vpc_id = "vpc-11111111", map_public_ip_on_launch = false }
}
override_data {
  target = data.aws_subnet.selected["subnet-33333333"]
  values = { availability_zone_id = "aps1-az3", vpc_id = "vpc-11111111", map_public_ip_on_launch = false }
}

# Exported by scripts/export_mock_plan.py for the OPA gate; keep this run compliant for prod.
run "secure_defaults" {
  command = plan
  assert {
    condition     = aws_msk_cluster.this.client_authentication[0].sasl[0].iam && !aws_msk_cluster.this.client_authentication[0].sasl[0].scram && !aws_msk_cluster.this.client_authentication[0].unauthenticated
    error_message = "IAM must be the only authentication method by default."
  }
  assert {
    condition     = length(aws_msk_cluster.this.client_authentication[0].tls) == 0
    error_message = "mTLS must be off unless tls_ca_arns is set."
  }
  assert {
    condition     = aws_msk_cluster.this.encryption_info[0].encryption_in_transit[0].client_broker == "TLS" && aws_msk_cluster.this.encryption_info[0].encryption_in_transit[0].in_cluster
    error_message = "TLS must protect client and inter-broker traffic."
  }
  assert {
    condition     = aws_msk_cluster.this.encryption_info[0].encryption_at_rest_kms_key_arn == var.msk_kms_key_arn
    error_message = "Broker CMK must match the caller input."
  }
  assert {
    condition     = aws_msk_cluster.this.broker_node_group_info[0].connectivity_info[0].public_access[0].type == "DISABLED"
    error_message = "Public access must stay disabled."
  }
  assert {
    condition     = aws_msk_cluster.this.logging_info[0].broker_logs[0].cloudwatch_logs[0].enabled && aws_cloudwatch_log_group.broker.kms_key_id == var.cloudwatch_logs_kms_key_arn && aws_cloudwatch_log_group.broker.retention_in_days == 365
    error_message = "Broker logging must use an encrypted CloudWatch log group with the requested retention."
  }
  assert {
    condition     = aws_msk_cluster.this.logging_info[0].broker_logs[0].s3[0].enabled && aws_msk_cluster.this.logging_info[0].broker_logs[0].s3[0].bucket == "log-archive-test"
    error_message = "S3 log archive must be wired when enabled."
  }
  assert {
    condition     = aws_msk_cluster.this.open_monitoring[0].prometheus[0].jmx_exporter[0].enabled_in_broker && aws_msk_cluster.this.open_monitoring[0].prometheus[0].node_exporter[0].enabled_in_broker
    error_message = "Prometheus exporters must be on by default."
  }
  assert {
    condition     = aws_msk_cluster.this.storage_mode == "TIERED" && aws_msk_cluster.this.enhanced_monitoring == "PER_BROKER"
    error_message = "Storage mode and monitoring level must follow inputs/defaults."
  }
  assert {
    condition     = length(aws_appautoscaling_policy.msk_storage) == 1 && aws_appautoscaling_policy.msk_storage[0].target_tracking_scaling_policy_configuration[0].target_value == 60 && aws_appautoscaling_policy.msk_storage[0].target_tracking_scaling_policy_configuration[0].disable_scale_in
    error_message = "Storage autoscaling must be on by default, targeting 60% with scale-in disabled."
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.msk_disk) == 1 && length(aws_cloudwatch_metric_alarm.msk_cpu) == 1 && length(aws_cloudwatch_metric_alarm.msk_urp) == 1 && length(aws_cloudwatch_metric_alarm.msk_offline_partitions) == 1 && length(aws_cloudwatch_metric_alarm.msk_active_controller) == 1
    error_message = "All five alarms must exist when alarm_sns_topic_arn is set."
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.msk_disk[0].metric_query) == 4
    error_message = "Disk alarm must query every broker plus one expression."
  }
  assert {
    condition     = strcontains(aws_msk_configuration.this.server_properties, "min.insync.replicas = 2") && strcontains(aws_msk_configuration.this.server_properties, "auto.create.topics.enable = false") && strcontains(aws_msk_configuration.this.server_properties, "unclean.leader.election.enable = false")
    error_message = "Hardened broker defaults must be present."
  }
  assert {
    condition     = aws_msk_cluster.this.tags["ManagedBy"] == "devotica-terraform" && aws_msk_cluster.this.tags["Module"] == "terraform-aws-msk" && aws_msk_cluster.this.tags["Environment"] == "prod"
    error_message = "Module tags must be applied."
  }
  assert {
    condition     = length(aws_msk_replicator.this) == 0 && length(aws_iam_role.replicator) == 0 && length(aws_msk_scram_secret_association.this) == 0
    error_message = "Optional replicator and SCRAM resources must be off by default."
  }
}

run "module_tags_cannot_be_overridden" {
  command = plan
  variables {
    tags = { ManagedBy = "someone-else", Module = "x", Environment = "dev", Project = "msk", Owner = "platform", CostCenter = "engineering", Repo = "terraform-aws-msk" }
  }
  assert {
    condition     = aws_msk_cluster.this.tags["ManagedBy"] == "devotica-terraform" && aws_msk_cluster.this.tags["Module"] == "terraform-aws-msk" && aws_msk_cluster.this.tags["Environment"] == "prod"
    error_message = "Caller tags must not override module tags."
  }
}

run "server_properties_override" {
  command = plan
  variables {
    server_properties = { "log.retention.hours" = "720", "num.partitions" = "6" }
  }
  assert {
    condition     = strcontains(aws_msk_configuration.this.server_properties, "log.retention.hours = 720") && strcontains(aws_msk_configuration.this.server_properties, "num.partitions = 6") && strcontains(aws_msk_configuration.this.server_properties, "min.insync.replicas = 2")
    error_message = "Caller properties must override defaults while keeping the rest."
  }
}

run "optional_features_off" {
  command = plan
  variables {
    storage_mode                = "LOCAL"
    storage_autoscaling_enabled = false
    open_monitoring_enabled     = false
    s3_logs_enabled             = false
    alarm_sns_topic_arn         = null
  }
  assert {
    condition     = length(aws_appautoscaling_target.msk_storage) == 0 && length(aws_cloudwatch_metric_alarm.msk_disk) == 0
    error_message = "Autoscaling and alarms must be removable."
  }
  assert {
    condition     = length(aws_msk_cluster.this.logging_info[0].broker_logs[0].s3) == 0 && !aws_msk_cluster.this.open_monitoring[0].prometheus[0].jmx_exporter[0].enabled_in_broker
    error_message = "S3 logs and Prometheus must be removable."
  }
  assert {
    condition     = aws_msk_cluster.this.logging_info[0].broker_logs[0].cloudwatch_logs[0].enabled
    error_message = "CloudWatch broker logging is not optional."
  }
}

run "scram_and_mtls" {
  command = plan
  variables {
    scram_enabled     = true
    scram_secret_arns = ["arn:aws:secretsmanager:ap-south-1:123456789012:secret:AmazonMSK_test-AbCdEf"]
    tls_ca_arns       = ["arn:aws:acm-pca:ap-south-1:123456789012:certificate-authority/44444444-4444-4444-4444-444444444444"]
  }
  assert {
    condition     = aws_msk_cluster.this.client_authentication[0].sasl[0].scram && aws_msk_cluster.this.client_authentication[0].sasl[0].iam && length(aws_msk_scram_secret_association.this) == 1
    error_message = "SCRAM must be added alongside IAM."
  }
  assert {
    condition     = length(aws_msk_cluster.this.client_authentication[0].tls) == 1
    error_message = "mTLS block must be present when CAs are supplied."
  }
}

run "replicator_same_region" {
  command = apply # Mock provider only: no AWS API calls.
  variables {
    replicator_enabled                   = true
    replicator_target_cluster_arn        = "arn:aws:kafka:ap-south-1:123456789012:cluster/msk-dr/55555555-5555-5555-5555-555555555555-1"
    replicator_target_subnet_ids         = ["subnet-44444444"]
    replicator_target_security_group_ids = ["sg-44444444"]
  }
  assert {
    condition     = length(aws_msk_replicator.this) == 1 && length(aws_vpc_security_group_ingress_rule.replicator_self) == 1
    error_message = "Replicator and its self-referencing ingress rule must be created."
  }
  assert {
    condition     = jsondecode(aws_iam_role.replicator[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "Replicator trust policy must be scoped with aws:SourceAccount."
  }
  assert {
    condition     = output.replicator_arn != null
    error_message = "replicator_arn output must be set."
  }
}

run "reject_replicator_cross_region" {
  command = plan
  variables {
    replicator_enabled                   = true
    replicator_target_cluster_arn        = "arn:aws:kafka:ap-southeast-1:123456789012:cluster/msk-dr/55555555-5555-5555-5555-555555555555-1"
    replicator_target_subnet_ids         = ["subnet-44444444"]
    replicator_target_security_group_ids = ["sg-44444444"]
  }
  expect_failures = [aws_msk_replicator.this[0]]
}

run "reject_replicator_without_target" {
  command = plan
  variables {
    replicator_enabled = true
  }
  expect_failures = [aws_msk_cluster.this]
}

run "reject_subnet_az_mismatch" {
  command = plan
  variables {
    availability_zone_count = 2
    number_of_broker_nodes  = 4
  }
  expect_failures = [aws_msk_cluster.this]
}

run "reject_uneven_brokers" {
  command = plan
  variables {
    number_of_broker_nodes = 4
  }
  expect_failures = [aws_msk_cluster.this]
}

run "reject_fractional_brokers" {
  command = plan
  variables {
    number_of_broker_nodes = 3.5
  }
  expect_failures = [var.number_of_broker_nodes]
}

run "reject_shared_az" {
  command = plan
  override_data {
    target = data.aws_subnet.selected["subnet-22222222"]
    values = { availability_zone_id = "aps1-az1", vpc_id = "vpc-11111111", map_public_ip_on_launch = false }
  }
  expect_failures = [aws_msk_cluster.this]
}

run "reject_public_ip" {
  command = plan
  override_data {
    target = data.aws_subnet.selected["subnet-22222222"]
    values = { availability_zone_id = "aps1-az2", vpc_id = "vpc-11111111", map_public_ip_on_launch = true }
  }
  expect_failures = [aws_msk_cluster.this]
}

run "reject_subnet_outside_vpc" {
  command = plan
  override_data {
    target = data.aws_subnet.selected["subnet-22222222"]
    values = { availability_zone_id = "aps1-az2", vpc_id = "vpc-22222222", map_public_ip_on_launch = false }
  }
  expect_failures = [aws_msk_cluster.this]
}

run "reject_tiered_on_old_kafka" {
  command = plan
  variables {
    kafka_version = "3.5.1"
  }
  expect_failures = [aws_msk_cluster.this]
}

run "reject_s3_logs_without_bucket" {
  command = plan
  variables {
    s3_logs_bucket = null
  }
  expect_failures = [aws_msk_cluster.this]
}

run "reject_scram_without_secrets" {
  command = plan
  variables {
    scram_enabled = true
  }
  expect_failures = [aws_msk_cluster.this]
}

run "reject_autoscaling_max_below_storage" {
  command = plan
  variables {
    storage_autoscaling_max_gb = 400
  }
  expect_failures = [aws_msk_cluster.this]
}

run "reject_alarms_over_nine_brokers" {
  command = plan
  variables {
    number_of_broker_nodes = 12
  }
  expect_failures = [aws_cloudwatch_metric_alarm.msk_disk[0], aws_cloudwatch_metric_alarm.msk_cpu[0], aws_cloudwatch_metric_alarm.msk_urp[0]]
}

run "reject_invalid_kafka_version" {
  command = plan
  variables {
    kafka_version = "3.4.0"
  }
  expect_failures = [var.kafka_version]
}

run "reject_short_retention" {
  command = plan
  variables {
    log_retention_days = 14
  }
  expect_failures = [var.log_retention_days]
}

run "reject_key_alias" {
  command = plan
  variables {
    msk_kms_key_arn = "alias/msk"
  }
  expect_failures = [var.msk_kms_key_arn]
}

run "reject_uppercase_name" {
  command = plan
  variables {
    name = "MSK-Test"
  }
  expect_failures = [var.name]
}

run "reject_unknown_environment" {
  command = plan
  variables {
    environment = "production"
  }
  expect_failures = [var.environment]
}
