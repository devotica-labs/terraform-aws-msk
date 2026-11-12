# Deliberately outside the default tests/ discovery directory.
# Explicit AWS approval required: this creates and then destroys a real cluster.
provider "aws" {}
run "sandbox_lifecycle" {
  command = apply
  assert {
    condition     = length(output.cluster_arn) > 0 && length(output.bootstrap_brokers_sasl_iam) > 0
    error_message = "MSK must expose an ARN and private IAM endpoints."
  }
  assert {
    condition     = aws_msk_cluster.this.client_authentication[0].sasl[0].iam && aws_msk_cluster.this.encryption_info[0].encryption_in_transit[0].in_cluster
    error_message = "Live cluster security settings do not match the contract."
  }
  assert {
    condition     = aws_msk_cluster.this.configuration_info[0].arn == aws_msk_configuration.this.arn
    error_message = "Cluster must use the module's hardened configuration."
  }
}
