function ok=testCoupledReceivedRadioIdentity()
% Declared received-result contract tests, not physical access qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),1);
state.CurrentSlot=40; state.CurrentServingIdx=[1;1];
state.CellAcquisitionState(:)="acquired";
row=localReceivedRow(4660);
original=state;
assert(sixgr.truth.CoupledRadioIdentity.resolve(state,1)==1);
assert(~sixgr.truth.CoupledRadioIdentity.connectedReady(state,1));
savedSR=state.UEConfiguredSRProcedures{1,1};
savedSchedulerCfg=state.DLSchedulers{1}.Cfg;
state=sixgr.truth.CoupledTruthRuntime.applyPRACHTrial(state,1,row);
assert(state.AccessState(1)=="succeeded" && sixgr.truth.CoupledRadioIdentity.connectedReady(state,1));
assert(sixgr.truth.CoupledRadioIdentity.resolve(state,1)==4660 && ...
    sixgr.truth.CoupledRadioIdentity.resolve(state,2)==2);
assert(sixgr.truth.CoupledRadioIdentity.resolve(state,1,2)==1, ...
    'Do not transfer the received identity to another cell.');
assert(numel(state.RadioIdentityHistory)==1 && ...
    ~state.RadioIdentityHistory.MACRRCStandardsQualified);
unchanged=sixgr.truth.CoupledRadioIdentity.adopt(state,1,row,38);
assert(isequaln(unchanged,state),'Exact received completion replay must be idempotent.');
for dir=["DL","UL"]
    [bound,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,dir);
    assert(bound.phy.pdsch.RNTI==4660 && bound.phy.pusch.RNTI==4660 && ...
        bound.lls6g.userContext.RNTI==4660 && bound.lls6g.userContext.UEIndex==1);
    assert(bound.phy.srs.UEFrequencyResourceBinding.RNTI==4660);
    [~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(state,bound,1,dir,1);
    assert(ue.RNTI==4660);
    assert(sixgr.truth.CoupledRadioIdentity.dataRNTI(bound,1,dir)==4660);
    raw=table([4660;NaN],[1;NaN],[true;false], ...
        'VariableNames',{'RNTI','UEIndex','CRCPass'});
    annotated=sixgr.truth.CoupledRadioIdentity.annotateDataEvidence(raw,bound,1,dir);
    assert(all(annotated.RNTI==4660) && all(annotated.UEIndex==1) && ...
        isequal(annotated.CRCPass,raw.CRCPass));
    poisoned=raw; poisoned.RNTI(1)=1;
    localReject(@()sixgr.truth.CoupledRadioIdentity.annotateDataEvidence(poisoned,bound,1,dir), ...
        'sixgr:truth:DataEvidenceRadioIdentityMismatch');
    poisoned=raw; poisoned.UEIndex(1)=2;
    localReject(@()sixgr.truth.CoupledRadioIdentity.annotateDataEvidence(poisoned,bound,1,dir), ...
        'sixgr:truth:DataEvidenceRadioIdentityMismatch');
    wrongCfg=bound; wrongCfg.lls6g.userContext.RNTI=1;
    localReject(@()sixgr.truth.CoupledRadioIdentity.dataRNTI(wrongCfg,1,dir), ...
        'sixgr:truth:DataRadioIdentityMismatch');
    assert(isempty(sixgr.truth.CoupledRadioIdentity.annotateDataEvidence(table(),bound,1,dir)), ...
        'Identity annotation must not manufacture trial rows.');
    % A retained earlier operation is annotated from its original snapshot,
    % never from the latest state after access adoption.
    oldCfg=bound; oldCfg.phy.pdsch.RNTI=1; oldCfg.phy.pusch.RNTI=1;
    oldCfg.lls6g.userContext.RNTI=1;
    older=sixgr.truth.CoupledRadioIdentity.annotateDataEvidence( ...
        table(1,'VariableNames',{'RNTI'}),oldCfg,1,dir);
    assert(older.RNTI==1 && sixgr.truth.CoupledRadioIdentity.resolve(state,1)==4660);
end
id=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',4660,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
updated=sixgr.truth.CoupledRadioIdentity.configuration(cfg,state);
installed=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(updated,ue);
assert(~isempty(installed.Data.CSIResources));
wrongOwner=ue; wrongOwner.RNTI=1;
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(updated,wrongOwner), ...
    'sixgr:phy:pucch:UEReportBindingRNTI');
