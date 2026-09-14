function ok=testPUSCHScheduledHARQAuthority()
% Retained UL DCI plus DECLARED DL identity fixtures, not physical mapping proof.
% The mock base has the production schema to test the binding contract only;
% it is never exported as actual scheduling, grant, receiver or PHY evidence.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_received_ul_harq_shared_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cases=0;
for n=1:8
    retained=load(fullfile('docs','lls','evidence_20260913','scheduled_ul_dai_03', ...
        sprintf('scheduled_ul_dai_%d.mat',n)),'fixed');
    grant=retained.fixed;
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,grant.ControlAbsoluteSlot+1);
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
