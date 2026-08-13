function seeds = trialSeeds(cfg,snrDB,trialIndex)
%TRIALSEEDS Allocate collision-free deterministic C0 waveform seeds.
% The allocation is independent of run mode. Each configured 0.25-dB SNR
% point owns four non-overlapping blocks, one each for channel, CFO, noise,
% and timing. The block capacity is the fixed TDOC maximum trial count.

configuredSNRs=[double(cfg.snr.minimum_db) double(cfg.snr.maximum_db) ...
    double(cfg.snr.coarse_grid_db(:).') ...
    double(cfg.statistics.high_snr_sanity_db) ...
    double(cfg.validation.zero_impairment_anchor_snr_db)];
minimumSNR = min(configuredSNRs);
step = double(cfg.snr.refinement_step_db);
maximumSNR = max(configuredSNRs);
capacity = double(cfg.statistics.tdoc_max_trials_per_point);
snrDB = double(snrDB);
trialIndex = double(trialIndex);

pointIndex = round((snrDB-minimumSNR)/step)+1;
reconstructedSNR = minimumSNR+(pointIndex-1)*step;
if ~(isscalar(snrDB) && isfinite(snrDB) && snrDB>=minimumSNR && ...
        snrDB<=maximumSNR && abs(snrDB-reconstructedSNR)<=1e-9)
    error("sixgr:phy:ia:c0:seed:SNRGrid", ...
        "SNR %.12g dB is outside [%g,%g] or is not aligned to the configured %.12g-dB refinement grid.", ...
        snrDB,minimumSNR,maximumSNR,step);
end
if ~(isscalar(trialIndex) && isfinite(trialIndex) && ...
        trialIndex==round(trialIndex) && trialIndex>=1 && trialIndex<=capacity)
    error("sixgr:phy:ia:c0:seed:TrialRange", ...
        "trialIndex must be an integer in [1,%d].",capacity);
end

base = double(cfg.run.seed_set_main)+(pointIndex-1)*4*capacity;
values = base+(0:3)*capacity+trialIndex;
if any(values>2^32-1)
    error("sixgr:phy:ia:c0:seed:RangeOverflow", ...
        "Configured C0 seed partition exceeds the MATLAB twister seed range.");
end
seeds = struct("PointIndex",pointIndex,"TrialIndex",trialIndex, ...
    "Channel",values(1),"CFO",values(2),"Noise",values(3), ...
    "Timing",values(4),"CapacityPerDomain",capacity, ...
    "Policy","disjoint_snr_domain_trial_blocks_v1");
end
