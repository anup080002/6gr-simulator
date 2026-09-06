function ok = testTRSRuntimeObservationBinding()
% One prepared multi-slot observation per authored frame, not per resource.
setup6GRSimToolkit('Verbose',false);
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
assert(isequal(double(cfg.phy.trs.slotNumbers(:).'),[2 7]));
resourceSlots = [];
startSlots = [];
for slot = 1:30
    w = sixgr.truth.resolveTRSObservationWindow(cfg,slot);
    assert(sixgr.truth.isActiveTRSOccasion(cfg,slot)==w.ResourceActive);
    if w.ResourceActive, resourceSlots(end+1)=slot-1; end %#ok<AGROW>
    if w.ObservationStarts, startSlots(end+1)=slot-1; end %#ok<AGROW>
end
assert(isequal(resourceSlots,[2 7 12 17 22 27]));
assert(isequal(startSlots,[2 12 22]));
preparedSlots = [];
authoredSlots = [2 7];
for frame = 0:2
    p = sixgr.link.prepareTRSTransmission(cfg,12,'RuntimeSlot',frame*10+3);
    assert(p.StrictConfig.StrictValidation.StrictValid);
    assert(isequal(p.Tx.SlotTable.Slot,frame*10+[2;7]));
    assert(p.Tx.FirstSlot0Based==frame*10+2);
    assert(p.NumSamples==round(0.006*p.SampleRateHz));
    preparedSlots = [preparedSlots; p.Tx.SlotTable.Slot]; %#ok<AGROW>
    for k = 1:numel(p.Tx.GridSlots)
        carrier = p.Tx.GridSlots(k).Carrier;
        assert(carrier.NFrame==frame);
        assert(carrier.NSlot==authoredSlots(k));
        expected = nrCSIRS(carrier,p.StrictConfig.ToolboxCSIRS);
        assert(isequal(expected,p.Tx.GridSlots(k).Symbols));
        % Modulate each actual resource independently, not a relabeled
        % earlier-frame waveform, and compare its retained transmit span.
        expectedWave = nrOFDMModulate(carrier,p.Tx.GridSlots(k).Grid,'Windowing',0);
        assert(norm(expectedWave-p.Tx.SlotWaveforms{k},'fro')<1e-10);
    end
end
assert(isequal(preparedSlots.',resourceSlots));
assert(numel(unique(preparedSlots))==numel(preparedSlots));
localMustFail(@()sixgr.link.prepareTRSTransmission(cfg,12,'RuntimeSlot',8), ...
    'sixgr:phy:trs:NotObservationStart');
bad = cfg;
bad.phy.trs.slotNumbers = [2 2 7];
localMustFail(@()sixgr.truth.resolveTRSObservationWindow(bad,3), ...
    'sixgr:truth:InvalidTRSResourceSlots');
bad.phy.trs.slotNumbers = [2 10];
localMustFail(@()sixgr.truth.resolveTRSObservationWindow(bad,3), ...
    'sixgr:truth:InvalidTRSResourceSlots');
bad.phy.trs.slotNumbers = [2 7.1];
localMustFail(@()sixgr.truth.resolveTRSObservationWindow(bad,3), ...
    'sixgr:truth:InvalidTRSResourceSlots');
bad = cfg;
bad.phy.numerology.slotsPerFrame = 20;
localMustFail(@()sixgr.link.prepareTRSTransmission(bad,12,'RuntimeSlot',23), ...
    'sixgr:phy:trs:RuntimeFrameTimingMismatch');
% Main-runtime adapter must distinguish resources from observation starts
% and pass the actual runtime slot through to the waveform producer.
source = fileread(which('sixgr.truth.runWaveformLinkBundle'));
assert(contains(source,'shouldAttemptTRS = trsWindow.ObservationStarts;'));
assert(contains(source,'"ChannelState",chState,"RuntimeSlot",'));
ok = true;
disp('TRS_RUNTIME_OBSERVATION_BINDING_PASS');
end

function localMustFail(f,identifier)
caught = false;
try
    f();
catch cause
    caught = strcmp(cause.identifier,identifier);
end
assert(caught,'Expected strict failure %s.',identifier);
end
