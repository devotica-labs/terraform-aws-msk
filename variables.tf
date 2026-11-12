################################################################################
# GROUP A — Required variables (no default; Terraform prompts if unset)
################################################################################

variable "name" {
  type        = string
  description = "Base name for all resources. Used as a prefix. Must be lowercase alphanumeric and hyphens only."
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name))
    error_message = "name must be lowercase alphanumeric and hyphens only."
  }
}

variable "kafka_version" {
  type        = string
  description = <<-EOT
    Apache Kafka version for the MSK cluster.

    Supported versions (as of 2026):
      "3.7.x.kraft" — Latest stable. KRaft mode (no ZooKeeper). Recommended for all new clusters.
      "3.6.0"       — Stable ZooKeeper-based. Use only if a dependency requires it.
      "3.5.1"       — Maintenance mode. Not recommended for new deployments.
      "2.8.1"       — End of standard support. Migrate away.

    [Devotica recommendation: "3.7.x.kraft"]
    PCI-DSS: Use a version with active security patch support only.
  EOT
  validation {
    condition     = can(regex("^(3\\.7\\.x\\.kraft|3\\.6\\.0|3\\.5\\.1|2\\.8\\.1)$", var.kafka_version))
    error_message = "kafka_version must be one of: 3.7.x.kraft, 3.6.0, 3.5.1, 2.8.1."
  }
}

variable "broker_instance_type" {
  type        = string
  description = <<-EOT
    EC2 instance type for MSK broker nodes.

    Options:
      "kafka.m7g.large"   — Graviton3. Best price-performance for most workloads.
                            [Devotica recommendation for production]
      "kafka.m7g.xlarge"  — Graviton3. High-throughput production clusters.
      "kafka.m5.large"    — x86. Use only if Graviton is not available in your region.
      "kafka.m5.xlarge"   — x86 high-throughput.
      "kafka.t3.small"    — Development and testing only. Not for production.

    PCI-DSS: t3.small is not recommended for production. It cannot sustain consistent throughput.
    Cost: m7g instances are approximately 20 percent cheaper than equivalent m5.
  EOT
  validation {
    condition     = can(regex("^kafka\\.(m7g|m5|t3)\\.(small|large|xlarge|2xlarge)$", var.broker_instance_type))
    error_message = "broker_instance_type must be a valid MSK instance type."
  }
}

variable "number_of_broker_nodes" {
  type        = number
  description = <<-EOT
    Total number of broker nodes. Must be a multiple of availability_zone_count.

    Options:
      3  — One broker per AZ. Minimum recommended for production.
      6  — Two brokers per AZ. Use for high-throughput or large partition counts.
      9  — Three brokers per AZ. Large-scale production clusters.

    [Devotica recommendation: 3 for standard production, 6 for high-throughput]
    PCI-DSS: Minimum 3 (one per AZ) required for HA compliance.
  EOT
  validation {
    condition     = var.number_of_broker_nodes >= 2 && var.number_of_broker_nodes % 1 == 0
    error_message = "number_of_broker_nodes must be a positive integer of at least 2."
  }
}

variable "availability_zone_count" {
  type        = number
  description = <<-EOT
    Number of Availability Zones to distribute brokers across.

    Options:
      2 — Two AZs. Development and cost-sensitive non-production only.
          Warning: losing one AZ in a 2-AZ cluster can block writes if min.insync.replicas=2.
      3 — Three AZs. [Devotica recommendation for all production workloads]
          Required for PCI-DSS and RBI-regulated environments.
          Protects against full AZ failure without impacting write availability.

    [Devotica recommendation: 3]
    PCI-DSS 2.2.1: High availability configuration required for in-scope systems.
    RBI IT Framework: Requires no single point of failure for critical payment infrastructure.
  EOT
  validation {
    condition     = contains([2, 3], var.availability_zone_count)
    error_message = "availability_zone_count must be 2 or 3."
  }
}

