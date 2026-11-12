# terraform-aws-msk

> Devotica · AWS Managed Streaming for Apache Kafka (MSK) · Enterprise Module

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

A production-grade Terraform module for deploying Amazon MSK clusters. Designed to be PCI-DSS and RBI-compliant out of the box — encryption, private access, IAM authentication, broker logging and storage autoscaling are all on by default. Clients choose the topology and cost levers; the security baseline is not negotiable.

---

## What this module does

- Deploys MSK broker nodes across 2 or 3 Availability Zones in your private subnets, with TLS encryption and IAM authentication enforced automatically.
- Encrypts broker storage and broker logs with your own KMS keys, so no data is protected by an AWS-managed key.
- Writes broker logs to an encrypted CloudWatch log group, and can also archive them to S3 for long-term compliance retention.
- Applies a hardened Kafka broker configuration (replication factor 3, at least 2 in-sync replicas, no automatic topic creation) that you can extend but not weaken by accident.
- Grows broker storage automatically before disks fill up, and raises CloudWatch alarms on disk, CPU, replication and controller health when you give it an SNS topic.
- Replicates topics and consumer groups to a second cluster with MSK Replicator when you need disaster recovery.

---

## What you must decide (required inputs)

Some inputs have no default on purpose. They control topology, cost and compliance posture, and the right answer depends on your workload, so the module makes you choose. If they are not set in a `.tfvars` file or the module block, Terraform prompts for them during `plan` and `apply`. Each variable's description lists the valid options, the trade-offs, any PCI-DSS or RBI requirement, and the Devotica recommendation in [brackets] — read it in the [Inputs](#inputs) table below before choosing.

| Variable | What it controls | Devotica recommendation |
|---|---|---|
| `name` | Base name for the cluster and every resource it creates | Lowercase service name, e.g. `payments-events` |
| `kafka_version` | Kafka version and mode | `"3.7.x.kraft"` (KRaft, no ZooKeeper) |
| `broker_instance_type` | Broker size and CPU architecture | `"kafka.m7g.large"` (Graviton3) |
| `number_of_broker_nodes` | Total brokers; must be a multiple of the AZ count | `3` (6 for high throughput) |
| `availability_zone_count` | HA topology | `3` (required for PCI-DSS and RBI) |
| `broker_storage_gb` | Starting EBS size per broker | `500` for production |
| `storage_mode` | Local EBS only, or EBS plus S3 tiering | `"TIERED"` for production, `"LOCAL"` for dev |
| `vpc_id` | VPC the brokers run in | A private VPC with no public routes for brokers |
| `private_subnet_ids` | Broker subnets; one per AZ, count must equal `availability_zone_count` | 3 private subnets, one per AZ |
| `log_retention_days` | CloudWatch broker log retention | `365` (PCI-DSS 10.5.1) |
| `msk_kms_key_arn` | Customer-managed key for broker storage | A dedicated MSK key with rotation enabled |
| `cloudwatch_logs_kms_key_arn` | Customer-managed key for the log group | A logs key whose policy allows `logs.<region>.amazonaws.com` |

---

## What is always on (non-negotiable security baseline)

These settings are hardcoded and cannot be changed by passing variables.

| Setting | Value | Why |
|---|---|---|
| Encryption at rest | Customer-managed KMS key | AWS-managed keys are not accepted |
| Client encryption | TLS only | Plaintext and mixed-mode are rejected |
| In-cluster encryption | Enabled | Broker-to-broker traffic is encrypted |
| IAM authentication | Always enabled | The module requires IAM; it cannot be turned off |
| Public broker access | Disabled | Brokers are always private |
| Unauthenticated access | Blocked | The unauthenticated flag is hardcoded false |
| Broker configuration | Hardened defaults applied | RF=3, min ISR=2, auto-create topics off, unclean election off |

---

## Optional features (on by default, can be turned off)

These features are on by default because they are recommended for production. Set them to `false` only if you have a specific reason.

