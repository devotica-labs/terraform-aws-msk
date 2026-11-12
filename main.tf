################################################################################
# Network
################################################################################

resource "aws_security_group" "msk" {
  name        = "${var.name}-msk-sg"
  description = "MSK cluster security group — ${var.name}"
  vpc_id      = var.vpc_id

  # No inline ingress: client access is granted with aws_vpc_security_group_ingress_rule
  # resources that reference the security_group_id output. Do not add inline ingress
  # blocks here, or Terraform will fight those standalone rules.

  # Egress is open because brokers need it for inter-broker replication and AWS service
  # endpoints. Restricting it requires coordination with the broker VPC routing
  # (VPC endpoints, NAT, inter-broker CIDRs) and is left to a later design decision.
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name}-msk-sg" })
}

# The replicator's ENIs in the source VPC use this cluster's security group, so the
# group must allow itself on the IAM listener.
resource "aws_vpc_security_group_ingress_rule" "replicator_self" {
  count = local.replicator_enabled ? 1 : 0

  security_group_id            = aws_security_group.msk.id
  referenced_security_group_id = aws_security_group.msk.id
  ip_protocol                  = "tcp"
  from_port                    = 9098
  to_port                      = 9098
  description                  = "MSK Replicator to brokers (SASL/IAM)"
  tags                         = local.common_tags
}

################################################################################
# Logging
################################################################################

resource "aws_cloudwatch_log_group" "broker" {
  name              = "/aws/msk/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_logs_kms_key_arn
  tags              = local.common_tags
}

################################################################################
# Broker configuration
################################################################################

resource "aws_msk_configuration" "this" {
  name              = "${var.name}-config"
  kafka_versions    = [var.kafka_version]
  server_properties = local.broker_config_content
  description       = "Hardened broker configuration for ${var.name}. Managed by Devotica terraform-aws-msk."
}

################################################################################
# Cluster
################################################################################

resource "aws_msk_cluster" "this" {
  cluster_name           = var.name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.number_of_broker_nodes
  enhanced_monitoring    = var.enhanced_monitoring
  storage_mode           = var.storage_mode

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.private_subnet_ids
    security_groups = [aws_security_group.msk.id]
    az_distribution = "DEFAULT"

    connectivity_info {
      public_access {
        type = "DISABLED"
      }
    }

    # provisioned_throughput is intentionally omitted (disabled). It is only valid on
    # kafka.m5.4xlarge and larger, which this module does not offer.
    storage_info {
      ebs_storage_info {
        volume_size = var.broker_storage_gb
      }
    }
  }

  client_authentication {
    unauthenticated = false

    sasl {
      iam   = true
      scram = var.scram_enabled
    }

    dynamic "tls" {
      for_each = length(var.tls_ca_arns) > 0 ? [1] : []
      content {
        certificate_authority_arns = var.tls_ca_arns
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = var.msk_kms_key_arn

    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = var.open_monitoring_enabled
      }
      node_exporter {
        enabled_in_broker = var.open_monitoring_enabled
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.broker.name
      }

      dynamic "s3" {
        for_each = var.s3_logs_enabled ? [1] : []
        content {
          enabled = true
          bucket  = var.s3_logs_bucket
          prefix  = var.s3_logs_prefix
        }
      }
    }
  }

  tags = local.common_tags

  lifecycle {
    # Storage autoscaling grows volumes outside Terraform, and EBS volumes cannot shrink.
    # Without this, the next plan would try to reduce the volume and fail.
    ignore_changes = [broker_node_group_info[0].storage_info[0].ebs_storage_info[0].volume_size]

    precondition {
      condition     = length(var.private_subnet_ids) == var.availability_zone_count
      error_message = "Provide exactly one private subnet per AZ: length(private_subnet_ids) must equal availability_zone_count."
    }
    precondition {
      condition     = var.number_of_broker_nodes % var.availability_zone_count == 0
      error_message = "number_of_broker_nodes must be a multiple of availability_zone_count."
    }
    precondition {
      condition     = length(toset([for subnet in data.aws_subnet.selected : subnet.availability_zone_id])) == length(var.private_subnet_ids)
      error_message = "Every subnet must be in a different Availability Zone."
    }
    precondition {
      condition     = alltrue([for subnet in data.aws_subnet.selected : subnet.vpc_id == var.vpc_id])
      error_message = "All private_subnet_ids must belong to vpc_id."
    }
    precondition {
      condition     = alltrue([for subnet in data.aws_subnet.selected : !subnet.map_public_ip_on_launch])
      error_message = "Subnet public-IP auto-assignment must be disabled. Also verify routing separately."
    }
    precondition {
      condition     = var.storage_mode == "LOCAL" || (contains(["3.6.0", "3.7.x.kraft"], var.kafka_version) && !startswith(var.broker_instance_type, "kafka.t3."))
      error_message = "TIERED storage requires kafka_version 3.6.0 or 3.7.x.kraft and a non-t3 broker type."
    }
    precondition {
      condition     = !var.s3_logs_enabled || try(length(var.s3_logs_bucket) > 0, false)
      error_message = "s3_logs_bucket is required when s3_logs_enabled is true."
    }
    precondition {
      condition     = !var.scram_enabled || length(var.scram_secret_arns) > 0
      error_message = "scram_secret_arns is required when scram_enabled is true."
    }
    precondition {
      condition     = !var.storage_autoscaling_enabled || var.storage_autoscaling_max_gb > var.broker_storage_gb
      error_message = "storage_autoscaling_max_gb must be greater than broker_storage_gb."
    }
    precondition {
      condition     = !var.replicator_enabled || (var.replicator_target_cluster_arn != null && length(var.replicator_target_subnet_ids) > 0 && length(var.replicator_target_security_group_ids) > 0)
      error_message = "replicator_enabled requires replicator_target_cluster_arn, replicator_target_subnet_ids and replicator_target_security_group_ids."
    }
  }
}

