# Evaluated against the module's root .tf files with the hcl2 parser:
#   conftest test --parser hcl2 --namespace module_files --policy policies *.tf
package module_files
import rego.v1

deny contains sprintf("module root must not declare provider blocks (found: %s)", [concat(", ", [name | some name, _ in input.provider])]) if {
    object.get(input, "provider", null) != null
}
