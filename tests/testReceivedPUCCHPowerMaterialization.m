function ok=testReceivedPUCCHPowerMaterialization()
% Actual unit-link decoded DCI plus declared installed
% boundary; validates preview binding, not shared physical TX integration.
setup6GRSimToolkit('Verbose',false);
f=fixture(); cfg=f.Inputs{1}.Config;
ue=struct('UEID',1,'RNTI',f.Installation.RNTI,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
frame=struct('K1',1,'K1Source','configured_periodic_CSI_report_occasion', ...
    'PDSCHEndSlot',8,'TargetSlot',9,'DecodedPRI',0,'PRIFieldWidth',3, ...
    'PRIProvenance','not_used_CSI','FirstCCE',0,'NumCCE',8, ...
    'SlotSymbolOwnership',"UUUUUUUUUUUUUU",'FlexibleResolutionProvided',false);
initial=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
frame.SchedulingRequestStates=sixgr.phy.pucch.SchedulingRequestState.atSlot(initial,8);
cfg.validation.pucch_resources.power_control.require_measured_reference_rs=false;
cfg.validation.pucch_resources.power_control.closed_loop_mode='configured';
planned=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(cfg,ue,int8([1;0;1;0]),int8([]),frame);
base=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned);
b=f.Installation;
b.UEID=ue.UEID; b.ServingCell=ue.ServingCell; b.ComponentCarrier=ue.ComponentCarrier;
b.ActiveULBWP=ue.ActiveULBWP;
b.P0_dBm=base.Assignment.PowerControlState.Data.P0dBm;
b.P0PUCCHID=base.Assignment.SpatialRelationState.Data.P0PUCCHID;
b.ClosedLoopIndex=base.Assignment.SpatialRelationState.Data.ClosedLoopIndex;
owner=sixgr.link.ReceivedPUCCHPowerControlState(b);
i=f.Inputs{1}; owner=owner.ingestReceivedDCI(i.Config,i.Assignment,i.Receipt);
f.Installation=b; s=14*8+planned.Plan.Resource.Data.StartSymbol;
o=struct('ObservationID',"declared_power_preview_only",'ResourceID',planned.Plan.Resource.ID, ...
    'ResourceDigest',planned.Plan.Resource.Digest,'ReportDigest',planned.Plan.ReportDigest, ...
    'TimingDigest',digest(struct('Symbol',s,'Sample',sampleAt(f,s))), ...
    'UEID',b.UEID,'RNTI',b.RNTI,'ServingCell',b.ServingCell, ...
    'ComponentCarrier',b.ComponentCarrier,'ActiveULBWP',b.ActiveULBWP, ...
    'ClosedLoopIndex',b.ClosedLoopIndex,'P0PUCCHID',b.P0PUCCHID, ...
    'StartSample',sampleAt(f,s),'EndSampleExclusive',sampleAt(f,s+planned.Plan.Resource.Data.NumSymbols), ...
    'StartSymbolBoundary',s,'DecisionSample',sampleAt(f,s),'SampleRateHz',f.Fs, ...
    'ClockEpoch',b.ClockEpoch,'SubcarrierSpacingKHz',b.SubcarrierSpacingKHz, ...
    'RepetitionCount',1,'Procedure',"autonomous_csi",'ResponseAssignmentDigest',"");
proposal=owner.resolveOccasion(o); before=owner.digest(); random=rng;
assert(proposal.UpdatedG_dB==1);
cfg.validation.pucch_resources.power_control.closed_loop_mode='received_dci';
binding=struct('Owner',owner,'Proposal',proposal);
actual=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned,binding);
assert(actual.Assignment.PowerControlState.Data.ClosedLoopAdjustmentdB==1 && ...
    actual.Assignment.PowerControlState.Data.ReceivedPowerProposalDigest==proposal.Digest && ...
    isempty(owner.History) && owner.digest()==before && isequal(rng,random));
% Actual original generated waveform power, not a metadata-only preview.
% This component comparison does not claim shared channel/receiver execution.
txCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,9);
carrier=sixgr.phy.grid.makeCarrier(txCfg);
referenceTx=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,base.Assignment,base.Report);
receivedTx=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,actual.Assignment,actual.Report);
delta=receivedTx.Power.AppliedPowerdBm-referenceTx.Power.AppliedPowerdBm;
assert(abs((receivedTx.Power.MeasuredWaveformPowerdBm-referenceTx.Power.MeasuredWaveformPowerdBm)-delta)<1e-10 && ...
    abs(receivedTx.Power.PowerError_dB)<1e-10 && isempty(owner.History) && owner.digest()==before);
assert(receivedTx.Assignment.PowerControlState.Data.ReceivedPowerProposalDigest==proposal.Digest);
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned),'sixgr:truth:ReceivedPUCCHPowerBinding');
bad=binding; bad.Proposal.UpdatedG_dB=3;
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned,bad),'sixgr:truth:ReceivedPUCCHPowerBinding');
bad=binding; bad.Proposal.Occasion.ReportDigest=digest('not_the_original_report');
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned,bad),'sixgr:truth:ReceivedPUCCHPowerBinding');
cfg.validation.pucch_resources.power_control.closed_loop_mode='configured';
reject(@()sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned,binding),'sixgr:truth:ReceivedPUCCHPowerBinding');
ok=true;
end

