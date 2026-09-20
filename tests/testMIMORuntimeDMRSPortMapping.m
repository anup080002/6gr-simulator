function ok=testMIMORuntimeDMRSPortMapping()
% Evidence-reducer fixture, not a physical rank-adaptation execution.
% A one-layer bootstrap cannot define the DM-RS count of later grants.
setup6GRSimToolkit('Verbose',false);
cfg=struct();
cfg.scenario.bs=struct('nTxAnt',4,'nRxAnt',4);
cfg.scenario.ue=struct('nTxAnt',4,'nRxAnt',4);
for channel=["pdsch","pusch"]
    cfg.phy.(channel)=struct('numLayers',1,'nLayers',1, ...
        'NumAntennaPorts',4,'mcsIndex',0,'modulation',"QPSK");
end
cfg.link_adaptation.fixed_or_amc="amc";
cfg.mimo.rank_adaptation_policy="adaptive";
raw=struct();
for direction=["DL","UL"]
    raw.(direction)=table((1:3).',[1;2;4],[1;2;4], ...
        repmat("QPSK",3,1),zeros(3,1),true(3,1), ...
        ["12";"12|12";"12|12|12|12"],[1;2;4], ...
        'VariableNames',{'TrialId','Layers','RankEstimate','Modulation', ...
        'MCS','CRCPass','PostEqSINRPerLayer_dB','MeasuredDMRSPortCount'});
end
out=sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg,raw,'StrictMode',true);
assert(all(out.AntennaPortMapping.Status=="pass"), ...
    'test:MIMOBootstrapDMRSPortCount', ...
    'Per-trial measured DM-RS evidence must validate rank 1/2/4, not bootstrap rank one.');
assert(all(out.AntennaPortMapping.DMRSPortCount==1), ...
    'Do not rewrite nominal bootstrap metadata using runtime evidence.');
assert(isequal(out.RankLayerTrials.MeasuredDMRSPortCount,[1;2;4;1;2;4]), ...
    'The primary source counts must survive the evidence reducer unchanged.');
assert(all(strlength(out.RankLayerTrials.DMRSPorts)==0) && ...
    all(isnan(out.LayerMetrics.DMRSPort)), ...
    'A measured count must not manufacture DM-RS port identities.');
% A bad minority row cannot be hidden by a mode/median or a valid other link.
for direction=["DL","UL"]
    for invalid=[0,1,1.5,NaN,Inf]
        bad=raw;
        bad.(direction).MeasuredDMRSPortCount(2)=invalid;
        rejected=sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg,bad,'StrictMode',true);
        selected=rejected.AntennaPortMapping.Direction==direction;
        assert(rejected.AntennaPortMapping.Status(selected)=="fail", ...
            'test:MIMOInvalidDMRSEvidence','Invalid per-trial evidence must fail.');
        assert(rejected.AntennaPortMapping.Status(~selected)=="pass");
    end
    bad=raw;
    bad.(direction)=removevars(bad.(direction),'MeasuredDMRSPortCount');
    rejected=sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg,bad,'StrictMode',true);
    assert(rejected.AntennaPortMapping.Status( ...
        rejected.AntennaPortMapping.Direction==direction)=="fail", ...
        'test:MIMOMissingDMRSEvidence', ...
        'Neither configured nor transmitted layers can manufacture measured DM-RS evidence.');
end
ok=true;
fprintf('MIMO_RUNTIME_DMRS_PORT_MAPPING_PASS directions=2 ranks=1,2,4 negative_cases=12\n');
end