calendar=sixgr.truth.buildConfiguredSRCalendar(updated,ue,40,50);
assert(~isempty(calendar) && all(calendar.RNTI==4660));
sr=state.UEConfiguredSRProcedures{1,1};
for k=1:numel(sr)
    a=sr(k).Data; b=savedSR(k).Data;
    assert(a.RNTI==4660 && b.RNTI==1);
    a.RNTI=b.RNTI;
    assert(isequaln(a,b),'Do not reset SR pending/prohibit state on identity adoption.');
end
assert(savedSchedulerCfg.validation.pucch_resources.ue_report_bindings(1).rnti==1 && ...
    state.DLSchedulers{1}.Cfg.validation.pucch_resources.ue_report_bindings(1).rnti==4660);
% Actual scheduler freeze uses the new radio identity but the original UE
% ordinal to choose its configured PUCCH resource.
u=struct('RNTI',4660,'UEIndex',1,'ServingCell',1,'DLBufferBytes',20000, ...
    'ULBufferBytes',0,'CQI',8,'RI',1,'PMI',0,'CRI',0, ...
    'ControlEligible',true,'GrantControlState','ok','PDCCHAggregationLevel',8, ...
    'ReceivedCSIReport',struct());
budget=struct('PRBSet',cfg.phy.pdsch.prbSet,'SymbolAllocation',cfg.phy.pdsch.symbolAllocation, ...
    'ControlAbsoluteSlot',55,'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation, ...
    'PDCCHCCEBudget',8,'DefaultPDCCHAggregationLevel',8,'MaxUEPerSlot',1);
sch=sixgr.l2.mac.SchedulerPF(updated,'Direction','DL');
[g,~]=sch.schedule(55,u,budget);
assert(isscalar(g) && g.RNTI==4660 && g.UEIndex==1 && ...
    g.PHYGrant.ChannelStateKey.RNTI==4660 && ...
    g.PHYGrant.HARQProcessKey.RNTI==4660 && g.PUCCHResourceIndicator==0);
assert(sixgr.truth.CoupledRadioIdentity.grantUEIndex(g,2)==1);
assert(sixgr.truth.CoupledRadioIdentity.grantUEIndex(rmfield(g,'UEIndex'),2)==1);
wrongGrant=g; wrongGrant.UEIndex=2;
localReject(@()sixgr.truth.CoupledRadioIdentity.grantUEIndex(wrongGrant,2), ...
    'sixgr:truth:GrantUEIdentityMismatch');
localReject(@()sixgr.truth.CoupledRadioIdentity.grantUEIndex(struct('RNTI',4660),2), ...
    'sixgr:truth:MissingGrantUEIdentity');
% Actual coded PDCCH using the adopted identity, with independent connected
% receiver monitoring. Unit-channel component, not a full access scenario.
[rxCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,"DL");
rxCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(rxCfg,56);
carrier=sixgr.phy.grid.makeCarrier(rxCfg);
ofdm=nrOFDMInfo(carrier);
rxCfg.lls6g.userContext.RuntimeSlotStartTime_s= ...
    sixgr.phy.frame.slotStartSample(carrier,55,ofdm.SampleRate)/ofdm.SampleRate;
p=sixgr.link.preparePDCCHTransmission(rxCfg,'DCIBits',g.DCI.Bits,'RNTI',g.RNTI);
observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
    p.RuntimeStartSample,p.RuntimeStartSample+p.NumSamples,p.SampleRateHz,size(p.TransmitSamples,2));
observation.append(sixgr.phy.waveform.WaveformChunk(p.TransmitSamples,p.RuntimeStartSample),p.SampleRateHz);
[decoded,controlInfo]=sixgr.link.completePDCCHReception(p,observation);
assert(decoded.Ok && decoded.CausalGrantDecodeOk && controlInfo.ReceiverConfiguredMonitoring && ...
    isequal(decoded.DCIBits(:),g.DCI.Bits(:)) && controlInfo.RNTI==4660);
