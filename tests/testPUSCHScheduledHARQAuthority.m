function ok=testPUSCHScheduledHARQAuthority()
% Retained UL DCI plus DECLARED DL identity fixtures, not physical mapping proof.
% The mock base has the production schema to test the binding contract only;
% it is never exported as actual scheduling, grant, receiver or PHY evidence.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_received_ul_harq_shared_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
localEmptyObligation(cfg);
cases=0;
for n=1:8
    retained=load(fullfile('docs','lls','evidence_20260913','scheduled_ul_dai_03', ...
        sprintf('scheduled_ul_dai_%d.mat',n)),'fixed');
    [grant,current]=localInstallCurrentULControl(cfg,retained.fixed);
    base=localBase(grant);
    before=grant;
    mapping=sixgr.truth.bindScheduledPUSCHHARQMapping(base,current,grant);
    assert(mapping.BitCount==n && isempty(mapping.ProtocolPaddingBitIndices) && ...
        mapping.ULTotalDAIRaw==mod(n-1,4) && isequaln(grant,before));
    % Contradictory UE/TX references must not change gNB assignment or width.
    poison=grant; poison.ExpectedUCIBits=ones(99,1,'int8');
    poison.UEReceivedAssignmentCount=0; poison.ControlDecodeOk=false;
    same=sixgr.truth.bindScheduledPUSCHHARQMapping(base,current,poison);
    assert(isequaln(mapping,same));
    % Add a declared monitoring occasion after the UL DCI, preserving the
    % already scheduled UL total DAI. Padding has no corresponding DL row.
    later=base; r=later.Records(end);
    r.BitIndex=n+1; r.TransmissionID="declared_later_tx";
    r.PHYGrantContextId="declared_later_grant"; r.HARQProcess=n;
    r.ControlAbsoluteSlot=grant.TimingDecision.ControlAbsoluteSlot;
    r.ControlStartSymbol=grant.TimingDecision.ControlSymbolAllocation(1)+1;
    r.SourceSlot=r.ControlAbsoluteSlot+1; r.CounterDAIRaw=mod(n,4);
    later.Records(end+1)=r; later.BitCount=n+1;
    later=localHash(later);
    padded=sixgr.truth.bindScheduledPUSCHHARQMapping(later,current,grant);
    assert(padded.BitCount==n+4 && padded.PhysicalAssignmentCount==n+1 && ...
        isequal(padded.ProtocolPaddingBitIndices,(n+2:n+4).'));
    % Transport dispatch uses the full receive width; the duplicate key is
    % the same physical DL obligation on either transport. Declared reducer
    % fixtures do not establish a received waveform or mutate a HARQ entity.
    observed=struct('MappingDigest',padded.Digest,'UEIndex',base.UEIndex, ...
        'RNTI',base.RNTI,'TargetSlot',base.TargetSlot,'Transport',"PUSCH", ...
        'DecodedBits',ones(padded.BitCount,1,'int8'),'DecodeOk',true,'DTXFlag',false);
    [rows,rebuilt,obligation]=sixgr.truth.mapScheduledHARQTransportFeedback(later,current,observed,grant);
    assert(isequaln(rebuilt,padded) && numel(rows)==n+1 && ...
        all([rows.ObservedAck]) && all([rows.ProtocolPaddingBitCount]==3) && ...
        obligation==later.Digest && obligation~=padded.Digest && ...
        all(string({rows.ObligationMappingDigest})==later.Digest));
    short=observed; short.DecodedBits=short.DecodedBits(1:n+1);
    shortRows=sixgr.truth.mapScheduledHARQTransportFeedback(later,current,short,grant);
    assert(~any([shortRows.ObservedAck]) && ~any([shortRows.ReceiverVectorLengthMatches]));
    onPUCCH=observed; onPUCCH.Transport="PUCCH";
    onPUCCH.MappingDigest=later.Digest; onPUCCH.DecodedBits=ones(n+1,1,'int8');
    [pucchRows,~,pucchObligation]=sixgr.truth.mapScheduledHARQTransportFeedback(later,current,onPUCCH);
    assert(pucchObligation==obligation && numel(pucchRows)==numel(rows));
    localReject(@()sixgr.truth.mapScheduledHARQTransportFeedback(later,current,observed), ...
        'sixgr:truth:MissingScheduledPUSCHHARQAuthority');
    localReject(@()sixgr.truth.mapScheduledHARQTransportFeedback(later,current,onPUCCH,grant), ...
        'sixgr:truth:ConflictingScheduledFeedbackTransport');
    absentCSI=struct('ReportConfigID',"",'ConfigurationEpoch',NaN);
    context=sixgr.truth.buildScheduledPUSCHUCIReceiveContext(padded,"declared_ul_observation",absentCSI);
    budget=context.bitBudget();
    assert(budget.OACK==n+4 && budget.OCSI1==0 && budget.OCSI2==0 && ...
        context.Data.HARQMappingDigest==padded.Digest);
    badCSI=absentCSI; badCSI.ExpectedPayloadBits=int8([1;0]);
    localReject(@()sixgr.truth.buildScheduledPUSCHUCIReceiveContext(padded,"declared_ul_observation",badCSI), ...
        'sixgr:truth:InvalidScheduledPUSCHCSIObligation');
    bad=grant; bad.ULTotalDAIAuthority.RawDAI=mod(bad.ULTotalDAIAuthority.RawDAI+1,4);
    localReject(@()sixgr.truth.bindScheduledPUSCHHARQMapping(base,current,bad), ...
        'sixgr:truth:ChangedScheduledPUSCHHARQAuthority');
    bad=grant; bad.UEIndex=grant.UEIndex+1;
    localReject(@()sixgr.truth.bindScheduledPUSCHHARQMapping(base,current,bad), ...
        'sixgr:truth:ScheduledPUSCHHARQContextMismatch');
    bad=base; bad.Records(1).PHYGrantContextId="different_dl_grant"; bad=localHash(bad);
    localReject(@()sixgr.truth.bindScheduledPUSCHHARQMapping(bad,current,grant), ...
        'sixgr:truth:UnexecutedPUSCHHARQAssignment');
    bad=base; bad.Records(1).ControlStartSymbol=99; bad=localHash(bad);
    localReject(@()sixgr.truth.bindScheduledPUSCHHARQMapping(bad,current,grant), ...
        'sixgr:truth:ScheduledPUSCHHARQAssignmentMismatch');
    cases=cases+2;
end
fprintf('PUSCH_SCHEDULED_HARQ_AUTHORITY_PASS declared_bindings=%d no_new_RF_execution\n',cases);
ok=true;
end

function localEmptyObligation(cfg)
% Empty physical owner plus retained scheduled UL DCI: schema qualification,
% not a newly executed UL waveform or a measured CSI report.
retained=load(fullfile('docs','lls','evidence_20260913','scheduled_ul_dai_03', ...
    'scheduled_ul_dai_0.mat'),'fixed');
[grant,current]=localInstallCurrentULControl(cfg,retained.fixed);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),3);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
absent=struct('ReportConfigID',"",'ConfigurationEpoch',NaN);
[context,mapping]=sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    state,current,grant,"declared_empty_ul_observation",absent);
budget=context.bitBudget();
assert(isempty(mapping) && context.Data.HARQACKBitCount==0 && ...
    context.Data.HARQMappingDigest=="" && budget.OACK==0 && ...
    budget.OCSI1==0 && budget.OCSI2==0 && isempty(owner.DataTransmissions));
