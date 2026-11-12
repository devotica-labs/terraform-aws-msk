locals {
  # Module-owned tags are merged last so callers cannot override them.
  common_tags = merge(var.tags, {
    ManagedBy   = "devotica-terraform"
    Module      = "terraform-aws-msk"
    Environment = var.environment
  })

  hardened_broker_defaults = {
    "auto.create.topics.enable"      = "false"
    "default.replication.factor"     = "3"
    "min.insync.replicas"            = "2"
    "unclean.leader.election.enable" = "false"
    "log.retention.hours"            = "168"
    "num.partitions"                 = "3"
  }

  broker_config_properties = merge(local.hardened_broker_defaults, var.server_properties)

  broker_config_content = join("\n", [for key in sort(keys(local.broker_config_properties)) : "${key} = ${local.broker_config_properties[key]}"])

  # MSK numbers brokers 1..N. Per-broker metrics are published with both the
  # "Cluster Name" and "Broker ID" dimensions, so alarms aggregate across them.
  broker_ids     = range(1, var.number_of_broker_nodes + 1)
  alarms_enabled = var.alarm_sns_topic_arn != null

  replicator_enabled = var.replicator_enabled && var.replicator_target_cluster_arn != null
}
