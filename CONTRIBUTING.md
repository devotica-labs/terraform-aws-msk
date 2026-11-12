# Contributing

## Local setup

Install Terraform 1.7 or later, then initialize without a backend:

```powershell
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test
```

The unit and contract suites use Terraform mock providers and do not make AWS API calls.
The integration test is isolated under `tests/integration` and intentionally requires a
separate, explicit AWS-backed invocation.

## Commit format

Use [Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | Release impact |
| --- | --- |
| `feat:` | Minor |
| `fix:`, `docs:`, `chore:` | Patch |
| `feat!:` or `BREAKING CHANGE:` | Major |

## Review

Before enabling required code-owner review, replace the example in
`.github/CODEOWNERS` with the actual GitHub user or team for this module.
