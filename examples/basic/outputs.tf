output "cluster_arn" {
  description = "MSK cluster ARN."
  value       = module.msk.cluster_arn
}
output "bootstrap_brokers_sasl_iam" {
  description = "Private IAM endpoints."
  value       = module.msk.bootstrap_brokers_sasl_iam
  sensitive   = true
}
output "security_group_id" {
  description = "Broker security group; attach client ingress rules to it."
  value       = module.msk.security_group_id
}
