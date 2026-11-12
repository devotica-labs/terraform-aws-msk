# Reference mapping and deliberate adaptations

Source: user-provided devotica-terraform-study-notes.pdf, read locally; no PDF uploaded to GitHub.

| PDF requirement | Implementation / boundary |
| --- | --- |
| pp. 8-9 module anatomy | main, variables, outputs, locals, data, versions; no backend/provider configuration in module |
| Every input typed/described/validated | All 12 module variables with validation and nullable=false |
| Stable resource addresses | Singleton resources; for_each for subnet/SG reads; no count-based resources |
| Basic <=10 lines / complete inputs | examples/basic/main.tf / examples/complete/main.tf |
| p. 15 unit/contract/integration | Mock plan tests, mock apply output contracts, separate opt-in integration directory |
| p. 10 CI | SHA-pinned actual shared workflow; all_green aggregator; local credential-free policy gate |
| p. 16 tool stack | Shared lint, tfsec successor, secrets, docs, Checkov, optional Infracost; local OPA |
| p. 10 release | Shared release-please/cosign/CycloneDX workflow; floating major retag disabled |
| pp. 6, 12-14 OIDC/state | Manual sandbox OIDC workflow; consumer guide owns encrypted state and locking |
| Mandatory tags | Six keys verified against Devotica's public policy, plus MSK-specific enforcement |

Upstream inspected 2026-11-02:
- https://github.com/devotica-labs/terraform-shared-config/tree/26fb3202dc77a47e503c9149f402b144c8b54c12
- https://github.com/devotica-labs/terraform-policies/blob/main/policies/01_mandatory_tags.rego
- https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/msk_cluster

Known upstream boundaries: shared conftest invokes a real AWS plan, so it is replaced with
the mock-plan gate here. Shared tfsec job now uses Trivy. The shared docs job declares contents:write
even with auto-update=false; the wrapper grants the required permission but never enables auto-update.
Shared Trivy and SBOM actions have mutable upstream references; pinning the reusable workflow alone
does not pin those nested actions. Cosign signs tag-name text, not the commit/archive digest.
Resolve these supply-chain items in terraform-shared-config before claiming fully pinned source provenance.

Terraform >=1.7 (rather than PDF >=1.6) supports provider mocks. Integration is nested to keep
plain terraform test safe. Broker family support is deliberately limited to m5/m7g in this iteration.
Live regional availability, route privacy, SG rules, key permissions, actual log delivery and
Kafka client access require an explicitly approved AWS integration exercise.
