# NR Validation Checks

## Hotspots

- `+sixgr/+config/normalizeConfig.m`: keep concrete-profile adoption one-way; never invent `TDL` or `CDL` profiles.
- `+sixgr/+config/validateConfig.m`: reject ambiguous channel models and mixed TDL/CDL families.
- `+sixgr/+phy/+rx/channelEstimate.m`: fast paths must not paint `hScalar` across fading grids.
- `+sixgr/+phy/+ul/PUSCH_Rx.m` and `+sixgr/+phy/+ul/PUCCH_Rx.m`: only use AWGN shortcuts on explicit AWGN paths.
- `+sixgr/+l2/+mac/SchedulerBase.m`: strict mode must reject rough TBS fallback.
- `sixgr_run_3gpp_full_campaign.m`: keep `truth`, `lut`, `logistic`, and `fast_proxy` outputs explicitly separated.

## Required tests

- `matlab -batch "setup6GRSimToolkit('Verbose',false); testConfig; testStrictProxyGuards; testStrictMode_NoFallbackAnywhere"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testLLS_DL; testLLS_UL; testLLS_ReferencePoints"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testSchedulerGrantConsistency"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testE2E_FastVsTruth; testE2E_TruthPacketSemanticCampaign"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testAll"`

## Failure signatures to respect

- `sixgr:config:AmbiguousChannelModel`
- `sixgr:config:BadChannelProfile`
- `SchedulerBase:TBSFallback`
- `StrictLogisticForbidden`
