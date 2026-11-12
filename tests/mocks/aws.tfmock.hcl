mock_data "aws_caller_identity" {
  defaults = {
    account_id = "123456789012"
    arn        = "arn:aws:iam::123456789012:role/devotica-ci"
  }
}
mock_resource "aws_msk_cluster" {
  defaults = {
    arn                          = "arn:aws:kafka:ap-south-1:123456789012:cluster/msk-test/11111111-1111-1111-1111-111111111111-1"
    cluster_uuid                 = "11111111-1111-1111-1111-111111111111-1"
    current_version              = "K1TESTVERSION"
    zookeeper_connect_string     = ""
    bootstrap_brokers_sasl_iam   = "b-1.test.kafka.ap-south-1.amazonaws.com:9098,b-2.test.kafka.ap-south-1.amazonaws.com:9098"
    bootstrap_brokers_sasl_scram = ""
    bootstrap_brokers_tls        = ""
  }
}
mock_resource "aws_msk_configuration" {
  defaults = {
    arn             = "arn:aws:kafka:ap-south-1:123456789012:configuration/msk-test-config/22222222-2222-2222-2222-222222222222-1"
    latest_revision = 1
  }
}
mock_resource "aws_security_group" {
  defaults = { id = "sg-0123456789abcdef0" }
}
mock_resource "aws_cloudwatch_log_group" {
  defaults = { arn = "arn:aws:logs:ap-south-1:123456789012:log-group:/aws/msk/msk-test" }
}
mock_resource "aws_iam_role" {
  defaults = { arn = "arn:aws:iam::123456789012:role/msk-test-msk-replicator" }
}
mock_resource "aws_msk_replicator" {
  defaults = { arn = "arn:aws:kafka:ap-south-1:123456789012:replicator/msk-test-replicator/33333333-3333-3333-3333-333333333333-1" }
}
