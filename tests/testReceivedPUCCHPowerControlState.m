function ok=testReceivedPUCCHPowerControlState()
% Native PDCCH inputs; DECLARED PUCCH emission/power boundary fixtures.
% This tests the unintegrated value-state owner, NOT shared PUCCH execution,
% power accuracy, decoded RRC installation, RF, or a complete feedback loop.
setup6GRSimToolkit('Verbose',false);
originalRNG=rng; restore=onCleanup(@()rng(originalRNG)); %#ok<NASGU>
rng(90231,'twister');
f=fixture();
checks={@()receivedCommands(f),@()historicalBranches(f),@()netSaturation(f), ...
    @()processingAndNoTransmission(f),@()resetAndLateDelivery(f), ...
    @()invalidReceipts(f),@()valueStatePersistence(f)};
names=["native_received_commands","historical_cutoff_branches","net_saturation", ...
    "processing_and_no_TX","P0_reset_and_late_delivery","typed_receipt_guards","value_state_RNG"];
failures=strings(0,1);
for k=1:numel(checks)
    try
        checks{k}(); fprintf('RECEIVED_PUCCH_G_PASS %s\n',names(k));
    catch ME
        failures(end+1)=names(k)+": "+string(getReport(ME,'extended','hyperlinks','off')); %#ok<AGROW>
        fprintf(2,'RECEIVED_PUCCH_G_FAIL %s: %s\n',names(k),ME.message);
    end
end
assert(isempty(failures),'test:ReceivedPUCCHPowerControlState','%s',strjoin(failures,newline));
fprintf(['RECEIVED_PUCCH_G_SCOPE native_PDCCH_decodes=4 PUCCH_waveforms=0 ' ...
    'runtime_integrated=0 physical_power_qualified=0 declared_TX_boundaries_only=1\n']);
ok=true;
end

function f=fixture()
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
base=sixgr.lls6g.buildInternalConfig(s,tempname);
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

function receivedCommands(f)
o=sixgr.link.ReceivedPUCCHPowerControlState(f.Installation);
before=rng;
for k=1:4
    [o,c]=ingest(o,f,k);
    expected=[1 3 -1 0];
    assert(c.Delta_dB==expected(k) && c.AssignmentDigest==f.Inputs{k}.Assignment.AssignmentDigest);
    assert(c.PDCCHEndSymbolBoundary==f.Inputs{k}.Receipt.PDCCHEndSymbolBoundary && ...
        c.AvailableAtSample==f.Inputs{k}.Receipt.AvailableAtSample);
end
assert(isequal(before,rng) && numel(o.Commands)==4 && isempty(o.History));
reject(@()ingest(o,f,1),'sixgr:power:PUCCHReceivedClock'); % original result is also chronologically old
only=ingest(sixgr.link.ReceivedPUCCHPowerControlState(f.Installation),f,1);
reject(@()ingest(only,f,1),'sixgr:power:PUCCHDuplicateTPC');
b=f.Installation; b.DCIServingCellIndex=b.DCIServingCellIndex+1;
wrong=sixgr.link.ReceivedPUCCHPowerControlState(b);
reject(@()ingest(wrong,f,1),'sixgr:power:PUCCHWrongEndpoint');
b=f.Installation; b.DCIComponentCarrierIndex=b.DCIComponentCarrierIndex+1;
wrong=sixgr.link.ReceivedPUCCHPowerControlState(b);
reject(@()ingest(wrong,f,1),'sixgr:power:PUCCHWrongEndpoint');
end

function historicalBranches(f)
o=ingest(ingest(sixgr.link.ReceivedPUCCHPowerControlState(f.Installation),f,1),f,2);
a1=f.Inputs{1}.Assignment; a2=f.Inputs{2}.Assignment;
assert(a1.HARQFeedbackAbsoluteSlot>a2.HARQFeedbackAbsoluteSlot);
p=o.resolveOccasion(occasion(f,14*a2.HARQFeedbackAbsoluteSlot+10,"dci_response",a2.AssignmentDigest));
assert(p.PreviousHistoryIndex==0 && p.NetTPC_dB==4 && p.UpdatedG_dB==4);
o=commit(o,p,23,-40,23);
% Later physical response has an earlier cutoff: it must NOT inherit g=4
% or the unrelated most recent maximum-power saturation state.
p=o.resolveOccasion(occasion(f,14*a1.HARQFeedbackAbsoluteSlot+10,"dci_response",a1.AssignmentDigest));
assert(p.PreviousHistoryIndex==0 && p.UpdatedG_dB==1 && ~p.PreviousAtMaximumPower);
o=commit(o,p,-40,-40,23);
p=o.resolveOccasion(occasion(f,14*a1.HARQFeedbackAbsoluteSlot+11,"dci_response",a1.AssignmentDigest));
assert(p.PreviousHistoryIndex==0 && p.UpdatedG_dB==1 && ~p.PreviousAtMinimumPower);
o=commit(o,p,23,-40,23);
p=o.resolveOccasion(occasion(f,14*(a1.HARQFeedbackAbsoluteSlot+1)+10,"autonomous_csi",""));
assert(p.PreviousHistoryIndex==3 && p.PreviousG_dB==1 && p.NetTPC_dB==3 && ...
    p.TPCAdjustmentHeldAtPowerLimit && p.UpdatedG_dB==1);
