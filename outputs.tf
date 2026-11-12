output "cluster_arn" {
  description = "MSK cluster ARN."
  value       = aws_msk_cluster.this.arn
}

output "cluster_name" {
  description = "MSK cluster name."
  value       = aws_msk_cluster.this.cluster_name
}

output "zookeeper_connect_string" {
  description = "ZooKeeper connection string. Empty for KRaft-mode clusters (3.7.x.kraft)."
  value       = aws_msk_cluster.this.zookeeper_connect_string
  sensitive   = true
}

output "bootstrap_brokers_sasl_iam" {
  description = "Private SASL/IAM bootstrap brokers (TCP 9098)."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
  sensitive   = true
}

output "bootstrap_brokers_sasl_scram" {
  description = "Private SASL/SCRAM bootstrap brokers (TCP 9096). Empty unless scram_enabled is true."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_scram
  sensitive   = true
}

output "bootstrap_brokers_tls" {
  description = "Private TLS bootstrap brokers (TCP 9094). Populated when mTLS (tls_ca_arns) is configured."
  value       = aws_msk_cluster.this.bootstrap_brokers_tls
  sensitive   = true
}

output "security_group_id" {
  description = "ID of the broker security group created by the module. Attach aws_vpc_security_group_ingress_rule resources to it to grant client access."
  value       = aws_security_group.msk.id
}

output "log_group_name" {
  description = "CloudWatch broker log group name."
  value       = aws_cloudwatch_log_group.broker.name
}

output "log_group_arn" {
  description = "CloudWatch broker log group ARN."
  value       = aws_cloudwatch_log_group.broker.arn
}

output "storage_autoscaling_enabled" {
  description = "Whether EBS storage autoscaling is enabled for the brokers."
  value       = var.storage_autoscaling_enabled
}

output "replicator_arn" {
  description = "ARN of the MSK Replicator, or null when replication is disabled."
  value       = var.replicator_enabled && var.replicator_target_cluster_arn != null ? aws_msk_replicator.this[0].arn : null
}
