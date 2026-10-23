function ok = testExecutedDataIdentity()
% Actual one-frame DL/UL export regression plus metadata negative cases.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg = sixgr.config.defaultConfig();
cfg = withCanonicalSchedulerTiming(cfg);
cfg.run.shortRun = true;
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.csirs.enable = false;
cfg.phy.csirs.enabled = false;
cfg.phy.pdsch.RNTI = 181;
cfg.phy.pusch.RNTI = 182;
cfg.phy.rnti = 999; % stale legacy alias must never own exported identity
cfg.lls6g.userContext.UEIndex = 2;

for direction = ["DL","UL"]
    channel = "PDSCH"; expected = 181;
    if direction == "UL", channel = "PUSCH"; expected = 182; end
    tx = struct(); tx.(channel) = struct('RNTI',expected);
    bound = sixgr.link.bindExecutedDataIdentity(struct(),tx,cfg,direction);
    assert(bound.RNTI == expected && bound.UEIndex == 2);
    assert(bound.RNTISource == "executed_" + lower(channel) + "_configuration");
    mustFail(@()sixgr.link.bindExecutedDataIdentity( ...
        struct('RNTI',999),tx,cfg,direction),'sixgr:link:ExecutedDataIdentityMismatch');
    tx.PHYGrant.ChannelStateKey = struct('RNTI',expected,'UEIndex',1);
    mustFail(@()sixgr.link.bindExecutedDataIdentity( ...
        struct(),tx,cfg,direction),'sixgr:link:ExecutedDataIdentityMismatch');
    tx = rmfield(tx,'PHYGrant');
    unknown = sixgr.link.bindExecutedDataIdentity(struct(),tx,struct(),direction);
    assert(isnan(unknown.UEIndex) && ...
        unknown.UEIdentitySource == "unavailable_no_executed_ue_binding");
    if direction == "DL"
        result = sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',1, ...
            'SNR_dB',18,'ExecutionProfile','phy_calibration');
    else
        result = sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',1,'SNR_dB',18);
    end
    assert(~result.Skipped && height(result.TrialTable)==1, ...
        'test:ExecutedDataTrialMissing','Expected an actual %s trial.',direction);
    T = result.TrialTable;
    assert(T.RNTI==expected && T.UEIndex==2, ...
        'test:ExecutedDataIdentityMissing','%s trial dropped actual TX identity.',direction);
    assert(strlength(string(T.GrantContextId))>0);
    assert(T.ExecutedResourceIntervalSource=="executed_TX_RE_runs_PRB_symbol_union_not_RF_activity" && ...
        strlength(T.ExecutedResourceIntervalsJSON)>0);
    intervals=jsondecode(T.ExecutedResourceIntervalsJSON);
    assert(all([intervals.AbsoluteSlotIndex0]==T.Slot-1));
    expanded=sixgr.truth.expandExecutedResourceIntervals(T,cfg);
    assert(height(expanded)==numel(intervals) && all(expanded.NumSymbols==1) && ...
        isequal(sort(expanded.SymbolStart),sort([intervals.SymbolIndex0].')));
    fprintf('%s actual trial: UEIndex=%d RNTI=%d; stale alias=%d rejected as authority.\n', ...
        direction,T.UEIndex,T.RNTI,cfg.phy.rnti);
end
ok = true;
end

function mustFail(fn,id)
try
    fn();
catch ME
    assert(string(ME.identifier)==string(id),'%s: %s',ME.identifier,ME.message);
    return;
end
error('test:MissingIdentityRejection','Expected %s.',id);
end