| Feature | Variable | Default | Cost note |
|---|---|---|---|
| Storage autoscaling | `storage_autoscaling_enabled` | `true` | Scales up only; billed for new size |
| Prometheus monitoring | `open_monitoring_enabled` | `true` | No direct cost |
| Per-broker CloudWatch metrics | `enhanced_monitoring` | `PER_BROKER` | ~$0.30/broker/month |

---

## Optional features (off by default, enable when needed)

These features are off because they add cost or complexity. Enable them for production regulated workloads.

| Feature | Variables needed | When to enable |
|---|---|---|
| S3 log archive | `s3_logs_enabled`, `s3_logs_bucket` | Required for PCI-DSS 10.5.1 and CERT-In log retention. Use the central log-archive account bucket. |
| CloudWatch alarms | `alarm_sns_topic_arn` | Set for any production cluster. Creates 5 alarms: disk, CPU, under-replicated partitions, offline partitions, active controller. |
| SASL/SCRAM auth | `scram_enabled`, `scram_secret_arns` | Only if a client cannot use IAM (non-JVM, third-party connectors). Secrets must use a CMK. |
| mTLS auth | `tls_ca_arns` | Zero-trust environments requiring certificate-based client auth. |
| MSK Replicator (DR) | `replicator_enabled`, `replicator_target_cluster_arn`, `replicator_target_subnet_ids`, `replicator_target_security_group_ids` | Active-active DR or multi-cluster. Target must be in the same region. See note below. |
| Custom broker properties | `server_properties` | Override specific Kafka settings. The module's hardened defaults always apply; your values merge on top. |

> **MSK Replicator region note:** AWS creates the replicator in the target cluster's region. This module creates it using your provider, so the target cluster must be in the same region as the source. For cross-region DR, deploy the replicator from the DR region's Terraform stack instead.

---

## Usage

### Minimal example

```hcl
provider "aws" {
  region = "ap-south-1"
}

module "msk" {
  source = "git::https://github.com/devotica-labs/terraform-aws-msk.git?ref=v2.0.0"

  name                    = "orders-events"     # base name for every resource
  kafka_version           = "3.7.x.kraft"       # KRaft mode, no ZooKeeper
  broker_instance_type    = "kafka.m7g.large"   # Graviton3
  number_of_broker_nodes  = 3                   # one broker per AZ
  availability_zone_count = 3                   # 3 AZs for production
  broker_storage_gb       = 500                 # starting size; autoscaling grows it
  storage_mode            = "LOCAL"             # all data on EBS
  vpc_id                  = "vpc-0a1b2c3d4e5f60718"
  private_subnet_ids      = ["subnet-0a1b2c3d4e5f60711", "subnet-0a1b2c3d4e5f60722", "subnet-0a1b2c3d4e5f60733"] # one per AZ
  log_retention_days      = 365                 # PCI-DSS 10.5.1

  msk_kms_key_arn             = "arn:aws:kms:ap-south-1:111122223333:key/0a1b2c3d-1111-2222-3333-444455556666" # broker storage CMK
  cloudwatch_logs_kms_key_arn = "arn:aws:kms:ap-south-1:111122223333:key/0a1b2c3d-7777-8888-9999-000011112222" # log group CMK
}
```

### Production example (PCI-DSS / RBI)