assert(~p.RuntimeIntegrated && ~p.PhysicalExecutionQualified);
end

function netSaturation(f)
o=ingest(sixgr.link.ReceivedPUCCHPowerControlState(f.Installation),f,1);
p=o.resolveOccasion(occasion(f,24,"autonomous_csi",""));
assert(p.UpdatedG_dB==1);
atMax=commit(o,p,23,-40,23); atMin=commit(o,p,-40,-40,23);
atMax=ingest(ingest(atMax,f,2),f,3);
atMin=ingest(ingest(atMin,f,2),f,3);
q=occasion(f,164,"autonomous_csi","");
p=atMax.resolveOccasion(q);
assert(p.NetTPC_dB==2 && p.PreviousG_dB==1 && p.UpdatedG_dB==1 && p.TPCAdjustmentHeldAtPowerLimit);
% Clamp-after-each-command (+3 held, then -1 applied) would wrongly give0.
assert(numel(p.AppliedOrHeldAssignmentDigests)==2 && isempty(p.DeferredAssignmentDigests));
p=atMin.resolveOccasion(q);
assert(p.NetTPC_dB==2 && p.UpdatedG_dB==3 && ~p.TPCAdjustmentHeldAtPowerLimit);
% Same +3/-1 command window, but first positive command was transmitted
% below the cap. The later negative command must release a saturated g.
o=ingest(ingest(sixgr.link.ReceivedPUCCHPowerControlState(f.Installation),f,1),f,2);
p=o.resolveOccasion(occasion(f,94,"autonomous_csi",""));
assert(p.UpdatedG_dB==4); o=commit(o,p,30,-40,23); o=ingest(o,f,3);
p=o.resolveOccasion(q);
assert(p.NetTPC_dB==-1 && p.UpdatedG_dB==3 && ~p.TPCAdjustmentHeldAtPowerLimit);
% A negative net is held at the actual minimum, including exact equality.
o=ingest(ingest(sixgr.link.ReceivedPUCCHPowerControlState(f.Installation),f,1),f,2);
p=o.resolveOccasion(occasion(f,94,"autonomous_csi",""));
o=commit(o,p,-40,-40,23); o=ingest(o,f,3); p=o.resolveOccasion(q);
assert(p.NetTPC_dB==-1 && p.UpdatedG_dB==4 && p.TPCAdjustmentHeldAtPowerLimit);
end

function processingAndNoTransmission(f)
o=ingest(sixgr.link.ReceivedPUCCHPowerControlState(f.Installation),f,1);
r=f.Inputs{1}.Receipt; start=r.PDCCHEndSymbolBoundary;
% Exact actual monitored-prefix receive availability must fit this early
% declared occasion; never backdate result availability to force the case.
assert(sampleAt(f,start)>=r.AvailableAtSample,'test:FixtureReceiveExtent', ...
    'Native monitored prefix contains later symbols; choose an honest boundary.');
