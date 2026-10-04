function ok=testSLSNativeCSIFeedbackIntegration()
% Actual configured calendar -> committed CSI-RS -> causal modeled CSI ->
% rank/PMI binding. No BLER curve or waveform-decoded CSI is claimed.
request=sixgr.config.loadSimulationRequest( ...
    'simulator/configs/scenarios/sls_nr_tdd_21cell_connected.yaml');
cfg=request.Config;
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/finite_srs_csirs_interference.yaml'));
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/modeled_csirs_power_reference.yaml'));
cfg.run.executionID='native_csirs_feedback_integration';
cfg.run.seed=113;
cfg.phy.srs.enable=false;
cfg.phy.ssb.enable=false;
cfg.phy.trs.enable=false;
cfg.phy.sib1.enable=false;
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.system.linkAbstraction.networkSpatial.csirsScramblingIDs=[11 37];
cfg.system.linkAbstraction.dynamicPUCCH.resourceBinding.mode='shared_configured_resources';
cfg.phy.csi.allowUncalibratedBLERLUT=true;
calendar=sixgr.system.buildSLSCommonChannelCalendar(cfg,12);
assert(any(string(calendar.Allocations.channel)=="CSI_RS"));
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
queue=sixgr.system.abstraction.CausalDLCSIFeedback(cfg);
large=struct('Pathloss_dB',[80 85;87 81],'TxPower_dBm',[30 27;30 27]);
state=struct('TTI',1,'AbsoluteSlot0',0,'ServingCells',[1 2], ...
    'RNTIByUE',[4660 4661],'GrantsDL',struct([]),'GrantsUL',struct([]), ...
    'GrantCellsDL',[],'GrantCellsUL',[],'LargeScaleState',large, ...
    'CommonChannelAllocations',calendar.Allocations);