variable "broker_storage_gb" {
  type        = number
  description = <<-EOT
    EBS storage per broker in GiB. Applied to each broker node individually.

    Guidelines:
      100  — Development / low-volume.
      500  — Standard production (up to ~400 GB usable with 20% headroom).
      1000 — High-volume production or long retention periods.
      2000 — Large-scale clusters with multi-day retention.

    [Devotica recommendation: 500 for standard production]
    Note: If storage_mode is TIERED, local storage can be smaller. See storage_mode.
    Cost: EBS gp3 at $0.08/GiB/month per broker.
  EOT
  validation {
    condition     = var.broker_storage_gb >= 20 && var.broker_storage_gb <= 16384
    error_message = "broker_storage_gb must be between 20 and 16384 GiB."
  }
}

variable "storage_mode" {
  type        = string
  description = <<-EOT
    Storage mode for broker data.

    Options:
      "LOCAL"  — All data on local EBS. Standard configuration.
      "TIERED" — Hot data on local EBS, cold data offloaded to S3 automatically.
                 Reduces local storage cost for high-retention workloads.
                 [Devotica recommendation for clusters with retention > 7 days]
                 Requires Kafka 3.6.0 or later (3.6.0 or 3.7.x.kraft in this module).
                 Not supported on kafka.t3.small.

    [Devotica recommendation: TIERED for production, LOCAL for development]
    Cost: TIERED reduces EBS cost but adds S3 storage cost for tiered data.
  EOT
  validation {
    condition     = contains(["LOCAL", "TIERED"], var.storage_mode)
    error_message = "storage_mode must be LOCAL or TIERED."
  }
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC where the MSK cluster will be deployed. Must be a private VPC with no public subnet routes for brokers."
  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID starting with vpc-."
  }
}

variable "private_subnet_ids" {
  type        = list(string)
  description = <<-EOT
    List of private subnet IDs for broker placement. Count must equal availability_zone_count
    (one subnet per AZ; MSK spreads number_of_broker_nodes evenly across them).
    Subnets must not auto-assign public IPs. Each subnet must be in a different AZ.

    [Devotica recommendation: One subnet per AZ, three subnets total for production]
  EOT
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnet IDs are required."
  }
}

variable "log_retention_days" {
  type        = number
  description = <<-EOT
    CloudWatch log retention for broker logs in days.

    Options:
      90   — Minimum acceptable for non-regulated workloads.
      180  — RBI CERT-In 2022 direction minimum for India-hosted systems.
      365  — PCI-DSS 10.5.1 minimum. [Devotica recommendation for all production]
      731  — Two years. Use for high-compliance or financial audit requirements.

    [Devotica recommendation: 365]
    PCI-DSS 10.5.1: Audit log history of at least 12 months required.
    RBI CERT-In 2022: Minimum 180 days for ICT infrastructure logs.
  EOT
  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention value."
  }
}

variable "cloudwatch_logs_kms_key_arn" {
  type        = string
  description = "ARN of a customer-managed KMS key for encrypting the CloudWatch log group. Must be in the same region. Required — AWS-managed keys are not accepted."
  validation {
    condition     = can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.cloudwatch_logs_kms_key_arn))
    error_message = "cloudwatch_logs_kms_key_arn must be a valid KMS key ARN."
  }
}

variable "msk_kms_key_arn" {
  type        = string
  description = "ARN of a customer-managed KMS key for encrypting MSK broker EBS volumes. Must be in the same region. Required — AWS-managed keys are not accepted."
  validation {
    condition     = can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.msk_kms_key_arn))
    error_message = "msk_kms_key_arn must be a valid KMS key ARN."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Map of tags to apply to all resources. ManagedBy and Module tags are set by the module and cannot be overridden."
}

################################################################################
# GROUP B — Optional variables with secure defaults
################################################################################