q=occasion(f,start,"autonomous_sr",""); before=o.digest(); p=o.resolveOccasion(q);
assert(p.NetTPC_dB==0 && p.UpdatedG_dB==0 && numel(p.DeferredAssignmentDigests)==1);
assert(o.digest()==before && isempty(o.History) && isequaln(p,o.resolveOccasion(q)));
% Missing PL / negative SR is represented here ONLY by no commit. The real
% preparation owner remains responsible for admission and actual RX/DTX.
o=commit(o,p,-10,-40,23);
p=o.resolveOccasion(occasion(f,start+20,"autonomous_csi",""));
assert(p.NetTPC_dB==1 && p.UpdatedG_dB==1 && isempty(p.DeferredAssignmentDigests));
assert(isempty(p.WindowAssignmentDigests) && numel(p.AppliedOrHeldAssignmentDigests)==1);
o=commit(o,p,-10,-40,23);
p=o.resolveOccasion(occasion(f,start+21,"autonomous_csi",""));
assert(p.NetTPC_dB==0 && p.UpdatedG_dB==1 && isempty(p.AppliedOrHeldAssignmentDigests));
% Common K2 is an independent configured cutoff, not the ACK K1.
b=f.Installation; b.CommonK2Slots=[1 4];
o=ingest(sixgr.link.ReceivedPUCCHPowerControlState(b),f,1);
p=o.resolveOccasion(occasion(f,start+1,"autonomous_csi",""));
assert(p.KPUCCHSymbols==14 && p.CutoffSymbolBoundary==start+1-14 && p.NetTPC_dB==0);
end

function resetAndLateDelivery(f)
o=ingest(sixgr.link.ReceivedPUCCHPowerControlState(f.Installation),f,1);
p=o.resolveOccasion(occasion(f,24,"autonomous_csi","")); o=commit(o,p,23,-40,23);
b=f.Installation; b.InstallationID="same_numeric_P0_new_original_event";
b.EffectiveSymbolBoundary=28; b.EffectiveSample=sampleAt(f,28); b.AvailableAtSample=b.EffectiveSample;
o=o.install(b); p=o.resolveOccasion(occasion(f,38,"autonomous_csi",""));
assert(p.UpdatedG_dB==0 && p.PreviousHistoryIndex==0 && isempty(p.AppliedOrHeldAssignmentDigests));
assert(numel(o.Commands)==1 && numel(o.History)==1 && numel(o.Installations)==2);
reject(@()o.install(b),'sixgr:power:PUCCHDuplicateInstallation');
changed=b; changed.InstallationID="not_a_P0_only_event"; changed.DCIServingCellIndex=3;
reject(@()o.install(changed),'sixgr:power:PUCCHWrongEndpoint');
% No command was known at this committed occasion. A later callback for
% old physical control cannot be relabeled as Tproc2 postponement.
o=sixgr.link.ReceivedPUCCHPowerControlState(f.Installation);
p=o.resolveOccasion(occasion(f,24,"autonomous_csi","")); o=commit(o,p,-10,-40,23);
reject(@()ingest(o,f,1),'sixgr:power:PUCCHLateControlAvailability');
end

function invalidReceipts(f)
empty=sixgr.link.ReceivedPUCCHPowerControlState(f.Installation);
i=f.Inputs{1}; r=i.Receipt; r.ReceiverAccepted=1;
reject(@()empty.ingestReceivedDCI(i.Config,i.Assignment,r),'sixgr:power:PUCCHReceivedCommand');
r=i.Receipt; r.PDCCHEndSampleExclusive=char(48);
reject(@()empty.ingestReceivedDCI(i.Config,i.Assignment,r),'sixgr:power:PUCCHClockInteger');
r=i.Receipt; r.AvailableAtSample=r.PDCCHEndSampleExclusive-1;
reject(@()empty.ingestReceivedDCI(i.Config,i.Assignment,r),'sixgr:power:PUCCHReceivedClock');
r=i.Receipt; r.IQ=zeros(2);
reject(@()empty.ingestReceivedDCI(i.Config,i.Assignment,r),'sixgr:power:PUCCHReceiptSchema');
b=f.Installation; b.ClosedLoopIndex=1;
reject(@()sixgr.link.ReceivedPUCCHPowerControlState(b),'sixgr:power:PUCCHUnsupportedInstallation');
b=f.Installation; b.CommonK2Slots=[];
reject(@()sixgr.link.ReceivedPUCCHPowerControlState(b),'sixgr:power:PUCCHCommonK2Required');
o=ingest(empty,f,1); q=occasion(f,24,"autonomous_csi","");
bad=q; bad.RepetitionCount=2;
reject(@()o.resolveOccasion(bad),'sixgr:power:PUCCHUnsupportedOccasion');
bad=q; bad.ServingCell=f.Installation.DCIServingCellIndex;
reject(@()o.resolveOccasion(bad),'sixgr:power:PUCCHWrongEndpoint');
bad=q; bad.DecisionSample=bad.StartSample-1;
reject(@()o.resolveOccasion(bad),'sixgr:power:PUCCHFinalBindingClock');
bad=q; bad.ClockEpoch=1;
reject(@()o.resolveOccasion(bad),'sixgr:power:PUCCHClockMismatch');
future=ingest(o,f,2);
reject(@()future.resolveOccasion(q),'sixgr:power:PUCCHFutureKnowledge');
p=o.resolveOccasion(q); [tx,power]=boundaryReceipts(p,-10,-40,23);
bad=p; bad.UpdatedG_dB=99;
reject(@()o.commitTransmission(bad,tx,power),'sixgr:power:PUCCHProposalChanged');
bad=tx; bad.CommittedAtSample=bad.FirstActiveSample;
reject(@()o.commitTransmission(p,bad,power),'sixgr:power:PUCCHTransmissionReceipt');
bad=power; bad.AppliedPower_dBm=bad.AppliedPower_dBm+1;
reject(@()o.commitTransmission(p,tx,bad),'sixgr:power:PUCCHPowerReceipt');
end