poisoned=state;
poisoned.SharedUEHARQACKEvents={struct('Ack',true,'Bits',ones(99,1))};
poisoned.PendingFeedbackTable=table(true,'VariableNames',{'Ack'});
poison=grant; poison.ExpectedUCIBits=ones(99,1,'int8');
same=sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    poisoned,current,poison,"declared_empty_ul_observation",absent);
assert(isequaln(same,context));
bad=grant; bad.UEIndex=state.NumUsers+1;
localReject(@()sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    state,current,bad,"declared_empty_ul_observation",absent), ...
    'sixgr:truth:HARQMappingUEIdentityMismatch');
localReject(@()sixgr.truth.scheduledHARQExpectationsForOccasion( ...
    state,state.NumUsers+1,grant.TimingDecision.DataAbsoluteSlot+1), ...
    'sixgr:truth:HARQMappingUEIdentityMismatch');
bad=grant; bad.RNTI=grant.RNTI+1;
localReject(@()sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    state,current,bad,"declared_empty_ul_observation",absent), ...
    'sixgr:truth:HARQMappingUEIdentityMismatch');
% On-wire 11 also represents four and eight assignments. A modulo value
% alone must never erase their retained gNB scheduling obligation.
for n=[1 4 8]
    nonempty=load(fullfile('docs','lls','evidence_20260913','scheduled_ul_dai_03', ...
        sprintf('scheduled_ul_dai_%d.mat',n)),'fixed');
    [otherGrant,other]=localInstallCurrentULControl(cfg,nonempty.fixed);
    localReject(@()sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
        state,other,otherGrant,"declared_empty_ul_observation",absent), ...
        'sixgr:truth:NonemptyScheduledPUSCHHARQAuthority');
end

bad=grant; bad.ULTotalDAIAuthority.Digest="changed";
localReject(@()sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    state,current,bad,"declared_empty_ul_observation",absent), ...
    'sixgr:truth:NonemptyScheduledPUSCHHARQAuthority');