variable "storage_autoscaling_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Enable automatic EBS storage scaling when disk utilization exceeds the threshold.
    Prevents broker outages caused by full disks without manual intervention.

    [Devotica recommendation: true]
    Cost: Storage scales up but never down. Monitor with the KafkaDataLogsDiskUsed metric.
    Set to false only for strictly cost-capped development clusters.
  EOT
}

variable "storage_autoscaling_max_gb" {
  type        = number
  default     = 2000
  description = <<-EOT
    Maximum EBS storage per broker in GiB when autoscaling is enabled.
    Must be greater than broker_storage_gb.

    [Devotica recommendation: 2000 or 4x the initial broker_storage_gb, whichever is larger]
    Cost: You are billed for the scaled-up storage, not the initial allocation.
  EOT
  validation {
    condition     = var.storage_autoscaling_max_gb >= 20 && var.storage_autoscaling_max_gb <= 16384
    error_message = "storage_autoscaling_max_gb must be between 20 and 16384 GiB."
  }
}

variable "storage_autoscaling_target_utilization" {
  type        = number
  default     = 60
  description = <<-EOT
    Target disk utilization percentage that triggers autoscaling.

    [Devotica recommendation: 60]
    Setting above 75 risks triggering scaling too late and causing broker unavailability.
    PCI-DSS: Proactive capacity management is required. Keep at or below 70.
  EOT
  validation {
    condition     = var.storage_autoscaling_target_utilization >= 10 && var.storage_autoscaling_target_utilization <= 80
    error_message = "storage_autoscaling_target_utilization must be between 10 and 80."
  }
}

variable "enhanced_monitoring" {
  type        = string
  default     = "PER_BROKER"
  description = <<-EOT
    Level of enhanced CloudWatch monitoring for MSK brokers.

    Options:
      "DEFAULT"              — Basic cluster-level metrics only. Free tier.
      "PER_BROKER"           — Per-broker metrics. [Devotica recommendation]
      "PER_TOPIC_PER_BROKER" — Per-topic per-broker metrics. High cardinality cost.
      "PER_TOPIC_PER_PARTITION" — Highest granularity. Significant CloudWatch cost.

    Cost: PER_BROKER adds approximately $0.30/broker/month in CloudWatch charges.
          PER_TOPIC_* levels can add significant cost for high-partition clusters.
  EOT
  validation {
    condition     = contains(["DEFAULT", "PER_BROKER", "PER_TOPIC_PER_BROKER", "PER_TOPIC_PER_PARTITION"], var.enhanced_monitoring)
    error_message = "enhanced_monitoring must be one of: DEFAULT, PER_BROKER, PER_TOPIC_PER_BROKER, PER_TOPIC_PER_PARTITION."
  }
}

variable "open_monitoring_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Enable Prometheus JMX and Node Exporter endpoints on brokers.
    Required for Prometheus-based monitoring stacks (Grafana, Thanos, etc.).

    [Devotica recommendation: true]
    Cost: No direct cost. Prometheus scrape traffic is billed as data transfer if cross-AZ.
  EOT
}

variable "s3_logs_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Enable broker log delivery to an S3 bucket for long-term audit and compliance archiving.
    Required for PCI-DSS and RBI workloads where logs must be retained beyond CloudWatch limits.

    [Devotica recommendation: true for production, false for development]
    PCI-DSS 10.5.1: Long-term log archival required.
    Set s3_logs_bucket and s3_logs_prefix when enabling.
  EOT
}

variable "s3_logs_bucket" {
  type        = string
  default     = null
  description = "S3 bucket name for broker log delivery. Required when s3_logs_enabled is true. Must be in the same region. Use a bucket from the central log-archive account."
}

variable "s3_logs_prefix" {
  type        = string
  default     = "msk-broker-logs"
  description = "S3 key prefix for broker log objects. Defaults to msk-broker-logs."
}