received=struct([]); transmitted=struct();
for slot=0:11
    state.TTI=slot+1; state.AbsoluteSlot0=slot;
    provider.commitSlotPopulation(state);
    observations=provider.observeCSI(state);
    for o=observations
        sixgr.system.abstraction.validateFeedbackCompletionClock(o,slot);
        assert(o.SourceAbsoluteSlot0==1 && o.CRI==0 && ...
            o.ReportAbsoluteSlot0==9 && o.AvailableAbsoluteSlot0==10);
        emitted=provider.committedCSIRSEmissions(o.SourceAbsoluteSlot0+1);
        emitter=emitted([emitted.ServingCellID]==o.ServingCell & [emitted.CRI]==o.CRI);
        assert(isscalar(emitter) && o.ReferenceResourceID==emitter.ResourceID && ...
            o.ReferenceEmissionSHA256==emitter.SHA256);
        assert(o.ReferenceCompletionEvidence.CSIRSInterferenceIncluded && ...
            ~o.ReferenceCompletionEvidence.PrimaryStudyAccepted && ...
            ~o.ReferenceCompletionEvidence.WaveformMeasured);
        thermal=10^((-174+10*log10(30000)+cfg.scenario.ue.noiseFigure_dB-30)/10);
        disturbance=o.ExternalCovariance-thermal*eye(4);
        assert(norm(disturbance(:))>0, ...
            'Native other-cell CSI-RS must reach the CSI rank/PMI disturbance.');
        queue.append(o,slot);
        unavailable=queue.powerReferenceAtSlotStart(o.UEIndex,o.ServingCell,slot);
        assert(~unavailable.Available,'A reference completed at slot end is not known at that slot start.');
        power=o.ModeledPowerReference;
        assert(power.ReferenceEmissionSHA256==emitter.SHA256 && ~power.WaveformMeasured && ...
            power.RNTI==state.RNTIByUE(o.UEIndex) && power.ReferenceRECount>0 && ...
            abs(power.RSRP_dBm-(10*log10(power.RSRP_W)+30))<1e-12);
        received=[received o]; %#ok<AGROW>
    end
    if slot<10
        assert(isempty(queue.select(1,1,slot,slot+1)), ...
            'The scheduler cannot use CSI before its configured report delivery.');
    end
    if slot==9
        power=queue.powerReferenceAtSlotStart(1,1,slot);
        assert(power.Available && ~power.WaveformMeasured && power.KnownAtAbsoluteSlot0==9 && ...
            isempty(queue.select(1,1,9,9)), ...
            'UE reference availability must not wait for gNB report delivery or expose CSI early to the scheduler.');
        transmitted=queue.reportForTransmission(1,1,9,9);
        assert(transmitted.Available && ~transmitted.WaveformBacked && ...
            transmitted.SelectedFeedback.RNTI==4660 && ...
            transmitted.SelectedFeedback.ReferenceEmissionSHA256==received(1).ReferenceEmissionSHA256);
        typedRequest=cfg.phy.csi.reportConfiguration; typedRequest.Rank=transmitted.SelectedFeedback.RI;
        typed=sixgr.phy.mimo.CSIReportConfiguration(typedRequest,cfg.phy.csi.reportConfigurationEpoch);
        values=typed.decode(transmitted.Part1Bits,transmitted.Part2Bits);
        assert(values.RI==transmitted.SelectedFeedback.RI && values.PMI==transmitted.SelectedFeedback.PMI && ...
            values.CQI_CW0==transmitted.SelectedFeedback.CQI);
        id=cfg.phy.frame.DefaultIdentity;
        ue=struct('UEID',1,'RNTI',4660,'ServingCell',1,'PUCCHCell',1, ...
            'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
        frame=struct('TargetSlot',10,'PDSCHEndSlot',10,'K1',0,'K1Source',"configured_CSI_occasion");
        planned=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(cfg,ue, ...
            transmitted.Part1Bits,transmitted.Part2Bits,frame);
        bound=sixgr.system.abstraction.materializeModeledPUCCH(cfg,planned,power,9);
        ps=bound.Assignment.PowerControlState.Data;
        assert(~ps.RuntimeMeasuredPathlossUsed && ps.ModeledReference.BindingSHA256==power.BindingSHA256 && ...
            ps.PathlossdB==power.PathlossdB && ps.MRB==bound.Assignment.Resource.Data.NumPRBs);
        carrier=sixgr.phy.grid.makeCarrier(cfg); carrier.NSlot=9;
        tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,bound.Assignment,bound.Report);
        expected=min(ps.PCMAXdBm,ps.P0dBm+ps.PathlossdB+10*log10(2^ps.Mu*ps.MRB)+ ...
            ps.DeltaFdB+ps.DeltaTFdB+ps.ClosedLoopAdjustmentdB);
        assert(tx.TransmissionPresent && abs(tx.Power.AppliedPowerdBm-expected)<1e-12 && ...
            ~tx.Power.RuntimeMeasuredPathlossUsed);
        malformed=power; malformed.PathlossdB=power.PathlossdB+1;
        reject(@()sixgr.system.abstraction.materializeModeledPUCCH(cfg,planned,malformed,9), ...
            'sixgr:abstraction:PowerReferenceIdentity');
        reject(@()sixgr.system.abstraction.materializeModeledPUCCH(cfg,planned,struct('Available',false),9), ...
            'sixgr:abstraction:MissingModeledPowerReference');
        reject(@()sixgr.system.abstraction.materializeModeledPUCCH(cfg,planned,power,10), ...
            'sixgr:phy:pucch:StaleConfiguration');
    end
end
assert(numel(received)==2 && isempty(provider.referenceFeedbackPending()));
wrongCell=queue.powerReferenceAtSlotStart(1,2,11);
assert(~wrongCell.Available, ...
    'A reference for another serving cell cannot control UE power.');
expired=queue.powerReferenceAtSlotStart(1,1,1+cfg.system.linkAbstraction.dynamicPUCCH.powerReference.maximumAgeSlots+1);
assert(~expired.Available, ...
    'Expired power references must not fall back to configured pathloss.');
r=queue.select(1,1,10,11);
assert(~isempty(r) && ~r.WaveformBacked && ismember(r.RI,[1 2 4]) && ...
    r.ReferenceEmissionSHA256==received(1).ReferenceEmissionSHA256);
assert(r.ObservationID==transmitted.SelectedFeedback.ObservationID);
r.RNTI=4660;
r.BindingSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(sixgr.util.jsonSafeValue(r)),'UTF-8'))));
grant=struct('ModeledCSIFeedback',r,'RNTI',4660,'ServingCell',1, ...
    'NumLayers',r.RI,'PMI',r.PMI,'ControlAbsoluteSlot',10, ...
    'ScheduledAbsoluteSlot',11,'HARQ',struct('IsRetransmission',false));
sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(cfg,grant);
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
save(fullfile(folder,'native_csi_feedback.mat'),'cfg','calendar','received','grant','transmitted');
fprintf('SLS_NATIVE_CSI_FEEDBACK_PASS cells=2 source=1 report=9 delivery=10 RI=%d evidence=%s\n',r.RI,folder);
ok=true;
end
function reject(f,id)
try
    f();
catch err
    assert(strcmp(err.identifier,id),'Unexpected error: %s',err.identifier); return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
