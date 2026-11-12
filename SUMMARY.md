# terraform-aws-msk — What Changed in v2.0.0

This document summarises what was missing in the original module, what was fixed, and what was added. It is written for a lead architect or technical reviewer.

---

## Critical fix

### Provider block in module root (BREAKING)
**What was wrong:** The module declared a `provider "aws"` block with `region = "ap-south-1"` and empty credentials. In Terraform, a child module's own provider overrides the caller's provider entirely — meaning every consumer's cluster would land in `ap-south-1` regardless of what region they configured, and their `assume_role`, `default_tags` and profile settings would be ignored. The module also could not be used with `count`, `for_each` or `depends_on`.
**What was fixed:** The provider block was removed. Consumers configure the provider in their root module as Terraform requires.

---

## Security fixes

### No broker configuration (HIGH)
**What was missing:** The original module had no `aws_msk_configuration` resource. Clusters ran on the MSK default configuration, so replication factor, minimum in-sync replicas, unclean leader election and topic auto-creation were whatever MSK chose for that Kafka version and AZ count, not an explicit, reviewed baseline.
**What was added:** A hardened `aws_msk_configuration` is now always created with these defaults: `auto.create.topics.enable = false`, `default.replication.factor = 3`, `min.insync.replicas = 2`, `unclean.leader.election.enable = false`. Consumers can override individual properties with the `server_properties` variable; the hardened values remain unless explicitly overridden.

### No authentication options beyond IAM (MEDIUM)
**What was missing:** SASL/SCRAM and mTLS were hardcoded off with no way to enable them, making the module unusable for non-JVM clients and third-party connectors.
**What was added:** `scram_enabled` + `scram_secret_arns` for SASL/SCRAM, and `tls_ca_arns` for mTLS. Both default to off. IAM remains always on.

### Module-owned security group (MEDIUM)
**What was missing:** The module accepted a list of caller-supplied security group IDs. Callers could pass groups with open ingress rules, including 0.0.0.0/0, with no warning.
**What was added:** The module now creates the broker security group with no ingress rules at all. Callers grant access explicitly with `aws_vpc_security_group_ingress_rule` resources targeting the `security_group_id` output. This makes network access to brokers auditable and intentional.

---

## Compliance fixes

### Log retention below PCI-DSS and RBI minimums (HIGH)
**What was wrong:** The default retention was 90 days. PCI-DSS 10.5.1 requires 12 months. The CERT-In Directions of April 2022 require 180 days for ICT system logs in India. The validation also accepted values as low as 1 day.
**What was fixed:** `log_retention_days` is now a required variable with no default — consumers must choose — and values below 30 days are rejected. The description shows the PCI-DSS and CERT-In requirements. The OPA policy blocks any prod or staging plan with retention below 180 days.

### No S3 log archive (HIGH)
**What was missing:** Broker logs went to CloudWatch only. CloudWatch is an operational log destination, not a compliance archive — it is expensive at high retention, and log groups can be deleted.
**What was added:** `s3_logs_enabled` + `s3_logs_bucket` + `s3_logs_prefix` route broker logs to an S3 bucket (intended for the central log-archive account). The OPA policy makes S3 logs mandatory in `prod`.

### No storage autoscaling (HIGH)
**What was missing:** EBS volumes had a fixed size with no autoscaling. A full disk is the most common cause of MSK broker unavailability.
**What was added:** `aws_appautoscaling_target` + `aws_appautoscaling_policy` are created by default, targeting 60% utilisation with scale-in disabled. The cluster ignores Terraform drift on volume size so autoscaled volumes are never "shrunk" back. The OPA policy blocks prod/staging plans with autoscaling off.

> **Where the OPA rules apply:** the policies run in this repository's CI against the module's own mock plan. They gate client deployments only when the client pipeline runs `conftest` with these policies against its own plan.

---

## Enterprise features added

