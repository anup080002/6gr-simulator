function ok=testH4100ShortPublicationConfig()
% Configuration/export contract only: does not execute the 60-slot scenario
% or claim its final artifacts, feedback delivery or statistical acceptance.
setup6GRSimToolkit('Verbose',false);
prefix='simulator/configs/scenarios/';
parent=sixgr.lls6g.config.loadScenarioConfig( ...
    [prefix 'h4_100_cdlc100_connected_impaired_40db_adaptation.yaml']);
short=sixgr.lls6g.config.loadScenarioConfig( ...
    [prefix 'h4_100_cdlc100_connected_impaired_40db_short.yaml']);
full=parent.toStruct(); bounded=short.toStruct();
cfg=sixgr.lls6g.buildInternalConfig(short,tempname);
assert(cfg.run.totalSlots==60 && cfg.run.numTTI==60 && ...
    cfg.phy.fc_Hz==4e9 && cfg.phy.carrier.NSizeGrid==273 && ...
    cfg.phy.carrier.SubcarrierSpacing==30 && ...
    cfg.phy.nTxAnt==64 && cfg.phy.nRxAnt==4);
assert(bounded.run_control.total_time_ms==30 && ...
    bounded.run_control.measurement_slots==60 && bounded.run_control.measurement_time_ms==30 && ...
    bounded.simulation.n_frames==3 && bounded.simulation.n_slots==60 && ...
    bounded.simulation.n_subframes==30 && bounded.simulation.min_duration_s==.03 && ...
    bounded.random_access.num_slots==60 && bounded.random_access.num_subframes==30);
assert(cfg.phy.pdsch.maxLayers==4 && cfg.phy.pusch.maxLayers==4 && ...
    cfg.phy.linkAdaptation.rankIncreaseConfirmationReports==2 && ...
    cfg.phy.csi.reportPeriodicitySlots==20);
for name=["saveCSV","saveMAT","saveFigures","savePNG","saveRawWaveforms", ...
        "saveChannelSnapshots","saveConstellations","rawIQCaptureEnabled", ...
        "liveCSVPNGEnabled","executionStageProfileEnabled"]
    assert(isfield(cfg.outputs,name) && cfg.outputs.(name), ...
        'test:ShortOutputDisabled','Required configured output is disabled: %s.',name);
end
assert(~cfg.outputs.emitPlaceholderArtifacts && ...
    cfg.outputs.liveCSVPNGIntervalSlots==5 && cfg.run.runtimeCheckpointEnabled && ...
    cfg.run.checkpointFirstSlot==49 && cfg.run.checkpointEverySlots==3);
assert(string(short.get('output.publication_mode'))=="full" && ...
    ~any(lower(string(short.get('scenario.study_mode',"")))==["smoke","runner_smoke"]));
contract=logical(short.get('output.artifact_contract_engine.enabled'));
assert(contract && logical(short.get('output.artifact_contract_engine.fail_on_missing_required')));
publication=sixgr.lls6g.runners.resolveWaveformBundlePublicationPolicy(cfg,contract);
assert(publication.LiveCSVPNGEnabled && ~publication.SaveFigures, ...
    'Canonical terminal CSV/PNG materialization owns the figures; do not enable a second legacy raster writer.');
assert(sixgr.artifact.liveCSVPlotDue(cfg,60,60), ...
    'The final slot must publish even when live refresh is throttled.');
% Compare resolved sections, not YAML text. Nothing in channel/RF, access,
% scheduling, traffic, CSI/SRS or publication can silently revert to the old
% gate just because a shorter horizon was selected.
for group=string(fieldnames(full)).'
    if any(group==["meta","config_inheritance"]), continue; end
    a=full.(group); b=bounded.(group);
    switch group
        case "run_control"
            names={'total_slots','total_time_ms','measurement_slots','measurement_time_ms'};
        case "simulation"
            names={'n_frames','n_slots','n_subframes','min_duration_s'};
        case "random_access"
            names={'num_slots','num_subframes'};
        case "output"
            names={'profile'};
            % Pin the equivalent full terminal path explicitly; absence in
            % the parent is the production full-publication default.
            a.publication_mode=char(string(parent.get('output.publication_mode','full')));
        otherwise
            names={};
    end
    if ~isempty(names), a=rmfield(a,names); b=rmfield(b,names); end
    assert(isequaln(a,b),'test:ShortScenarioChangedPhysics', ...
        'Shortening the horizon changed the resolved %s section.',group);
end
assert(full.run_control.total_slots==100,'Do not overwrite the longer reference campaign.');
fprintf('H4_SHORT_PUBLICATION_CONFIG_PASS slots=60 duration_ms=30 outputs=enabled full_scenario_executed=0\n');
ok=true;
end
