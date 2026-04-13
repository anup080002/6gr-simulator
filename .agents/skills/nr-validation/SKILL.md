---
name: nr-validation
description: Validate strict NR simulator invariants for config normalization, fading profiles, truth-vs-proxy separation, scheduler grant semantics, and channel-estimation correctness. Use when editing +sixgr/+config, PHY or channel-estimation code, scheduler grant or TBS logic, strict-mode fallback guards, or tests that cover truth/proxy and fading-channel behavior.
---

# Nr Validation

Use this skill when a patch touches config loading, channel models, scheduler grants, or PHY truth/proxy behavior.

## Workflow

1. Identify the semantic source of truth before changing any fast path, normalization helper, or export.
2. Enforce these invariants:
- Require concrete `TDL-*` or `CDL-*` profiles.
- Keep proxy outputs labeled as proxy and truth outputs labeled as truth.
- Reject synthetic fallback in strict mode.
- On fading channels, require per-resource channel estimates. Scalar full-grid `Hest` is AWGN-only.
- Export grant-level TBS only from real grants, real transport blocks, or direct PHY allocation math.
3. Review the hotspot files listed in `references/checks.md`.
4. Run the smallest relevant test set from `references/checks.md`. If the patch crosses subsystem boundaries, run all listed tests.

## Review cues

- A normalization change is wrong if it manufactures a concrete profile from a bare model name.
- A MEX change is wrong if it can only return `hScalar` and then paints that scalar across a fading grid.
- A scheduler or export change is wrong if `TBSBits` is reconstructed from served bits instead of actual grant allocation.
- A truth/proxy change is wrong if summary rows stop distinguishing `truth`, `lut`, `logistic`, or `fast_proxy`.

Read `references/checks.md` for file-level guidance and commands.
