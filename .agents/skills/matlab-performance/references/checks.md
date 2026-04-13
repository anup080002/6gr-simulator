# MATLAB Performance Checks

## Hotspots

- Root `sixgr_*_kernel.m` wrappers and corresponding `_mex` entry points
- `+sixgr/+phy/+rx/channelEstimate.m`: MEX paths must preserve fading-grid semantics or fall back to `nrChannelEstimate`
- `+sixgr/+system/BLER_DB.m`, `+sixgr/+system/BLER_LUT.m`, and `+sixgr/+hybrid/CalibrateBLER.m`: strict mode must reject synthetic defaults
- `sixgr_run_3gpp_full_campaign.m`: fast-proxy code must stay labeled as proxy and must not synthesize primary grant-level exports
- `+sixgr/+system/SystemLevelRunner.m`: performance changes cannot change grant or HARQ trace meaning

## Required tests

- `matlab -batch "setup6GRSimToolkit('Verbose',false); selftest6GRSimToolkit"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testHybrid; testHybrid_CalibrationCoverage; testStrictProxyGuards; testStrictMode_NoFallbackAnywhere"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testLLS_DL; testLLS_UL; testE2E_FastVsTruth"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testAll"`

## Optimization rules

- Speed up reference logic first; do not change artifact shape or labels to make benchmarks look better.
- Prefer exact MATLAB fallback over approximate silent drift.
- Treat scalar full-grid `Hest` as AWGN-only.
- Keep proxy vs truth provenance explicit in any accelerated path.
