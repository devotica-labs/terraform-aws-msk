# Devotica terraform-aws-msk — Basic Example
# This example demonstrates a PCI-DSS and RBI-compliant MSK configuration.
# All security-sensitive settings are enforced by the module and cannot be changed.
# Review each variable description before changing values for your environment.
#
# Only the required inputs are set. Every ID and ARN below is illustrative.

module "msk" {
  source = "../.."

  name          = "orders-events"
  kafka_version = "3.7.x.kraft" # KRaft mode, no ZooKeeper

  broker_instance_type    = "kafka.m7g.large" # Graviton3
  number_of_broker_nodes  = 3                 # one broker per AZ
  availability_zone_count = 3

  broker_storage_gb = 500
  storage_mode      = "LOCAL"

  vpc_id = "vpc-0a1b2c3d4e5f60718"
  private_subnet_ids = [
    "subnet-0a1b2c3d4e5f60711",
    "subnet-0a1b2c3d4e5f60722",
    "subnet-0a1b2c3d4e5f60733",
  ]

  log_retention_days          = 365 # PCI-DSS 10.5.1
  msk_kms_key_arn             = "arn:aws:kms:ap-south-1:111122223333:key/0a1b2c3d-1111-2222-3333-444455556666"
  cloudwatch_logs_kms_key_arn = "arn:aws:kms:ap-south-1:111122223333:key/0a1b2c3d-7777-8888-9999-000011112222"

  # On by default; shown explicitly because full disks are the most common MSK outage.
  storage_autoscaling_enabled = true
}