resource "aws_msk_scram_secret_association" "this" {
  count = var.scram_enabled && length(var.scram_secret_arns) > 0 ? 1 : 0

  cluster_arn     = aws_msk_cluster.this.arn
  secret_arn_list = var.scram_secret_arns
}

################################################################################
# Storage autoscaling
################################################################################

resource "aws_appautoscaling_target" "msk_storage" {
  count = var.storage_autoscaling_enabled ? 1 : 0

  max_capacity       = var.storage_autoscaling_max_gb
  min_capacity       = var.broker_storage_gb
  resource_id        = aws_msk_cluster.this.arn
  scalable_dimension = "kafka:broker-storage:VolumeSize"
  service_namespace  = "kafka"
  tags               = local.common_tags

  depends_on = [aws_msk_cluster.this]
}

resource "aws_appautoscaling_policy" "msk_storage" {
  count = var.storage_autoscaling_enabled ? 1 : 0

  name               = "${var.name}-storage-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.msk_storage[0].resource_id
  scalable_dimension = aws_appautoscaling_target.msk_storage[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.msk_storage[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "KafkaBrokerStorageUtilization"
    }
    target_value     = var.storage_autoscaling_target_utilization
    disable_scale_in = true
  }
}

################################################################################
# Alarms
#
# KafkaDataLogsDiskUsed, CpuUser and UnderReplicatedPartitions are per-broker metrics,
# so those alarms use metric math across every broker. A CloudWatch alarm accepts at
# most 10 metrics, which caps these alarms at 9 brokers.
################################################################################