### MSK Replicator for DR
**What was missing:** No cross-cluster replication option.
**What was added:** `replicator_enabled` creates an `aws_msk_replicator` with a least-privilege IAM role (scoped with `aws:SourceAccount`) and a self-referencing security group rule. The target cluster must be in the same region, because AWS creates the replicator in the target's region; cross-region DR is deployed from the DR region's stack. The OPA policy warns (does not block) when prod has no replicator, prompting the team to confirm DR coverage.

### CloudWatch alarms
**What was missing:** No alarms. Consumers were told to set up monitoring themselves.
**What was added:** When `alarm_sns_topic_arn` is set, the module creates five alarms: disk usage (>85%), CPU (>70%), under-replicated partitions (>0), offline partitions (>0), and active controller count (<1). Disk, CPU and URP alarms aggregate across all brokers using metric math, which caps them at 9 brokers (CloudWatch's 10-metric limit per alarm).

### Tiered storage
**What was missing:** `storage_mode` was hardcoded to `LOCAL`.
**What was added:** `storage_mode` is now a required variable. `TIERED` offloads cold segments to S3, reducing EBS cost for high-retention clusters. A precondition enforces that tiered storage is only used with compatible Kafka versions (3.6.0, 3.7.x.kraft) and non-t3 instance types.

### Prometheus open monitoring
**What was missing:** JMX and Node exporters were off with no variable to enable them.
**What was added:** `open_monitoring_enabled` defaults to `true`. Both exporters are enabled by default for Prometheus scraping (Grafana, Thanos, etc.).

### Graviton3 instance types
**What was missing:** The default instance type was `kafka.m5.large` (x86). Graviton3 (`kafka.m7g.*`) is approximately 20% cheaper and performs better.
**What was added:** `kafka.m7g.*` types were already allowed; they are now the documented recommendation. `broker_instance_type` is a required variable so consumers make an explicit, informed choice.

### KRaft-mode Kafka
**What was missing:** KRaft versions were not in the validation list and not documented.
**What was added:** `3.7.x.kraft` is the first option in the validation list and the recommended version. KRaft removes the ZooKeeper dependency entirely.

---

## OPA / policy improvements

| Rule | Before | After |
|------|--------|-------|
| Environment value | Not checked (any non-empty `Environment` tag) | `environment` variable validated as prod / staging / dev / sandbox and written to the tag |
| Storage autoscaling | Not checked | Blocked in prod and staging |
| Log retention | Only required to be finite | Blocked below 180 days in prod and staging |
| S3 log archive | Not checked | Blocked in prod |
| MSK Replicator | Not checked | Warn in prod (does not block, requires team acknowledgement) |
| Provider block in module root | Not checked | New module_files policy rejects any provider block |

---

## Test coverage

| Test file | Before | After |
|-----------|--------|-------|
| unit.tftest.hcl | 13 runs: 2 positive, 11 rejection cases | 24 runs: 6 positive (defaults, tag protection, overrides, optional features, SCRAM/mTLS, replicator), 18 rejection cases |
| contract.tftest.hcl | Checked old outputs | Updated to new output names and types |
| mocks/aws.tfmock.hcl | Minimal mocks | Full mock set for all new resources |
| policies/msk_test.rego | 4 tests | 13 tests including new policy rules |
| policies/module_files_test.rego | Did not exist | 2 tests |

All 25 Terraform test runs (24 unit + 1 contract) pass on AWS provider 5.80.0 and 6.73.0. The Rego tests have not yet been executed; they run in CI via `conftest verify`.

---

## What still needs a live AWS run

- The `aws:SourceAccount` condition on the replicator IAM trust policy
- Per-broker alarm metric queries (broker IDs are assigned at cluster creation time)
- Storage autoscaling target registration (requires a live cluster ARN)
- Tiered storage behaviour with `3.7.x.kraft`

These cannot be validated with mock providers. Run the integration test suite (`tests/integration/`) against a real AWS account before releasing v2.0.0.

---

*Generated by Devotica automated module review — 2026-11-12*
