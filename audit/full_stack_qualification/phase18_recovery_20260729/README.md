# Phase-18 recovery Codex pack

Copy this folder into the simulator repository at:

```text
audit/full_stack_qualification/phase18_recovery_20260729/
```

Then tell Codex to read and execute:

```text
CODEX_PROMPT_20_PHASE18_FINALIZATION_REGRESSION_AND_ARTIFACT_RECOVERY.md
```

Treat `evidence/` as immutable input from the failed WebGUI run `phase18_actual_20260729_01`.

Do not launch another complete qualification run until the recovery gates in Section 20 of the prompt pass.
