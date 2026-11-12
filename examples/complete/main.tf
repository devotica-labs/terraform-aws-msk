# Devotica terraform-aws-msk — Complete Example
# This example demonstrates a PCI-DSS and RBI-compliant MSK configuration.
# All security-sensitive settings are enforced by the module and cannot be changed.
# Review each variable description before changing values for your environment.
#
# Every ID and ARN below is illustrative. Replace them with resources from your account.

module "msk" {
  source = "../.."

  # --- Identity and placement -------------------------------------------------
  name        = "payments-events"
  environment = "prod"

  # KRaft mode (no ZooKeeper) is the Devotica recommendation for new clusters.
  kafka_version = "3.7.x.kraft"

  # Graviton3, one broker per AZ across three AZs (PCI-DSS / RBI HA baseline).
  broker_instance_type    = "kafka.m7g.large"
  number_of_broker_nodes  = 3
  availability_zone_count = 3

  vpc_id = "vpc-0a1b2c3d4e5f60718"
  # One private subnet per AZ; count must equal availability_zone_count.
  private_subnet_ids = [
    "subnet-0a1b2c3d4e5f60711",
    "subnet-0a1b2c3d4e5f60722",
    "subnet-0a1b2c3d4e5f60733",
  ]

  # --- Storage -----------------------------------------------------------------
  # TIERED keeps hot data on EBS and moves older segments to S3 for long retention.
  broker_storage_gb                      = 500
  storage_mode                           = "TIERED"
  storage_autoscaling_enabled            = true
  storage_autoscaling_max_gb             = 2000
  storage_autoscaling_target_utilization = 60

  # --- Encryption (customer-managed keys only) ----------------------------------
  msk_kms_key_arn             = "arn:aws:kms:ap-south-1:111122223333:key/0a1b2c3d-1111-2222-3333-444455556666"
  cloudwatch_logs_kms_key_arn = "arn:aws:kms:ap-south-1:111122223333:key/0a1b2c3d-7777-8888-9999-000011112222"

  # --- Logging -------------------------------------------------------------------
  # 365 days satisfies PCI-DSS 10.5.1 and the 180-day CERT-In direction.
  log_retention_days = 365
  # Long-term archive in the central log-archive account's bucket.
  s3_logs_enabled = true
  s3_logs_bucket  = "devotica-log-archive-ap-south-1"
  s3_logs_prefix  = "msk/payments-events"

  # --- Monitoring and alerting ---------------------------------------------------
  enhanced_monitoring     = "PER_BROKER"
  open_monitoring_enabled = true
  alarm_sns_topic_arn     = "arn:aws:sns:ap-south-1:111122223333:platform-alerts"

  # --- Authentication --------------------------------------------------------------
  # IAM is always on. SCRAM and mTLS stay off unless a client cannot use IAM.
  scram_enabled     = false
  scram_secret_arns = []
  tls_ca_arns       = []

  # --- Broker configuration overrides -------------------------------------------------
  # Merged over the module's hardened defaults (RF=3, min ISR=2, auto-create off).
  server_properties = {
    "log.retention.hours" = "720"
    "num.partitions"      = "6"
  }

  # --- Disaster recovery --------------------------------------------------------------
  # The target cluster must be in the same region (the replicator is created in the
  # target's region with this stack's provider). For cross-region DR, create the
  # replicator from the DR region's stack.
  replicator_enabled                   = true
  replicator_target_cluster_arn        = "arn:aws:kafka:ap-south-1:111122223333:cluster/payments-events-dr/0a1b2c3d-aaaa-bbbb-cccc-ddddeeeeffff-2"
  replicator_target_subnet_ids         = ["subnet-0b1b2c3d4e5f60711", "subnet-0b1b2c3d4e5f60722", "subnet-0b1b2c3d4e5f60733"]
  replicator_target_security_group_ids = ["sg-0b1b2c3d4e5f60799"]
  replicator_topics_to_replicate       = ["payments\\..*"]

  tags = {
    Project    = "payments"
    Owner      = "platform"
    CostCenter = "engineering"
    Repo       = "terraform-aws-msk"
  }
}

# The module creates the broker security group with no ingress. Grant each client
# security group access to the IAM listener explicitly.
resource "aws_vpc_security_group_ingress_rule" "app_to_msk" {
  security_group_id            = module.msk.security_group_id
  referenced_security_group_id = "sg-0c1b2c3d4e5f60788"
  ip_protocol                  = "tcp"
  from_port                    = 9098
  to_port                      = 9098
  description                  = "Payments service to MSK (SASL/IAM)"
}