function valueStatePersistence(f)
before=rng; o=ingest(sixgr.link.ReceivedPUCCHPowerControlState(f.Installation),f,1);
p=o.resolveOccasion(occasion(f,24,"autonomous_csi",""));
n=commit(o,p,23,-40,23);
assert(isempty(o.History) && numel(n.History)==1 && o.digest()~=n.digest());
path=[tempname '.mat']; cleanup=onCleanup(@()delete(path)); %#ok<NASGU>
save(path,'n'); loaded=load(path,'n');
assert(isequaln(n,loaded.n) && n.digest()==loaded.n.digest() && isequal(before,rng));
end

function [o,c]=ingest(o,f,k)
i=f.Inputs{k}; [o,c]=o.ingestReceivedDCI(i.Config,i.Assignment,i.Receipt);
end

function q=occasion(f,s,procedure,response)
b=f.Installation;
q=struct('ObservationID',"declared_PUCCH_boundary_"+s,'ResourceID',1, ...
    'ResourceDigest',digest("declared_resource_not_executed_PUCCH"), ...
    'ReportDigest',digest("declared_payload_not_encoded_PUCCH"), ...
    'TimingDigest',digest(struct('StartSymbolBoundary',s,'SampleRateHz',f.Fs)), ...
    'UEID',b.UEID,'RNTI',b.RNTI,'ServingCell',b.ServingCell, ...
    'ComponentCarrier',b.ComponentCarrier,'ActiveULBWP',b.ActiveULBWP, ...
    'ClosedLoopIndex',b.ClosedLoopIndex,'P0PUCCHID',b.P0PUCCHID, ...
    'StartSample',sampleAt(f,s),'EndSampleExclusive',sampleAt(f,s+1), ...
    'StartSymbolBoundary',s,'DecisionSample',sampleAt(f,s),'SampleRateHz',f.Fs, ...
    'ClockEpoch',b.ClockEpoch,'SubcarrierSpacingKHz',b.SubcarrierSpacingKHz, ...
    'RepetitionCount',1,'Procedure',procedure,'ResponseAssignmentDigest',string(response));
end

function o=commit(o,p,requested,minimum,maximum)
[tx,power]=boundaryReceipts(p,requested,minimum,maximum);
o=o.commitTransmission(p,tx,power);
end

function [tx,power]=boundaryReceipts(p,requested,minimum,maximum)
% Supplied owner-boundary fixtures only. The source token is the API under
% test, NOT proof that a PUCCH sample was emitted in this component test.
q=p.Occasion;
tx=struct('TransmissionID',"declared_TX_"+q.ObservationID,'ObservationID',q.ObservationID, ...
    'AssignmentDigest',digest("declared_assignment_"+q.ObservationID), ...
    'PowerProposalDigest',p.Digest,'FirstActiveSample',q.StartSample, ...
    'CommittedAtSample',q.StartSample+1,'SampleRateHz',q.SampleRateHz, ...
    'ClockEpoch',q.ClockEpoch,'SubcarrierSpacingKHz',q.SubcarrierSpacingKHz, ...
    'Source',"actual_shared_PUCCH_transmission_started_not_receiver_outcome");
power=struct('PowerProposalDigest',p.Digest,'ClosedLoopAdjustment_dB',p.UpdatedG_dB, ...
    'P0_dBm',-90,'RequestedPower_dBm',requested, ...
    'AppliedPower_dBm',min(maximum,max(minimum,requested)), ...
    'PCMAX_dBm',maximum,'MinimumPower_dBm',minimum,'Source',"original_transmitted_PUCCH_power_state");
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
