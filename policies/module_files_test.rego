package module_files
import rego.v1

test_provider_block_denied if {
    count(deny) == 1 with input as {"provider": {"aws": [{"region": "ap-south-1"}]}}
}
test_terraform_block_allowed if {
    count(deny) == 0 with input as {"terraform": [{"required_version": ">= 1.11.0"}]}
}
