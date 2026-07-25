# Using the SSB / Initial Access / SIB1 / Random Access Codex Pack

1. Extract this directory into the simulator repository as:

```text
tests/vectors/initial_access/
```

2. Keep the vector files and verifiers read-only during implementation unless an independently demonstrated vector defect is found.

3. Open Codex at the repository root.

4. Paste the complete contents of:

```text
CODEX_PROMPT_06_SSB_INITIAL_ACCESS_SIB1_RA_WITH_IMPACT_ANALYSIS.md
```

5. Require Codex to edit the production MATLAB source and run the exact commands in the prompt.

6. Do not accept a plan-only response, unexecuted class skeletons, same-Toolbox “independent” comparisons, or a result that stops at Msg4 without RRCSetupComplete.

7. Run the pack integrity check before and after implementation:

```bash
python tests/vectors/initial_access/verify_initial_access_vector_pack.py
```

8. Validate base and impact artifacts:

```bash
python tests/vectors/initial_access/verify_initial_access_artifacts.py artifacts/initial_access_phase
python tests/vectors/initial_access/verify_initial_access_impact_artifacts.py artifacts/initial_access_impact
```

The bounded strict profile is FR1 four-step contention-based random access through successful RRCSetupComplete. Two-step, CFRA, BFR, SUL, NTN and RedCap/eRedCap are required to reject explicitly until separately implemented and independently validated.
