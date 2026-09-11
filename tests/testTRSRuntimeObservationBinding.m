function ok = testTRSRuntimeObservationBinding(mode)
% One complete waveform per configured consecutive-slot tracking resource set.
setup6GRSimToolkit('Verbose',false);
if nargin<1, mode="TDD"; end
scenario='lls_causal_access_to_data_wiring_tdd.yaml';
if string(mode)=="FDD", scenario='lls_causal_access_to_data_wiring.yaml'; end
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios',scenario));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
assert(isequal(double(cfg.phy.trs.slotNumbers(:).'),[7 8]) && cfg.phy.trs.burstLengthSlots==2);
resourceSlots = [];
startSlots = [];
for slot = 1:30
    w = sixgr.truth.resolveTRSObservationWindow(cfg,slot);
    assert(sixgr.truth.isActiveTRSOccasion(cfg,slot)==w.ResourceActive);
    if w.ResourceActive, resourceSlots(end+1)=slot-1; end %#ok<AGROW>
    if w.ObservationStarts, startSlots(end+1)=slot-1; end %#ok<AGROW>
end
assert(isequal(resourceSlots,[7 8 17 18 27 28]));
assert(isequal(startSlots,[7 17 27]));
preparedSlots = [];
for frame = 0:2
  for firstSlot=7
    authoredSlots=firstSlot+(0:1);
    p = sixgr.link.prepareTRSTransmission(cfg,12,'RuntimeSlot',frame*10+firstSlot+1);
    assert(p.StrictConfig.StrictValidation.StrictValid);
    assert(isequal(p.Tx.SlotTable.Slot,frame*10+authoredSlots(:)));
    assert(p.Tx.FirstSlot0Based==frame*10+firstSlot);
    assert(p.NumSamples==round(0.002*p.SampleRateHz));
    assert(numel(p.StrictConfig.ToolboxResources)==2);
    assert(all(p.Tx.ResourceMappingTable.CSIRSRowNumber==1) && ...
        all(p.Tx.ResourceMappingTable.NumCSIRSPorts==1) && ...
        all(string(p.Tx.ResourceMappingTable.Density)=="three"));
    preparedSlots = [preparedSlots; p.Tx.SlotTable.Slot]; %#ok<AGROW>
    for k = 1:numel(p.Tx.GridSlots)
        carrier = p.Tx.GridSlots(k).Carrier;
        assert(carrier.NFrame==frame);
        assert(carrier.NSlot==authoredSlots(k));
        expected=[];
        for r=1:2
            expected=[expected;nrCSIRS(carrier,p.StrictConfig.ToolboxResources{r})]; %#ok<AGROW>
        end
        assert(isequal(expected,p.Tx.GridSlots(k).Symbols));
        assert(p.Tx.GridSlots(k).NRE==6*p.StrictConfig.NumRB);
        mapping=p.Tx.ResourceMappingTable(p.Tx.ResourceMappingTable.Slot==frame*10+authoredSlots(k),:);
        assert(isequal(unique(mapping.Symbol0Based).',[4 8]) && ...
            numel(unique(mapping.LinearIndex1Based))==height(mapping));
        % Modulate each actual resource independently, not a relabeled
        % earlier-frame waveform, and compare its retained transmit span.
        expectedWave = nrOFDMModulate(carrier,p.Tx.GridSlots(k).Grid,'Windowing',0);
        assert(norm(expectedWave-p.Tx.SlotWaveforms{k},'fro')<1e-10);
    end
  end
end
assert(isequal(preparedSlots.',resourceSlots));
assert(numel(unique(preparedSlots))==numel(preparedSlots));
localMustFail(@()sixgr.link.prepareTRSTransmission(cfg,12,'RuntimeSlot',9), ...
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
bad.phy.trs.slotNumbers=[2 7];
localMustFail(@()sixgr.truth.resolveTRSObservationWindow(bad,3),'sixgr:truth:NonconsecutiveTRSBurst');
bad=cfg; bad.phy.trs.symbolLocation=4;
localMustFail(@()sixgr.link.prepareTRSTransmission(bad,12,'RuntimeSlot',8), ...
    'sixgr:phy:trs:UnsupportedTrackingSymbolPair');
bad=cfg; bad.phy.trs.csirsRowNumber=2;
localMustFail(@()sixgr.link.prepareTRSTransmission(bad,12,'RuntimeSlot',8), ...
    'sixgr:phy:trs:InvalidTrackingDensityPorts');
bad = cfg;
bad.phy.numerology.slotsPerFrame = 20;
localMustFail(@()sixgr.link.prepareTRSTransmission(bad,12,'RuntimeSlot',8), ...
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
