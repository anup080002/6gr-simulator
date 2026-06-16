# LLS Standards Claim Policy

Strict LLS output must not imply broad normative `3GPP`, `6G`, `Rel-20`, or
standards conformance unless the claim profile is exact and every mandatory
runtime evidence row is implemented, proxy-free, and artifact-backed.

Allowed study/profile labels include:

- `run_completed`
- `nr_baseline_study`
- `nr_inspired_research`
- `rel20_study_context`
- `experimental_6g_study`
- `strict_anchor_internal`
- `standards_mapped_nr_profile`

Forbidden broad conformance wording is rejected in strict runs unless exact
proof exists. Rejected claims emit AUD-001 and force:

- `ClaimAllowed=false`
- `ClaimStatus=claim_rejected`
- `StandardsConformanceOk=false`
- `ResultOk=false`

Audit artifacts:

- `reports/csv/standards_claim_audit.csv`
- `reports/csv/public_output_claim_scan.csv`