badCSI=absent; badCSI.ExpectedPayloadBits=int8([1;0]);
localReject(@()sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    state,current,grant,"declared_empty_ul_observation",badCSI), ...
    'sixgr:truth:InvalidScheduledPUSCHCSIObligation');
request=struct('ReportConfigID',"declared_empty_harq_csi",'Epoch',0, ...
    'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',1,'MaxRank',2, ...
    'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',1, ...
    'ReportQuantity',"cri-RI-LI-PMI-CQI",'NumCSIResources',3, ...
    'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
schema=sixgr.phy.mimo.CSIReportConfiguration(request,0);
csi=struct('ReportConfigID',schema.ReportConfigID,'ConfigurationEpoch',schema.Epoch);
[withCSI,mapping]=sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    state,current,grant,"declared_empty_ul_observation",csi,schema);
budget=withCSI.bitBudget(schema);
assert(isempty(mapping) && budget.OACK==0 && budget.OCSI1==schema.part1BitCount() && ...
    budget.OCSI2==0 && numel(schema.part2BitCountCandidates())==2);
localReject(@()sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    state,current,grant,"declared_empty_ul_observation",csi), ...
    'sixgr:pusch:MissingCSIReportConfiguration');
request.Epoch=1; stale=sixgr.phy.mimo.CSIReportConfiguration(request,1);
localReject(@()sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    state,current,grant,"declared_empty_ul_observation",csi,stale), ...
    'sixgr:pusch:CSIReceiveConfigurationMismatch');
assert(isempty(owner.DataTransmissions) && state.DLHarq.Stats.Tx==0 && ...
    state.DLHarq.Stats.Ack==0 && state.DLHarq.Stats.Nack==0);
end

function [grant,current]=localInstallCurrentULControl(cfg,grant)
% The archived grants retain physical allocation and DAI-ledger evidence.
% Re-encode their control fields using the currently installed context,
% exactly as production does before PDCCH waveform preparation.
current=sixgr.phy.grid.applyRuntimeCarrierTimeline( ...
    cfg,double(grant.TimingDecision.ControlAbsoluteSlot)+1);
scheduler=sixgr.l2.mac.SchedulerPF(current,'Direction','UL');
grant.TPMI=grant.PHYGrant.PrecodingState.TPMI;
grant.DCI=scheduler.buildDCIBitfield(grant);
a=grant.ULTotalDAIAuthority;
ledger=struct('Version',1,'LastControlAbsoluteSlot',a.ControlAbsoluteSlot, ...
    'Entries',a.ScheduledDLAssignments);
grant=sixgr.truth.prepareScheduledULDAI(ledger,current,grant);
end

function base=localBase(grant)
a=grant.ULTotalDAIAuthority;
rows=struct([]);
for entry=reshape(a.ScheduledDLAssignments,1,[])
    d=entry.Assignment; k=entry.Ordinal;
    r=struct('BitIndex',k,'TransmissionID',"declared_tx_"+k, ...
        'PHYGrantContextId',d.GrantID,'UEIndex',grant.UEIndex,'RNTI',grant.RNTI, ...
        'HARQProcess',k-1,'NDI',1,'SourceSlot',d.ControlAbsoluteSlot+1, ...
        'TargetSlot',d.FeedbackAbsoluteSlot+1,'ConfigurationEpoch',d.ConfigurationEpoch, ...
        'ControlAbsoluteSlot',d.ControlAbsoluteSlot,'ControlStartSymbol',d.ControlStartSymbol, ...
        'CounterDAIRaw',entry.RawDAI);
    if isempty(rows), rows=r; else, rows(end+1)=r; end %#ok<AGROW>
end
base=struct('Records',rows,'BitCount',numel(rows),'UEIndex',grant.UEIndex, ...
    'RNTI',grant.RNTI,'TargetSlot',a.PUSCHAbsoluteSlot+1, ...
    'ConfigurationEpoch',a.ConfigurationEpoch,'ContextDigest',"declared_dl_context", ...
    'LastGrant',struct('ServingCell',grant.ServingCell), ...
    'Source',"physically_transmitted_dl_schedule_not_ue_feedback_state");
base=localHash(base);
end

function base=localHash(base)
fields={'LastGrant'};
if isfield(base,'Digest'), fields{end+1}='Digest'; end
base.Digest=sixgr.phy.pucch.PUCCHUtil.hash(rmfield(base,fields));
end

function localReject(action,id)
try
    action();
catch err
    assert(strcmp(err.identifier,id),'Expected %s; received %s: %s',id,err.identifier,err.message);
    return;
end
error('test:ExpectedRejection','Expected %s',id);
end
