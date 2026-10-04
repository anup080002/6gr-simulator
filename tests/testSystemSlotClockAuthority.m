function ok = testSystemSlotClockAuthority()
% Physical time, grants and feedback use the same clock in both SLS backends.
for backend = ["waveform" "calibrated_link_abstraction"]
    for duplex = ["TDD" "FDD"]
        for mu = 0:3
            cfg = struct('phy',struct('carrier',struct( ...
                'SubcarrierSpacing',15*2^mu,'CyclicPrefix','normal'), ...
                'duplex',struct('mode',duplex)), ...
                'system',struct('phyBackend',backend));
            expected=1e-3/2^mu;
            assert(sixgr.system.resolveSlotDuration(cfg)==expected);
            assert(sixgr.system.resolveSlotDuration(cfg,struct('TTI_s',expected))==expected);
            cfg.system.tti_s=expected;
            assert(sixgr.system.resolveSlotDuration(cfg)==expected);
            localReject(@()sixgr.system.resolveSlotDuration(cfg,struct('TTI_s',0.25)), ...
                'sixgr:system:TTIClockMismatch');
            cfg.system.tti_s=2*expected;
            localReject(@()sixgr.system.resolveSlotDuration(cfg), ...
                'sixgr:system:TTIClockMismatch');
        end
    end
end
for bad = {0,-1,NaN,Inf,1i,[1 2],"0.001",true}
    localReject(@()sixgr.system.resolveSlotDuration(cfg,struct('TTI_s',bad{1})), ...
        'sixgr:system:InvalidTTIDuration');
end
% Verify the production runner rejects the mismatch before constructing
% traffic, grants or a calibration package, not only in a detached helper.
cfg=sixgr.config.defaultConfig();
ctx=sixgr.core.SimContext(cfg);
for backend=["waveform" "calibrated_link_abstraction"]
    localReject(@()sixgr.system.SystemLevelRunner.run(ctx, ...
        struct('NumTTI',1,'TTI_s',0.25,'PHYBackend',backend)), ...
        'sixgr:system:TTIClockMismatch');
end
ok=true;
end

function localReject(fn,id)
try
    fn();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message);
    return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