resource "aws_cloudwatch_metric_alarm" "msk_disk" {
  count = local.alarms_enabled ? 1 : 0

  alarm_name          = "${var.name}-disk-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 85
  alarm_description   = "MSK broker disk usage above 85% for ${var.name}"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]

  metric_query {
    id          = "result"
    expression  = "MAX([${join(",", [for id in local.broker_ids : "m${id}"])}])"
    label       = "Max KafkaDataLogsDiskUsed across brokers"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = local.broker_ids
    content {
      id = "m${metric_query.value}"
      metric {
        metric_name = "KafkaDataLogsDiskUsed"
        namespace   = "AWS/Kafka"
        period      = 300
        stat        = "Maximum"
        dimensions = {
          "Cluster Name" = aws_msk_cluster.this.cluster_name
          "Broker ID"    = tostring(metric_query.value)
        }
      }
    }
  }

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = var.number_of_broker_nodes <= 9
      error_message = "Per-broker alarms support at most 9 brokers (CloudWatch 10-metric limit)."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "msk_cpu" {
  count = local.alarms_enabled ? 1 : 0

  alarm_name          = "${var.name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 70
  alarm_description   = "MSK broker CPU above 70%"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]

  metric_query {
    id          = "result"
    expression  = "MAX([${join(",", [for id in local.broker_ids : "m${id}"])}])"
    label       = "Max CpuUser across brokers"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = local.broker_ids
    content {
      id = "m${metric_query.value}"
      metric {
        metric_name = "CpuUser"
        namespace   = "AWS/Kafka"
        period      = 300
        stat        = "Maximum"
        dimensions = {
          "Cluster Name" = aws_msk_cluster.this.cluster_name
          "Broker ID"    = tostring(metric_query.value)
        }
      }
    }
  }

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = var.number_of_broker_nodes <= 9
      error_message = "Per-broker alarms support at most 9 brokers (CloudWatch 10-metric limit)."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "msk_urp" {
  count = local.alarms_enabled ? 1 : 0

  alarm_name          = "${var.name}-under-replicated-partitions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "MSK has under-replicated partitions — replication is degraded"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]

  metric_query {
    id          = "result"
    expression  = "SUM([${join(",", [for id in local.broker_ids : "m${id}"])}])"
    label       = "Total UnderReplicatedPartitions"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = local.broker_ids
    content {
      id = "m${metric_query.value}"
      metric {
        metric_name = "UnderReplicatedPartitions"
        namespace   = "AWS/Kafka"
        period      = 300
        stat        = "Maximum"
        dimensions = {
          "Cluster Name" = aws_msk_cluster.this.cluster_name
          "Broker ID"    = tostring(metric_query.value)
        }
      }
    }
  }

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = var.number_of_broker_nodes <= 9
      error_message = "Per-broker alarms support at most 9 brokers (CloudWatch 10-metric limit)."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "msk_offline_partitions" {
  count = local.alarms_enabled ? 1 : 0

  alarm_name          = "${var.name}-offline-partitions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "OfflinePartitionsCount"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "MSK has offline partitions — data may be unavailable"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]

  dimensions = {
    "Cluster Name" = aws_msk_cluster.this.cluster_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "msk_active_controller" {
  count = local.alarms_enabled ? 1 : 0

  alarm_name          = "${var.name}-no-active-controller"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ActiveControllerCount"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "MSK active controller count is below 1 — cluster has no active controller"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  # No data means no controller is reporting, which is the failure this alarm exists for.
  treat_missing_data = "breaching"

  dimensions = {
    "Cluster Name" = aws_msk_cluster.this.cluster_name
  }

  tags = local.common_tags
}

################################################################################
# MSK Replicator
################################################################################

resource "aws_iam_role" "replicator" {
  count = var.replicator_enabled ? 1 : 0

  name = "${var.name}-msk-replicator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "kafka.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = local.common_tags
}

# Equivalent to the AWS-documented MSK Replicator execution role, scoped to the
# source and target clusters and their topics and consumer groups.
resource "aws_iam_role_policy" "replicator" {
  count = local.replicator_enabled ? 1 : 0

  name = "${var.name}-msk-replicator"
  role = aws_iam_role.replicator[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ClusterAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:WriteDataIdempotently",
        ]
        Resource = [aws_msk_cluster.this.arn, var.replicator_target_cluster_arn]
      },
      {
        Sid    = "TopicAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:DescribeTopicDynamicConfiguration",
          "kafka-cluster:AlterTopicDynamicConfiguration",
        ]
        Resource = [for arn in [aws_msk_cluster.this.arn, var.replicator_target_cluster_arn] : "${replace(arn, ":cluster/", ":topic/")}/*"]
      },
      {
        Sid      = "GroupAccess"
        Effect   = "Allow"
        Action   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
        Resource = [for arn in [aws_msk_cluster.this.arn, var.replicator_target_cluster_arn] : "${replace(arn, ":cluster/", ":group/")}/*"]
      },
    ]
  })
}

resource "aws_msk_replicator" "this" {
  count = local.replicator_enabled ? 1 : 0

  replicator_name            = "${var.name}-replicator"
  description                = "MSK Replicator for ${var.name} — managed by Devotica terraform-aws-msk"
  service_execution_role_arn = aws_iam_role.replicator[0].arn

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = aws_msk_cluster.this.arn
    }
    vpc_config {
      subnet_ids          = var.private_subnet_ids
      security_groups_ids = [aws_security_group.msk.id]
    }
  }

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = var.replicator_target_cluster_arn
    }
    vpc_config {
      subnet_ids          = var.replicator_target_subnet_ids
      security_groups_ids = var.replicator_target_security_group_ids
    }
  }

  replication_info_list {
    source_kafka_cluster_arn = aws_msk_cluster.this.arn
    target_kafka_cluster_arn = var.replicator_target_cluster_arn
    target_compression_type  = "NONE"

    topic_replication {
      topics_to_replicate                  = var.replicator_topics_to_replicate
      detect_and_copy_new_topics           = true
      copy_access_control_lists_for_topics = true
      copy_topic_configurations            = true
    }

    consumer_group_replication {
      consumer_groups_to_replicate        = [".*"]
      detect_and_copy_new_consumer_groups = true
      synchronise_consumer_group_offsets  = true
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy.replicator, aws_vpc_security_group_ingress_rule.replicator_self]

  lifecycle {
    precondition {
      condition     = split(":", var.replicator_target_cluster_arn)[3] == split(":", aws_msk_cluster.this.arn)[3]
      error_message = "MSK Replicator is created in the target cluster's region; this module only supports a target in the same region as the source cluster."
    }
  }
}
