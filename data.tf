data "aws_caller_identity" "current" {}

# data "aws_region" is deliberately not declared: its id/name attributes are deprecated
# in AWS provider v6 and its replacement (region) does not exist in v5, so it cannot be
# read cleanly across the supported ">= 5.80, < 7.0" range. Regions are taken from ARNs.

data "aws_subnet" "selected" {
  for_each = toset(var.private_subnet_ids)
  id       = each.value
}