wrong=p; wrong.ReceiverConfig.phy.pdsch.RNTI=1; wrong.ReceiverConfig.phy.pusch.RNTI=1;
wrong.ReceiverConfig.phy.pdcch.rnti=1; wrong.ReceiverConfig.phy.pdcch.scramblingRNTI=1;
[notForBootstrap,~]=sixgr.link.completePDCCHReception(wrong,observation);
assert(~notForBootstrap.Ok,'The former bootstrap identity must not decode the connected command.');
frozen=g;
state.SharedScheduledDLGrantHistory={g};
% A different UE can adopt another identity without altering this grant.
row2=localReceivedRow(4661);
second=sixgr.truth.CoupledRadioIdentity.adopt(state,2,row2,38);
assert(isequaln(second.SharedScheduledDLGrantHistory{1},frozen) && ...
    sixgr.truth.CoupledRadioIdentity.resolve(second,2)==4661);
localReject(@()sixgr.truth.CoupledRadioIdentity.adopt(state,2,row,38), ...
    'sixgr:truth:RadioIdentityCollision');
localReject(@()sixgr.truth.CoupledRadioIdentity.adopt(state,1,row2,38), ...
    'sixgr:truth:ConflictingRadioIdentity');
localReject(@()sixgr.truth.CoupledRadioIdentity.adopt(original,1,row,41), ...
    'sixgr:truth:PrematureRadioIdentity');
for name=["RAPIDMatches","Msg4PDSCHCrcPass","ContentionIdentityMatches"]
    bad=row; bad.(name)=false;
    localReject(@()sixgr.truth.CoupledRadioIdentity.adopt(original,1,bad,38), ...
        'sixgr:truth:UnacceptedReceivedCRNTI');
end
bad=row; bad.FinalCRNTI=4662;
localReject(@()sixgr.truth.CoupledRadioIdentity.adopt(original,1,bad,38), ...
    'sixgr:truth:InvalidReceivedCRNTI');
bad=row; bad.FinalCRNTISource="configured_final_crnti";
localReject(@()sixgr.truth.CoupledRadioIdentity.adopt(original,1,bad,38), ...
    'sixgr:truth:UnacceptedReceivedCRNTI');
localReject(@()sixgr.truth.CoupledRadioIdentity.adopt(original,1, ...
    removevars(row,'FinalCRNTISource'),38),'sixgr:truth:MissingReceivedCRNTI');
busy=original; busy.DLHarq=sixgr.l2.mac.HARQEntityDL(cfg);
busy.DLHarq.allocate(1,39,8);
localReject(@()sixgr.truth.CoupledRadioIdentity.adopt(busy,1,row,38), ...
    'sixgr:truth:RadioIdentityWithActiveHARQ');
reset=sixgr.truth.CoupledRadioIdentity.resetAccess(second);
assert(isempty(reset.RadioIdentityBindings) && numel(reset.RadioIdentityHistory)==2 && ...
    sixgr.truth.CoupledRadioIdentity.resolve(reset,1)==1 && ...
    reset.CfgMobility.validation.pucch_resources.ue_report_bindings(1).rnti==1 && ...
    reset.UEConfiguredSRProcedures{1,1}(1).Data.RNTI==1 && isequaln(g,frozen));
ok=true;
fprintf('COUPLED_RECEIVED_RADIO_IDENTITY_PASS configured_1_received_4660=1 independent_UEs=1 frozen_grant_unchanged=1\n');
end

function row=localReceivedRow(rnti)
row=struct2table(struct('Status',"PASS",'CRCPass',NaN,'RACompleted',true, ...
    'RASlotTimeBase',"absolute_zero_based",'Slot',40,'Msg1ScheduledSlot',14, ...
    'Msg2ScheduledSlot',16,'Msg3ScheduledSlot',24,'Msg4ScheduledSlot',37, ...
    'RAPIDMatches',true,'Msg2DCICrcPass',true,'Msg2PDSCHCrcPass',true, ...
    'RARULGrantValid',true,'Msg3PUSCHCrcPass',true,'Msg4PDCCHCrcPass',true, ...
    'Msg4PDSCHCrcPass',true,'ContentionIdentityMatches',true, ...
    'TemporaryCRNTI',rnti,'FinalCRNTI',rnti, ...
    'FinalCRNTISource',"decoded_msg4_payload_after_contention_match", ...
    'FinalCRNTIEncodingProfile',"legacy_bounded_not_NR_MAC_RRC"));
end

function localReject(call,id)
try, call(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s: %s',id,err.identifier,err.message);
    return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