function f=fixture()
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_ssb_physical_power_contract_fixture.yaml');
base=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(~sixgr.rf.isNormalizedFixedSNRPowerReference(base));
% Component inputs remain the installed connected DCI policy. No expected
% TX fields are substituted for the CRC-accepted receiver assignment.
commands=[2 3 0 1]; slots=[0 5 10 15]; k1=[8 1 1 1];
f=struct('Inputs',{cell(1,4)},'Carrier',sixgr.phy.grid.makeCarrier(base));
for k=1:4
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(base,slots(k)+1);
    c=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
    defs=sixgr.phy.pdcch.DCISchemaEngine.resolve(c).Definitions;
    fields=struct(); for d=defs(:).', fields.(d.Name)=d.ValueMin; end
    fields.frequency_resource_assignment=cfg.phy.carrier.NSizeGrid*5+3;
    fields.mcs=0; fields.rv=0; fields.ndi=0; fields.harq_process=2;
    fields.tpc_command_for_pucch=commands(k);
    timing=find(c.Data.DLDataToULACK==k1(k));
    assert(isscalar(timing),'test:FixtureTiming','The declared fixture must retain its installed K1.');
    fields.pdsch_to_harq_feedback_timing=timing-1;
    packet=sixgr.phy.pdcch.DCIPacker.pack(fields,c);
    tx=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',packet.Bits,'RNTI',c.Data.RNTIValue);
    % Exact native monitored prefix, not invented early decode availability.
    samples=tx.TransmitSamples(1:tx.MinimumReceiveSamples,:);
    [rx,info]=sixgr.phy.dl.PDCCH_Rx(samples,cfg,'SampleRate_Hz',tx.SampleRateHz);
    a=sixgr.phy.pdcch.materializeConnectedDCI(rx,info,cfg);
    assert(a.Fields.tpc_command_for_pucch==commands(k) && a.K1Slots==k1(k));
    used=[rx.MonitoredDataREIndices(:);rx.MonitoredDMRSREIndices(:)];
    K=size(rx.RxGrid,1); L=rx.ReferenceGridSymbolsPerSlot;
    syms=unique(floor(mod(double(used)-1,K*L)/K));
    assert(L==14 && ~isempty(syms));
    f.Fs=tx.SampleRateHz;
    startSymbol=14*slots(k)+min(syms); endSymbol=14*slots(k)+max(syms)+1;
    startSample=sampleAt(f,startSymbol); endSample=sampleAt(f,endSymbol);
    available=sixgr.phy.frame.slotStartSample(tx.Tx.Carrier,slots(k),f.Fs)+size(samples,1);
    assert(available>=endSample);
    r=struct('ObservationID',"original_unit_link_PDCCH_"+k, ...
        'AssignmentDigest',string(a.AssignmentDigest), ...
        'TimingDigest',digest(struct('Indices',double(used),'Symbols',syms, ...
            'StartSample',startSample,'EndSampleExclusive',endSample,'AvailableAtSample',available)), ...
        'PDCCHStartSymbolBoundary',startSymbol,'PDCCHEndSymbolBoundary',endSymbol, ...
        'PDCCHStartSample',startSample,'PDCCHEndSampleExclusive',endSample, ...
        'AvailableAtSample',available,'SampleRateHz',f.Fs,'ClockEpoch',0, ...
        'SubcarrierSpacingKHz',double(cfg.phy.carrier.SubcarrierSpacing), ...
        'ReceiverAccepted',true,'ReceiverSelectionSource',string(rx.DCISelectionSource));
    f.Inputs{k}=struct('Config',cfg,'Assignment',a,'Receipt',r);
end
c=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(f.Inputs{1}.Config,'1_1');
% Deliberately nontrivial configured-index/runtime-ID mapping. This is an
% explicit installation boundary fixture, not a decoded network mapping.
f.Installation=struct('InstallationID',"declared_dedicated_P0_event_1", ...
    'UEID',3,'RNTI',double(c.Data.RNTIValue),'ServingCell',7,'ComponentCarrier',9, ...
    'ActiveULBWP',double(base.phy.bwp.ul.BWPID), ...
    'DCIServingCellIndex',double(c.Data.ControlServingCell), ...
    'DCIComponentCarrierIndex',double(c.Data.ControlCarrier), ...
    'ClosedLoopIndex',0,'P0PUCCHID',4,'P0_dBm',-90, ...
    'EffectiveSample',0,'EffectiveSymbolBoundary',0,'AvailableAtSample',0, ...
    'SampleRateHz',f.Fs,'ClockEpoch',0, ...
    'SubcarrierSpacingKHz',double(base.phy.carrier.SubcarrierSpacing), ...
    'CyclicPrefix',"normal",'CommonK2Slots',0,'ProcessingCapability',"capability1", ...
    'Source',"installed_dedicated_p0_configuration");
assert(f.Installation.ServingCell~=f.Installation.DCIServingCellIndex+1 && ...
    f.Installation.ComponentCarrier~=f.Installation.DCIComponentCarrierIndex);
end


function sample=sampleAt(f,symbol)
carrier=f.Carrier; slot=floor(symbol/14); within=mod(symbol,14);
carrier.NFrame=floor(slot/carrier.SlotsPerFrame); carrier.NSlot=mod(slot,carrier.SlotsPerFrame);
info=nrOFDMInfo(carrier,'SampleRate',f.Fs,'Windowing',0);
offset=mod(carrier.NSlot,carrier.SlotsPerSubframe)*14;
lengths=double(info.SymbolLengths(:));
sample=sixgr.phy.frame.slotStartSample(carrier,slot,f.Fs)+sum(lengths(offset+(1:within)));
end

function d=digest(value)
d=string(sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(jsonencode(value),'UTF-8'))));
end

function reject(fn,id)
try, fn(); catch ME
    assert(strcmp(ME.identifier,id),'test:WrongGuard','Expected %s, got %s: %s',id,ME.identifier,ME.message);
    return
end
error('test:MissingGuard','Expected %s.',id);
end
