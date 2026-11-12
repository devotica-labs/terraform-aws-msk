mock_provider "aws" {
  source = "./tests/mocks"
}
variables {
  name                        = "msk-test"
  kafka_version               = "3.7.x.kraft"
  broker_instance_type        = "kafka.m7g.large"
  number_of_broker_nodes      = 3
  availability_zone_count     = 3
  broker_storage_gb           = 500
  storage_mode                = "LOCAL"
  vpc_id                      = "vpc-11111111"
  private_subnet_ids          = ["subnet-11111111", "subnet-22222222", "subnet-33333333"]
  log_retention_days          = 365
  msk_kms_key_arn             = "arn:aws:kms:ap-south-1:123456789012:key/11111111-1111-1111-1111-111111111111"
  cloudwatch_logs_kms_key_arn = "arn:aws:kms:ap-south-1:123456789012:key/22222222-2222-2222-2222-222222222222"
  tags                        = { Project = "msk", Owner = "platform", CostCenter = "engineering", Repo = "terraform-aws-msk" }
}
override_data {
  target = data.aws_subnet.selected["subnet-11111111"]
  values = { availability_zone_id = "aps1-az1", vpc_id = "vpc-11111111", map_public_ip_on_launch = false }
}
override_data {
  target = data.aws_subnet.selected["subnet-22222222"]
  values = { availability_zone_id = "aps1-az2", vpc_id = "vpc-11111111", map_public_ip_on_launch = false }
}
override_data {
  target = data.aws_subnet.selected["subnet-33333333"]
  values = { availability_zone_id = "aps1-az3", vpc_id = "vpc-11111111", map_public_ip_on_launch = false }
}
run "stable_output_contract" {
  command = apply # Mock provider only: no AWS API calls.
  assert {
    condition     = output.cluster_name == var.name
    error_message = "Cluster name output must reflect input."
  }
  assert {
    condition     = output.cluster_arn == "arn:aws:kafka:ap-south-1:123456789012:cluster/msk-test/11111111-1111-1111-1111-111111111111-1"
    error_message = "Cluster ARN contract changed."
  }
  assert {
    condition     = output.bootstrap_brokers_sasl_iam == "b-1.test.kafka.ap-south-1.amazonaws.com:9098,b-2.test.kafka.ap-south-1.amazonaws.com:9098"
    error_message = "IAM endpoint output contract changed."
  }
  assert {
    condition     = output.zookeeper_connect_string == "" && output.bootstrap_brokers_sasl_scram == "" && output.bootstrap_brokers_tls == ""
    error_message = "Unused endpoint outputs must be empty strings."
  }
  assert {
    condition     = output.security_group_id == "sg-0123456789abcdef0"
    error_message = "Security group output contract changed."
  }
  assert {
    condition     = output.log_group_name == "/aws/msk/msk-test" && output.log_group_arn == "arn:aws:logs:ap-south-1:123456789012:log-group:/aws/msk/msk-test"
    error_message = "Log output contract changed."
  }
  assert {
    condition     = output.storage_autoscaling_enabled == true && output.replicator_arn == null
    error_message = "Feature-flag output contract changed."
  }
}
