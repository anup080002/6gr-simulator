# 6GR PUCCH/UCI Codex implementation pack

Use this pack from the simulator repository root.

1. Copy this directory to `tests/vectors/pucch/`.
2. Open `CODEX_PROMPT_05_PUCCH_UCI_WITH_IMPACT_ANALYSIS.md` and give the entire prompt to Codex.
3. Codex must edit the production MATLAB source and execute the commands in the prompt. A plan-only response is not completion.
4. Run `python verify_pucch_vector_pack.py` before and after source work.
5. Accept the base phase only when `verify_pucch_artifacts.py <artifact-dir>` exits 0.
6. Accept impact analysis only when `verify_pucch_impact_artifacts.py <impact-artifact-dir>` exits 0.

Key counts:

- 10 implementation findings
- 4,271 deterministic manifest rows
- 50 impact families
- 600 controlled experiments
- 75 acceptance rules
- 23 base CSVs and 15 base PNGs
- 16 impact CSVs and 28 impact PNGs

The supplied vectors are a bounded independent floor. The prompt requires additional pure-spec or frozen vectors for selected-profile procedures not fully represented by the floor.
