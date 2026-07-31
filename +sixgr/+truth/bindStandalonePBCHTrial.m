function cfgTrial = bindStandalonePBCHTrial(cfg, snr_dB, trialIndex, ssbIndex)
%BINDSTANDALONEPBCHTRIAL Resolve one deterministic PBCH waveform trial.
%
% Each standalone trial must apply the requested operating point while
% using a distinct, reproducible noise seed.  The SSB index selected by the
% sweep is also materialized into configuration because the strict SIB1
% waveform generator consumes phy.ssb.runtimeSSBIndex.

arguments
    cfg (1,1) struct
    snr_dB (1,1) double {mustBeReal,mustBeFinite}
    trialIndex (1,1) double {mustBeInteger,mustBePositive}
    ssbIndex (1,1) double {mustBeInteger,mustBeNonnegative}
end

cfgTrial = sixgr.truth.bindStandaloneSNRPoint(cfg, snr_dB);
baseSeed = double(sixgr.util.structGet(cfgTrial, "run.seed", 1501));
if ~(isscalar(baseSeed) && isfinite(baseSeed) && baseSeed == round(baseSeed))
    error("sixgr:truth:InvalidStandalonePBCHBaseSeed", ...
        "Standalone PBCH waveform trials require a finite integer run.seed.");
end
cfgTrial = sixgr.util.structSet(cfgTrial, ...
    "run.seed", baseSeed + double(trialIndex) - 1);
cfgTrial = sixgr.util.structSet(cfgTrial, ...
    "phy.ssb.runtimeSSBIndex", double(ssbIndex));
end
