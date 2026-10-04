function ok = testSystemMobilityElapsedClock()
% Production geometry clock regression, not decoded-throughput evidence.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.run.seed=31;
cfg.run.shortRun=false;
cfg.outputs.saveCSV=false;
cfg.outputs.saveMAT=false;
cfg.outputs.saveFigures=false;
cfg.outputs.saveFIG=false;
cfg.outputs.savePNG=false;
cfg.system.phyBackend='waveform';
cfg.system.beam.enable=false;
cfg.system.handover.enable=false;
cfg.scenario.layout.nSites=1;
cfg.scenario.layout.nSectorsPerSite=1;
cfg.scenario.nUE=1;
cfg.scenario.ue.nUE=1;
% An outdoor straight-line trajectory has no random indoor heading jitter;
% its independently replayed position is an exact elapsed-time oracle.
cfg.scenario.ue.indoorFraction=0;
cfg.scenario.ue.distribution.indoorFraction=0;
cfg.scenario.mobility.enable=true;
cfg.scenario.mobility.model='straightLine';
cfg.scenario.mobility.speed_kmh=[36 36];
cfg.channel.model='AWGN';
cfg.channel.awgnOnly=true;
cfg.channel.fading.enable=false;
cfg=withCanonicalSchedulerTiming(sixgr.config.normalizeConfig(cfg));
duration=sixgr.time.slotDurationSec(cfg);
root=fullfile(pwd,'results','sls','mobility_elapsed_clock', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
fprintf('MOBILITY_CLOCK_EVIDENCE_ROOT=%s\n',root);
for cadence=[1 3]
    cfg.system.mobility.updatePeriod_slots=cadence;
    n=8; % Last refresh at slot 6 must integrate 3 slots, not 2 remaining.
    ctx=sixgr.core.SimContext(cfg,'RunFolder',fullfile(root,sprintf('cadence_%d',cadence)));
    result=sixgr.system.SystemLevelRunner.run(ctx,struct('NumTTI',n, ...
        'DetailedTrace',true,'OfferedBitsDL',zeros(n,1),'OfferedBitsUL',zeros(n,1)));
    save(fullfile(root,sprintf('cadence_%d.mat',cadence)),'result','cfg','-v7.3');
    assert(result.Ok,'Production geometry run failed: %s',strjoin(string(result.Errors),'; '));
    D=result.Details;
    actual=[D.UEPosX_m D.UEPosY_m D.UEPosZ_m];
    expected=D.UEInitial.pos_m;
    assert(isequal(actual(1,:),expected),'Slot zero must retain the initial UE drop.');
    ue=D.UEInitial;
    ue.K=1;
    model=[];
    for slot=1:n-1
        if mod(slot,cadence)==0
            [ue,model]=sixgr.scenario.mobility.updatePositions(ue,cfg,cadence*duration,model);
        end
        assert(max(abs(actual(slot+1,:)-ue.pos_m))<1e-10, ...
            'Geometry at slot %d must integrate only elapsed cadence intervals.',slot);
    end
    assert(norm(actual(end,:)-actual(1,:))>0,'A moving trajectory must actually execute.');
    assert(sum(D.GrantCountDL+D.GrantCountUL)==0, ...
        'This clock regression must not be reported as physical data qualification.');
end
ok=true;
end
