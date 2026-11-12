# Manual sandbox integration

No integration test or deployment has been authorized or run as part of local implementation.
MSK is chargeable and slow to create/delete. Obtain explicit approval, a budget, and a cleanup owner.

1. Create GitHub Environment `sandbox-msk`, restrict it to main and require a non-author reviewer.
   Do this BEFORE enabling/running the integration workflow; GitHub can otherwise create an unprotected environment.
2. Set environment variables `AWS_OIDC_ROLE_ARN`, `AWS_SANDBOX_ACCOUNT_ID` and
   `MSK_INTEGRATION_TFVARS_JSON` (JSON for every required module input). Use unique test cluster names,
   a valid vpc_id, one private subnet per AZ, both CMK ARNs, region ap-south-1 and "environment": "sandbox".
3. Configure narrowly scoped OIDC trust for the repository and `environment:sandbox-msk`,
   plus deployment/read/delete permissions for the test resources, KMS and log delivery.
   The role must permit a 4-hour session. No stored AWS keys. Confirm runner access to AWS APIs.
4. Dispatch on main with confirmation `DEPLOY-SANDBOX-MSK` and obtain environment approval.
5. Terraform test applies, checks outputs/security and attempts destroy. This is a control-plane
   lifecycle check, not a Kafka produce/consume test. A private-network runner and IAM client
   smoke test are still needed to prove end-to-end data-plane connectivity.
6. Confirm cluster and log group deletion after completion. A cancelled runner, expired session
   or failed destroy can leave resources. Inspect the test cleanup diagnostics, retained recovery
   artifact/state if present, AWS console and unique test tags. Recover/import into a dedicated
   cleanup state and review a destroy plan before deleting. Never delete shared SGs/subnets/keys.

Do not upload real tfvars/state to source control. Recovery artifacts can be sensitive; restrict
repo access and delete them after cleanup. Test state is not your production state backend.
Do not run the integration directory as a routine local validation command.