```hcl
module "msk" {
  source = "git::https://github.com/devotica-labs/terraform-aws-msk.git?ref=v2.0.0"

  name        = "payments-events"
  environment = "prod"

  # Topology: Graviton3, one broker per AZ across 3 AZs
  kafka_version           = "3.7.x.kraft"
  broker_instance_type    = "kafka.m7g.large"
  number_of_broker_nodes  = 3
  availability_zone_count = 3
  vpc_id                  = "vpc-0a1b2c3d4e5f60718"
  private_subnet_ids      = ["subnet-0a1b2c3d4e5f60711", "subnet-0a1b2c3d4e5f60722", "subnet-0a1b2c3d4e5f60733"]

  # Storage: tiered to S3, autoscaling up to 2 TiB per broker
  broker_storage_gb                      = 500
  storage_mode                           = "TIERED"
  storage_autoscaling_enabled            = true
  storage_autoscaling_max_gb             = 2000
  storage_autoscaling_target_utilization = 60

  # Encryption: customer-managed keys only
  msk_kms_key_arn             = "arn:aws:kms:ap-south-1:111122223333:key/0a1b2c3d-1111-2222-3333-444455556666"
  cloudwatch_logs_kms_key_arn = "arn:aws:kms:ap-south-1:111122223333:key/0a1b2c3d-7777-8888-9999-000011112222"

  # Logging: 1 year in CloudWatch, archived to the central log-archive bucket
  log_retention_days = 365
  s3_logs_enabled    = true
  s3_logs_bucket     = "devotica-log-archive-ap-south-1"
  s3_logs_prefix     = "msk/payments-events"

  # Monitoring and alerting
  enhanced_monitoring     = "PER_BROKER"
  open_monitoring_enabled = true
  alarm_sns_topic_arn     = "arn:aws:sns:ap-south-1:111122223333:platform-alerts"

  # DR: enable and set replicator_target_* to replicate to a standby cluster
  replicator_enabled = false

  tags = {
    Project    = "payments"
    Owner      = "platform"
    CostCenter = "engineering"
    Repo       = "payments-infra"
  }
}
```

> After applying, attach client access to the security group the module creates:
> ```hcl
> resource "aws_vpc_security_group_ingress_rule" "app_to_msk" {
>   security_group_id            = module.msk.security_group_id
>   referenced_security_group_id = aws_security_group.app.id
>   ip_protocol                  = "tcp"
>   from_port                    = 9098
>   to_port                      = 9098
>   description                  = "App servers to MSK (SASL/IAM)"
> }
> ```

Clients also need an IAM policy that allows `kafka-cluster:Connect` and the topic and group actions they use, scoped to this cluster's ARN. The module does not grant client access. Full working examples are in [`examples/basic`](examples/basic) and [`examples/complete`](examples/complete).

---

## Compliance

| Standard | Requirement | How this module satisfies it |
|---|---|---|
| PCI-DSS 3.5 | Encryption of stored data | CMK enforced for EBS and CloudWatch logs |
| PCI-DSS 4.2.1 | Encryption of data in transit | TLS-only enforced for client and inter-broker traffic |
| PCI-DSS 7.2 | Least-privilege access | IAM authentication enforced; unauthenticated access blocked |
| PCI-DSS 10.5.1 | Audit log retention ≥ 1 year | `log_retention_days` has no default, so the consumer must choose; 365 recommended; S3 archive available. The OPA floor is 180 days, so 1-year retention must be chosen deliberately |
| PCI-DSS 12.10.1 | Incident response plan includes business recovery and continuity | MSK Replicator available for same-region failover; cross-region DR is deployed from the DR region's stack |
| RBI IT Framework | No single point of failure | 3 AZs recommended via `availability_zone_count`. Not enforced by policy: a 2-AZ cluster is accepted |
| CERT-In Directions (Apr 2022) | Log retention ≥ 180 days | OPA policy blocks retention below 180 days in prod/staging |

The OPA policies in [`policies/`](policies) run in this repository's CI against the module's mock plan. To enforce them on a client deployment, run `conftest test` with these policies against that deployment's `terraform show -json` plan output.

---

