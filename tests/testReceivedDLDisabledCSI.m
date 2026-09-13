function ok=testReceivedDLDisabledCSI()
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
saved=load(fullfile('docs','lls','evidence_20260913','received_dl_harq_calendar_02','attempt_4.mat'));
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,saved.a.ControlAbsoluteSlot+1);
cfg.phy.csirs.enable=false;
try
    saved.before.receive(cfg,saved.a,saved.delayed,'TimingSearchWindowSamples',[0 60]);
    error('test:MissingRejection','Disabled required CSI must be rejected.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:mimo:MissingMeasurementState'), ...
        'Expected strict-CSI dependency rejection, got %s.',ME.identifier);
end
% Optional-CSI boundary fixture, not a change to the strict 12 dB baseline.
cfg.phy.mimo.strict=false;
[rx,decision]=saved.before.receive(cfg,saved.a,saved.delayed, ...
    'TimingSearchWindowSamples',[0 60]);
fprintf('DISABLED_CSI_DIAGNOSTIC decision_equal=%d status=%s indices=%d observed=%d\n', ...
    isequaln(decision,saved.decision),rx.CSIRSObservation.RuntimeMaterializationStatus, ...
    numel(rx.CSIRSIndices),rx.CSIRSObservation.Observed);
for name=string(fieldnames(decision)).'
    if ~isequaln(decision.(name),saved.decision.(name))
        fprintf('DISABLED_CSI_DECISION_DIFFERENCE field=%s\n',name);
        disp(decision.(name)); disp(saved.decision.(name));
    end
end
assert(isequaln(decision,saved.decision));
assert(rx.CSIRSObservation.RuntimeMaterializationStatus=="disabled");
assert(isempty(rx.CSIRSIndices) && ~rx.CSIRSObservation.Observed);
fprintf('RECEIVED_DL_REPORT_DISABLED_CSI_PASS waveform=nonoccasion_capture guards=1\n');
ok=true;
end