variable "scram_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Enable SASL/SCRAM authentication using Secrets Manager credentials.
    Use for non-JVM clients or third-party connectors that cannot use IAM authentication.

    [Devotica recommendation: false — prefer IAM authentication]
    When enabled, provide scram_secret_arns with CMK-encrypted Secrets Manager secrets.
    Requires Kafka 2.6 or later.
    Cost: Secrets Manager charges per secret per month plus API calls.
  EOT
}

variable "scram_secret_arns" {
  type        = list(string)
  default     = []
  description = "List of Secrets Manager secret ARNs for SCRAM authentication. Required when scram_enabled is true. Secrets must be encrypted with a CMK, not the AWS-managed key."
}

variable "tls_ca_arns" {
  type        = list(string)
  default     = []
  description = <<-EOT
    List of ACM Private CA ARNs for mTLS client authentication.
    Use for client certificate-based authentication in zero-trust environments.

    [Devotica recommendation: empty — use IAM or SCRAM unless mTLS is explicitly required]
    When set, clients must present a certificate signed by one of the listed CAs.
  EOT
}

variable "replicator_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Enable MSK Replicator for cross-cluster topic replication.
    Required for active-active DR or multi-cluster architectures.

    [Devotica recommendation: true for production clusters in regulated environments]
    PCI-DSS 12.3.3 and RBI IT Framework: DR capability required for critical systems.
    When enabled, provide replicator_target_cluster_arn, replicator_target_subnet_ids,
    replicator_target_security_group_ids and replicator_topics_to_replicate.
    Cost: MSK Replicator charges per GB replicated plus replication instance hours.
  EOT
}

variable "replicator_target_cluster_arn" {
  type        = string
  default     = null
  description = <<-EOT
    ARN of the target MSK cluster for replication. Required when replicator_enabled is true.
    AWS creates an MSK Replicator in the TARGET cluster's region, and this module creates it
    with the caller's provider, so the target must be in the same region as this cluster.
    For cross-region DR, deploy the replicator from the DR region's stack instead.
  EOT
}

variable "replicator_target_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Private subnet IDs in the target cluster's VPC that the replicator attaches to. Required when replicator_enabled is true."
}

variable "replicator_target_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security group IDs in the target cluster's VPC that allow the replicator to reach the target brokers on TCP 9098. Required when replicator_enabled is true."
}

variable "replicator_topics_to_replicate" {
  type        = list(string)
  default     = [".*"]
  description = "List of topic name patterns to replicate. Defaults to all topics. Use specific patterns to reduce replication cost."
}

variable "alarm_sns_topic_arn" {
  type        = string
  default     = null
  description = <<-EOT
    SNS topic ARN for CloudWatch alarm notifications.
    When set, the module creates alarms for: disk usage, CPU, under-replicated partitions,
    offline partitions, and active controller count.

    [Devotica recommendation: always set for production]
    PCI-DSS 10.6.1: Automated alerting on critical system events required.
  EOT
}

variable "server_properties" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Custom Kafka broker configuration properties. Merged with the module's hardened defaults.
    Consumer-supplied values override module defaults where keys conflict.

    Module hardened defaults (always applied):
      auto.create.topics.enable        = false
      default.replication.factor       = 3
      min.insync.replicas              = 2
      unclean.leader.election.enable   = false
      log.retention.hours              = 168
      num.partitions                   = 3

    Example override:
      server_properties = {
        "log.retention.hours" = "720"
        "num.partitions"      = "6"
      }
  EOT
}

variable "environment" {
  type        = string
  default     = "prod"
  description = <<-EOT
    Deployment environment. Used in resource naming, tags, and OPA policy evaluation.

    Options:
      "prod"    — Production. Full compliance checks enforced. [Devotica default]
      "staging" — Pre-production. Compliance checks enforced.
      "dev"     — Development. Relaxed retention and monitoring defaults.
      "sandbox" — Ephemeral. Minimal cost configuration.
  EOT
  validation {
    condition     = contains(["prod", "staging", "dev", "sandbox"], var.environment)
    error_message = "environment must be one of: prod, staging, dev, sandbox."
  }
}