<!-- BEGIN_TF_DOCS -->
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bootstrap_brokers_sasl_iam"></a> [bootstrap\_brokers\_sasl\_iam](#output\_bootstrap\_brokers\_sasl\_iam) | Private SASL/IAM bootstrap brokers (TCP 9098). |
| <a name="output_bootstrap_brokers_sasl_scram"></a> [bootstrap\_brokers\_sasl\_scram](#output\_bootstrap\_brokers\_sasl\_scram) | Private SASL/SCRAM bootstrap brokers (TCP 9096). Empty unless scram\_enabled is true. |
| <a name="output_bootstrap_brokers_tls"></a> [bootstrap\_brokers\_tls](#output\_bootstrap\_brokers\_tls) | Private TLS bootstrap brokers (TCP 9094). Populated when mTLS (tls\_ca\_arns) is configured. |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | MSK cluster ARN. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | MSK cluster name. |
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | CloudWatch broker log group ARN. |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | CloudWatch broker log group name. |
| <a name="output_replicator_arn"></a> [replicator\_arn](#output\_replicator\_arn) | ARN of the MSK Replicator, or null when replication is disabled. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the broker security group created by the module. Attach aws\_vpc\_security\_group\_ingress\_rule resources to it to grant client access. |
| <a name="output_storage_autoscaling_enabled"></a> [storage\_autoscaling\_enabled](#output\_storage\_autoscaling\_enabled) | Whether EBS storage autoscaling is enabled for the brokers. |
| <a name="output_zookeeper_connect_string"></a> [zookeeper\_connect\_string](#output\_zookeeper\_connect\_string) | ZooKeeper connection string. Empty for KRaft-mode clusters (3.7.x.kraft). |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alarm_sns_topic_arn"></a> [alarm\_sns\_topic\_arn](#input\_alarm\_sns\_topic\_arn) | SNS topic ARN for CloudWatch alarm notifications.<br/>When set, the module creates alarms for: disk usage, CPU, under-replicated partitions,<br/>offline partitions, and active controller count.<br/><br/>[Devotica recommendation: always set for production]<br/>PCI-DSS 10.6.1: Automated alerting on critical system events required. | `string` | `null` | no |
| <a name="input_availability_zone_count"></a> [availability\_zone\_count](#input\_availability\_zone\_count) | Number of Availability Zones to distribute brokers across.<br/><br/>Options:<br/>  2 — Two AZs. Development and cost-sensitive non-production only.<br/>      Warning: losing one AZ in a 2-AZ cluster can block writes if min.insync.replicas=2.<br/>  3 — Three AZs. [Devotica recommendation for all production workloads]<br/>      Required for PCI-DSS and RBI-regulated environments.<br/>      Protects against full AZ failure without impacting write availability.<br/><br/>[Devotica recommendation: 3]<br/>PCI-DSS 2.2.1: High availability configuration required for in-scope systems.<br/>RBI IT Framework: Requires no single point of failure for critical payment infrastructure. | `number` | n/a | yes |
| <a name="input_broker_instance_type"></a> [broker\_instance\_type](#input\_broker\_instance\_type) | EC2 instance type for MSK broker nodes.<br/><br/>Options:<br/>  "kafka.m7g.large"   — Graviton3. Best price-performance for most workloads.<br/>                        [Devotica recommendation for production]<br/>  "kafka.m7g.xlarge"  — Graviton3. High-throughput production clusters.<br/>  "kafka.m5.large"    — x86. Use only if Graviton is not available in your region.<br/>  "kafka.m5.xlarge"   — x86 high-throughput.<br/>  "kafka.t3.small"    — Development and testing only. Not for production.<br/><br/>PCI-DSS: t3.small is not recommended for production. It cannot sustain consistent throughput.<br/>Cost: m7g instances are approximately 20 percent cheaper than equivalent m5. | `string` | n/a | yes |
| <a name="input_broker_storage_gb"></a> [broker\_storage\_gb](#input\_broker\_storage\_gb) | EBS storage per broker in GiB. Applied to each broker node individually.<br/><br/>Guidelines:<br/>  100  — Development / low-volume.<br/>  500  — Standard production (up to ~400 GB usable with 20% headroom).<br/>  1000 — High-volume production or long retention periods.<br/>  2000 — Large-scale clusters with multi-day retention.<br/><br/>[Devotica recommendation: 500 for standard production]<br/>Note: If storage\_mode is TIERED, local storage can be smaller. See storage\_mode.<br/>Cost: EBS gp3 at $0.08/GiB/month per broker. | `number` | n/a | yes |
| <a name="input_cloudwatch_logs_kms_key_arn"></a> [cloudwatch\_logs\_kms\_key\_arn](#input\_cloudwatch\_logs\_kms\_key\_arn) | ARN of a customer-managed KMS key for encrypting the CloudWatch log group. Must be in the same region. Required — AWS-managed keys are not accepted. | `string` | n/a | yes |
| <a name="input_enhanced_monitoring"></a> [enhanced\_monitoring](#input\_enhanced\_monitoring) | Level of enhanced CloudWatch monitoring for MSK brokers.<br/><br/>Options:<br/>  "DEFAULT"              — Basic cluster-level metrics only. Free tier.<br/>  "PER\_BROKER"           — Per-broker metrics. [Devotica recommendation]<br/>  "PER\_TOPIC\_PER\_BROKER" — Per-topic per-broker metrics. High cardinality cost.<br/>  "PER\_TOPIC\_PER\_PARTITION" — Highest granularity. Significant CloudWatch cost.<br/><br/>Cost: PER\_BROKER adds approximately $0.30/broker/month in CloudWatch charges.<br/>      PER\_TOPIC\_* levels can add significant cost for high-partition clusters. | `string` | `"PER_BROKER"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment. Used in resource naming, tags, and OPA policy evaluation.<br/><br/>Options:<br/>  "prod"    — Production. Full compliance checks enforced. [Devotica default]<br/>  "staging" — Pre-production. Compliance checks enforced.<br/>  "dev"     — Development. Relaxed retention and monitoring defaults.<br/>  "sandbox" — Ephemeral. Minimal cost configuration. | `string` | `"prod"` | no |
| <a name="input_kafka_version"></a> [kafka\_version](#input\_kafka\_version) | Apache Kafka version for the MSK cluster.<br/><br/>Supported versions (as of 2026):<br/>  "3.7.x.kraft" — Latest stable. KRaft mode (no ZooKeeper). Recommended for all new clusters.<br/>  "3.6.0"       — Stable ZooKeeper-based. Use only if a dependency requires it.<br/>  "3.5.1"       — Maintenance mode. Not recommended for new deployments.<br/>  "2.8.1"       — End of standard support. Migrate away.<br/><br/>[Devotica recommendation: "3.7.x.kraft"]<br/>PCI-DSS: Use a version with active security patch support only. | `string` | n/a | yes |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log retention for broker logs in days.<br/><br/>Options:<br/>  90   — Minimum acceptable for non-regulated workloads.<br/>  180  — RBI CERT-In 2022 direction minimum for India-hosted systems.<br/>  365  — PCI-DSS 10.5.1 minimum. [Devotica recommendation for all production]<br/>  731  — Two years. Use for high-compliance or financial audit requirements.<br/><br/>[Devotica recommendation: 365]<br/>PCI-DSS 10.5.1: Audit log history of at least 12 months required.<br/>RBI CERT-In 2022: Minimum 180 days for ICT infrastructure logs. | `number` | n/a | yes |
| <a name="input_msk_kms_key_arn"></a> [msk\_kms\_key\_arn](#input\_msk\_kms\_key\_arn) | ARN of a customer-managed KMS key for encrypting MSK broker EBS volumes. Must be in the same region. Required — AWS-managed keys are not accepted. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Base name for all resources. Used as a prefix. Must be lowercase alphanumeric and hyphens only. | `string` | n/a | yes |
| <a name="input_number_of_broker_nodes"></a> [number\_of\_broker\_nodes](#input\_number\_of\_broker\_nodes) | Total number of broker nodes. Must be a multiple of availability\_zone\_count.<br/><br/>Options:<br/>  3  — One broker per AZ. Minimum recommended for production.<br/>  6  — Two brokers per AZ. Use for high-throughput or large partition counts.<br/>  9  — Three brokers per AZ. Large-scale production clusters.<br/><br/>[Devotica recommendation: 3 for standard production, 6 for high-throughput]<br/>PCI-DSS: Minimum 3 (one per AZ) required for HA compliance. | `number` | n/a | yes |
| <a name="input_open_monitoring_enabled"></a> [open\_monitoring\_enabled](#input\_open\_monitoring\_enabled) | Enable Prometheus JMX and Node Exporter endpoints on brokers.<br/>Required for Prometheus-based monitoring stacks (Grafana, Thanos, etc.).<br/><br/>[Devotica recommendation: true]<br/>Cost: No direct cost. Prometheus scrape traffic is billed as data transfer if cross-AZ. | `bool` | `true` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private subnet IDs for broker placement. Count must equal availability\_zone\_count<br/>(one subnet per AZ; MSK spreads number\_of\_broker\_nodes evenly across them).<br/>Subnets must not auto-assign public IPs. Each subnet must be in a different AZ.<br/><br/>[Devotica recommendation: One subnet per AZ, three subnets total for production] | `list(string)` | n/a | yes |
| <a name="input_replicator_enabled"></a> [replicator\_enabled](#input\_replicator\_enabled) | Enable MSK Replicator for cross-cluster topic replication.<br/>Required for active-active DR or multi-cluster architectures.<br/><br/>[Devotica recommendation: true for production clusters in regulated environments]<br/>PCI-DSS 12.3.3 and RBI IT Framework: DR capability required for critical systems.<br/>When enabled, provide replicator\_target\_cluster\_arn, replicator\_target\_subnet\_ids,<br/>replicator\_target\_security\_group\_ids and replicator\_topics\_to\_replicate.<br/>Cost: MSK Replicator charges per GB replicated plus replication instance hours. | `bool` | `false` | no |
| <a name="input_replicator_target_cluster_arn"></a> [replicator\_target\_cluster\_arn](#input\_replicator\_target\_cluster\_arn) | ARN of the target MSK cluster for replication. Required when replicator\_enabled is true.<br/>AWS creates an MSK Replicator in the TARGET cluster's region, and this module creates it<br/>with the caller's provider, so the target must be in the same region as this cluster.<br/>For cross-region DR, deploy the replicator from the DR region's stack instead. | `string` | `null` | no |
| <a name="input_replicator_target_security_group_ids"></a> [replicator\_target\_security\_group\_ids](#input\_replicator\_target\_security\_group\_ids) | Security group IDs in the target cluster's VPC that allow the replicator to reach the target brokers on TCP 9098. Required when replicator\_enabled is true. | `list(string)` | `[]` | no |
| <a name="input_replicator_target_subnet_ids"></a> [replicator\_target\_subnet\_ids](#input\_replicator\_target\_subnet\_ids) | Private subnet IDs in the target cluster's VPC that the replicator attaches to. Required when replicator\_enabled is true. | `list(string)` | `[]` | no |
| <a name="input_replicator_topics_to_replicate"></a> [replicator\_topics\_to\_replicate](#input\_replicator\_topics\_to\_replicate) | List of topic name patterns to replicate. Defaults to all topics. Use specific patterns to reduce replication cost. | `list(string)` | <pre>[<br/>  ".*"<br/>]</pre> | no |
| <a name="input_s3_logs_bucket"></a> [s3\_logs\_bucket](#input\_s3\_logs\_bucket) | S3 bucket name for broker log delivery. Required when s3\_logs\_enabled is true. Must be in the same region. Use a bucket from the central log-archive account. | `string` | `null` | no |
| <a name="input_s3_logs_enabled"></a> [s3\_logs\_enabled](#input\_s3\_logs\_enabled) | Enable broker log delivery to an S3 bucket for long-term audit and compliance archiving.<br/>Required for PCI-DSS and RBI workloads where logs must be retained beyond CloudWatch limits.<br/><br/>[Devotica recommendation: true for production, false for development]<br/>PCI-DSS 10.5.1: Long-term log archival required.<br/>Set s3\_logs\_bucket and s3\_logs\_prefix when enabling. | `bool` | `false` | no |
| <a name="input_s3_logs_prefix"></a> [s3\_logs\_prefix](#input\_s3\_logs\_prefix) | S3 key prefix for broker log objects. Defaults to msk-broker-logs. | `string` | `"msk-broker-logs"` | no |
| <a name="input_scram_enabled"></a> [scram\_enabled](#input\_scram\_enabled) | Enable SASL/SCRAM authentication using Secrets Manager credentials.<br/>Use for non-JVM clients or third-party connectors that cannot use IAM authentication.<br/><br/>[Devotica recommendation: false — prefer IAM authentication]<br/>When enabled, provide scram\_secret\_arns with CMK-encrypted Secrets Manager secrets.<br/>Requires Kafka 2.6 or later.<br/>Cost: Secrets Manager charges per secret per month plus API calls. | `bool` | `false` | no |
| <a name="input_scram_secret_arns"></a> [scram\_secret\_arns](#input\_scram\_secret\_arns) | List of Secrets Manager secret ARNs for SCRAM authentication. Required when scram\_enabled is true. Secrets must be encrypted with a CMK, not the AWS-managed key. | `list(string)` | `[]` | no |
| <a name="input_server_properties"></a> [server\_properties](#input\_server\_properties) | Custom Kafka broker configuration properties. Merged with the module's hardened defaults.<br/>Consumer-supplied values override module defaults where keys conflict.<br/><br/>Module hardened defaults (always applied):<br/>  auto.create.topics.enable        = false<br/>  default.replication.factor       = 3<br/>  min.insync.replicas              = 2<br/>  unclean.leader.election.enable   = false<br/>  log.retention.hours              = 168<br/>  num.partitions                   = 3<br/><br/>Example override:<br/>  server\_properties = {<br/>    "log.retention.hours" = "720"<br/>    "num.partitions"      = "6"<br/>  } | `map(string)` | `{}` | no |
| <a name="input_storage_autoscaling_enabled"></a> [storage\_autoscaling\_enabled](#input\_storage\_autoscaling\_enabled) | Enable automatic EBS storage scaling when disk utilization exceeds the threshold.<br/>Prevents broker outages caused by full disks without manual intervention.<br/><br/>[Devotica recommendation: true]<br/>Cost: Storage scales up but never down. Monitor with the KafkaDataLogsDiskUsed metric.<br/>Set to false only for strictly cost-capped development clusters. | `bool` | `true` | no |
| <a name="input_storage_autoscaling_max_gb"></a> [storage\_autoscaling\_max\_gb](#input\_storage\_autoscaling\_max\_gb) | Maximum EBS storage per broker in GiB when autoscaling is enabled.<br/>Must be greater than broker\_storage\_gb.<br/><br/>[Devotica recommendation: 2000 or 4x the initial broker\_storage\_gb, whichever is larger]<br/>Cost: You are billed for the scaled-up storage, not the initial allocation. | `number` | `2000` | no |
| <a name="input_storage_autoscaling_target_utilization"></a> [storage\_autoscaling\_target\_utilization](#input\_storage\_autoscaling\_target\_utilization) | Target disk utilization percentage that triggers autoscaling.<br/><br/>[Devotica recommendation: 60]<br/>Setting above 75 risks triggering scaling too late and causing broker unavailability.<br/>PCI-DSS: Proactive capacity management is required. Keep at or below 70. | `number` | `60` | no |
| <a name="input_storage_mode"></a> [storage\_mode](#input\_storage\_mode) | Storage mode for broker data.<br/><br/>Options:<br/>  "LOCAL"  — All data on local EBS. Standard configuration.<br/>  "TIERED" — Hot data on local EBS, cold data offloaded to S3 automatically.<br/>             Reduces local storage cost for high-retention workloads.<br/>             [Devotica recommendation for clusters with retention > 7 days]<br/>             Requires Kafka 3.6.0 or later (3.6.0 or 3.7.x.kraft in this module).<br/>             Not supported on kafka.t3.small.<br/><br/>[Devotica recommendation: TIERED for production, LOCAL for development]<br/>Cost: TIERED reduces EBS cost but adds S3 storage cost for tiered data. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to apply to all resources. ManagedBy and Module tags are set by the module and cannot be overridden. | `map(string)` | `{}` | no |
| <a name="input_tls_ca_arns"></a> [tls\_ca\_arns](#input\_tls\_ca\_arns) | List of ACM Private CA ARNs for mTLS client authentication.<br/>Use for client certificate-based authentication in zero-trust environments.<br/><br/>[Devotica recommendation: empty — use IAM or SCRAM unless mTLS is explicitly required]<br/>When set, clients must present a certificate signed by one of the listed CAs. | `list(string)` | `[]` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC where the MSK cluster will be deployed. Must be a private VPC with no public subnet routes for brokers. | `string` | n/a | yes |
<!-- END_TF_DOCS -->

---

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.11.0 |
| aws | >= 5.80, < 7.0 |

---

## Resources created

**Core**
- `aws_security_group.msk` — broker security group with no ingress (attach rules from the caller)
- `aws_cloudwatch_log_group.broker` — encrypted broker log group
- `aws_msk_configuration.this` — hardened broker configuration
- `aws_msk_cluster.this` — MSK Provisioned Standard cluster

**Observability** (created when `alarm_sns_topic_arn` is set)
- `aws_cloudwatch_metric_alarm.msk_disk`
- `aws_cloudwatch_metric_alarm.msk_cpu`
- `aws_cloudwatch_metric_alarm.msk_urp`
- `aws_cloudwatch_metric_alarm.msk_offline_partitions`
- `aws_cloudwatch_metric_alarm.msk_active_controller`

**Optional** (created only when specific variables are set)
- `aws_appautoscaling_target.msk_storage` + `aws_appautoscaling_policy.msk_storage` — when `storage_autoscaling_enabled = true`
- `aws_msk_scram_secret_association.this` — when `scram_enabled = true`
- `aws_iam_role.replicator` + `aws_iam_role_policy.replicator` + `aws_msk_replicator.this` + `aws_vpc_security_group_ingress_rule.replicator_self` — when `replicator_enabled = true`

---

## Upgrade guide (v1 → v2)

If you are upgrading from an earlier version of this module.

1. **Provider block removed.** The module no longer declares its own AWS provider, so it no longer forces `ap-south-1`. Declare `provider "aws"` (region, credentials, `default_tags`) in your root module.
2. **Required inputs added.** Set `availability_zone_count`, `vpc_id`, `broker_storage_gb` and `storage_mode`. `broker_instance_type`, `number_of_broker_nodes` and `log_retention_days` used to have defaults and must now be set explicitly.
3. **Inputs renamed.** Rename `kms_key_arn` → `msk_kms_key_arn`, `cloudwatch_kms_key_arn` → `cloudwatch_logs_kms_key_arn`, and `ebs_volume_size` → `broker_storage_gb`.
4. **Security group ownership changed.** The module now creates the broker security group. Remove the `security_group_ids` input and grant client access with `aws_vpc_security_group_ingress_rule` resources on the `security_group_id` output. Changing the cluster's security groups can force cluster replacement; check the plan before applying.
5. **Log group renamed.** The log group moved from `/aws/msk/<name>/broker` to `/aws/msk/<name>`. CloudWatch cannot rename a log group, so the old group would be destroyed. To keep its logs, run `terraform state rm 'module.msk.aws_cloudwatch_log_group.broker'` before applying, or export the logs first.
6. **Outputs removed or renamed.** Removed: `cluster_uuid`, `current_version`, `kms_key_arn`, `security_group_ids`, `private_subnet_ids`. Renamed: `cloudwatch_log_group_name` → `log_group_name`, `cloudwatch_log_group_arn` → `log_group_arn`. `bootstrap_brokers_sasl_iam` is now marked sensitive.

> Run `terraform plan` before `terraform apply`. Review every change that involves replacement of the MSK cluster or log group — cluster replacement is destructive and causes downtime.

---

## Support

This module is maintained by Devotica / V3 Consultancies. For issues or questions, open a GitHub issue or contact the platform team.
