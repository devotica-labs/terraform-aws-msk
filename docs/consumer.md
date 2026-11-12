# Consumer structure

Use a separate consumer repository, for example `sample-infra/msk/` with main.tf, variables.tf,
outputs.tf, versions.tf, `backend/config.sandbox.hcl`, `backend/config.prod.hcl`,
`tfvars/sandbox.tfvars` and `tfvars/prod.tfvars`. Keep service-first layout as in the PDF.

Only the consumer declares `backend "s3" {}`. Populate bucket, unique key
`<project>/msk/<environment>.tfstate`, region, encrypt=true, kms_key_id and the existing lock
configuration from verified bootstrap outputs. PDF references S3+DynamoDB locking; review
the installed Terraform version and the team's S3 lockfile migration before changing that setup.
Never put sandbox account values from the reference PDF into a reusable module.

For local development use a relative source pointing to this checkout. Once published,
consume `devotica-labs/msk/aws` with an approved version constraint, e.g. `~> 1.0` only after
that release exists. Pin production versions and commit the consumer provider lock file.
Review plan in a PR, use OIDC, require non-author approval for production, and manage drift
in the consumer repo. This local module build neither creates bootstrap resources nor configures
remote repositories, cloud state, GitHub environments or deployment credentials.
