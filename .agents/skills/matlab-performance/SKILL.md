---
name: matlab-performance
description: Optimize MATLAB and MEX hot paths in the simulator without changing semantic outputs. Use when editing fast kernels, MEX wrappers, vectorized PHY or system paths, BLER calibration or lookup code, or campaign fast-proxy code that must preserve strict validation, channel-estimation fidelity, and result integrity.
---

# Matlab Performance

Use this skill when you need speed without semantic drift.

## Workflow

1. Identify the exact reference path and artifact contract before optimizing anything.
2. Constrain the optimization:
- Preserve table shapes, labels, and manifest fields.
- Preserve truth and proxy separation.
- Do not hide strict-mode failures behind fallback or synthetic data.
- Do not use scalar full-grid channel estimates on fading channels.
3. Optimize the smallest hot path possible and keep the fallback path exact.
4. Run the targeted tests from `references/checks.md`.
5. If the accelerated path can only approximate semantics, label it as proxy and keep it out of primary truth exports.

## Review cues

- Prefer exact MATLAB fallback over approximate silent drift.
- A speedup is not valid if it changes `Source`, `ExecutionBackend`, `ApproximationMode`, or grant-trace meaning.
- Fast E2E and MEX paths must preserve the same validation failures that the reference path would raise.

Read `references/checks.md` before changing MEX wrappers or fast E2E paths.
