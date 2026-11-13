# Changelog

## 0.1.0 (2026-11-13)


### Features

* initial AWS MSK module ([da4c749](https://github.com/devotica-labs/terraform-aws-msk/commit/da4c749430f97ee265e396814b8d2239368472e0))

## [2.0.0] - 2026-11-12

### Breaking Changes
- Removed `provider "aws"` block from `versions.tf`. The module no longer declares a provider.
  Consumers must configure the AWS provider in their root module.
- `log_retention_days` default removed — now a required variable. Values below 30 days are rejected.
- `broker_instance_type` default (`kafka.m5.large`) removed — now a required variable.
- `availability_zone_count` (new) and `number_of_broker_nodes` are now required variables.
- New required inputs: `vpc_id`, `broker_storage_gb`, `storage_mode`.
- Renamed inputs: `kms_key_arn` → `msk_kms_key_arn`, `cloudwatch_kms_key_arn` → `cloudwatch_logs_kms_key_arn`,
  `ebs_volume_size` → `broker_storage_gb`.
- Removed input `security_group_ids`: the module now creates the broker security group (`aws_security_group.msk`)
  with no ingress. Grant client access with `aws_vpc_security_group_ingress_rule` on the `security_group_id` output.
- `kafka_version` is restricted to `3.7.x.kraft`, `3.6.0`, `3.5.1` and `2.8.1`.
- `name` must now be lowercase alphanumeric and hyphens.
- `tags` is now optional and no longer validates the Devotica tag set; the OPA gate still enforces it.
  New `environment` input (`prod | staging | dev | sandbox`, default `prod`) sets the `Environment` tag,
  which callers can no longer override. `ManagedBy` changed from `Terraform` to `devotica-terraform`; `Module` tag added.
- Broker log group renamed from `/aws/msk/<name>/broker` to `/aws/msk/<name>`. Existing log groups are replaced on
  upgrade; export or `terraform state mv`/import before applying if the old logs must be kept.
- Outputs removed: `cluster_uuid`, `current_version`, `kms_key_arn`, `security_group_ids`, `private_subnet_ids`.
  Outputs renamed: `cloudwatch_log_group_name` → `log_group_name`, `cloudwatch_log_group_arn` → `log_group_arn`.
  `bootstrap_brokers_sasl_iam` is now marked sensitive.
- Minimum Terraform version raised to `>= 1.11.0`.
- AWS provider constraint changed from `~> 5.30` to `>= 5.80, < 7.0` (tested on 5.80.0 and 6.73.0).

### Added
- `aws_msk_configuration` with hardened broker defaults (auto-create off, RF=3, min ISR=2, unclean election off).
- Storage autoscaling (`aws_appautoscaling_target` + `aws_appautoscaling_policy`) enabled by default.
- S3 broker log delivery option (`s3_logs_enabled`, `s3_logs_bucket`, `s3_logs_prefix`).
- Prometheus open monitoring (`open_monitoring_enabled`, default true).
- SASL/SCRAM authentication option (`scram_enabled`, `scram_secret_arns`).
- mTLS authentication option (`tls_ca_arns`).
- MSK Replicator (`replicator_enabled`, `replicator_target_cluster_arn`, `replicator_target_subnet_ids`,
  `replicator_target_security_group_ids`, `replicator_topics_to_replicate`). The target must be in the same
  region as the source; cross-region replicators must be created from the target region's stack.
- Replicator IAM role with `aws:SourceAccount` condition and a least-privilege inline policy scoped to the
  source and target clusters, plus a self-referencing security group rule on TCP 9098.
- CloudWatch alarms for disk, CPU, under-replicated partitions, offline partitions, and active controller.
- Tiered storage support (`storage_mode` variable).
- `server_properties` override map for custom broker configuration.
- Graviton3 (`kafka.m7g.*`) documented as the recommended broker family.
- KRaft-mode Kafka version (`3.7.x.kraft`) added to validation.
- `data.aws_caller_identity` for policy conditions.
- OPA rules: autoscaling required and log retention >= 180 days in prod/staging, S3 log archive required in prod,
  warning when prod has no replicator, and a `module_files` policy that rejects provider blocks in the module root.

### Fixed
- `log_retention_days` validation now only accepts valid CloudWatch retention values of 30 days or more.
- Plan-time preconditions for subnet count vs. AZ count, tiered-storage compatibility, and required companion
  inputs for S3 logs, SCRAM, autoscaling and the replicator.
- CI Terraform version raised from 1.9.5 to 1.11.4 to match `required_version`.

## Unreleased

- Initial MSK Provisioned Standard module with IAM, TLS, CMKs and broker logs.
- Mocked unit/contract tests, isolated manual integration and Devotica workflow integration.
