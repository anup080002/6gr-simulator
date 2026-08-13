function test_c0_seed_partitions()
%TEST_C0_SEED_PARTITIONS Prove all configured C0 seed ranges are disjoint.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","tdoc");
capacity=double(cfg.statistics.tdoc_max_trials_per_point);
configuredSNRs=[double(cfg.snr.minimum_db) double(cfg.snr.maximum_db) ...
    double(cfg.snr.coarse_grid_db(:).') ...
    double(cfg.statistics.high_snr_sanity_db)];
snrs=min(configuredSNRs):double(cfg.snr.refinement_step_db):max(configuredSNRs);
ranges=zeros(numel(snrs)*4,2); cursor=0;
for snr=snrs
    first=sixgr.phy.ia.c0.util.trialSeeds(cfg,snr,1);
    last=sixgr.phy.ia.c0.util.trialSeeds(cfg,snr,capacity);
    for domain=["Channel" "CFO" "Noise" "Timing"]
        cursor=cursor+1;
        ranges(cursor,:)=[double(first.(domain)) double(last.(domain))];
    end
end
ranges=sortrows(ranges,1);
assert(all(ranges(2:end,1)>ranges(1:end-1,2)), ...
    "Main C0 SNR/domain seed blocks overlap.");
calibration=double(cfg.run.seed_set_calibration)+ ...
    [1 double(cfg.false_alarm.calibration_trials)];
validation=double(cfg.run.seed_set_validation)+ ...
    [1 double(cfg.false_alarm.validation_trials)];
main=[ranges(1,1) ranges(end,2)];
assert(localDisjoint(main,calibration)&&localDisjoint(main,validation)&& ...
    localDisjoint(calibration,validation));
initial=sixgr.phy.ia.c0.util.initialSNRGrid(cfg);
assert(any(initial==double(cfg.statistics.high_snr_sanity_db)), ...
    "Configured high-SNR sanity point is missing from the initial sweep.");
refined=sixgr.phy.ia.c0.util.refinementSNRGrid(cfg,-7.13);
globalOrigin=min(configuredSNRs);
assert(all(abs((refined-globalOrigin)/double(cfg.snr.refinement_step_db)- ...
    round((refined-globalOrigin)/double(cfg.snr.refinement_step_db)))<1e-9), ...
    "Refined SNR values are not aligned to the seed grid.");

bad=cfg;
bad.run.seed_set_validation=bad.run.seed_set_calibration+200;
try
    sixgr.phy.ia.c0.config.validateScenario(bad);
    error("test_c0_seed_partitions:MissingFailure", ...
        "Overlapping false-alarm seed partitions were accepted.");
catch ME
    assert(ME.identifier=="sixgr:phy:ia:c0:config:SeedRangeOverlap", ...
        "Unexpected overlap failure: %s",ME.identifier);
end
fprintf('test_c0_seed_partitions: PASS (%d main blocks; no collisions)\n', ...
    height(ranges));
end

function value=localDisjoint(first,second)
value=max(first(1),second(1))>min(first(2),second(2));
end
