function [deferred,binding]=resolveSharedReceivedPUCCHPower(state,item,cfg,planned,book)
% Resource planning may precede command arrival; power binding may not.
deferred=false; binding=[];
mode=string(sixgr.util.structGet(cfg,'validation.pucch_resources.power_control.closed_loop_mode','configured'));
if mode=="configured", return; end
assert(mode=="received_dci",'sixgr:truth:PUCCHPowerPolicy','Unknown power mode.');
stream=state.SharedWaveformStream; ue=item.UE;
assert(numel(state.SharedReceivedPUCCHPowerOwners)>=ue && ...
    isa(state.SharedReceivedPUCCHPowerOwners{ue},'sixgr.link.ReceivedPUCCHPowerControlState'), ...
    'sixgr:truth:PUCCHPowerOwnerMissing','TPC owner must predate received monitoring, not be synthesized at TX.');
owner=state.SharedReceivedPUCCHPowerOwners{ue}; b=owner.Installation;
plan=planned.Plan; r=plan.Resource.Data;
c=sixgr.phy.grid.makeCarrier(cfg); L=double(c.SymbolsPerSlot);
assert(L==14 && plan.Data.DueSlot==item.Context.Slot && plan.Data.UEID==ue && ...
    plan.Data.RNTI==b.RNTI && plan.Data.ServingCell==b.ServingCell, ...
    'sixgr:truth:PUCCHPowerOccasion','The selected plan must retain the installed endpoint and registered slot.');
info=nrOFDMInfo(c,'SampleRate',stream.SampleRateHz,'Windowing',0);
offset=mod(double(c.NSlot),double(c.SlotsPerSubframe))*L;
lengths=double(info.SymbolLengths(offset+(1:L)));
timing=item.Context.PhysicalTiming;
first=timing.TransmitStartSample+sum(lengths(1:r.StartSymbol));
last=timing.TransmitStartSample+sum(lengths(1:r.StartSymbol+r.NumSymbols));
now=stream.Events.NextSampleIndex;
assert(first>=now && last<=timing.TransmitEndSampleExclusive, ...
    'sixgr:truth:LateReceivedPUCCHPowerBinding','Never retime or rewrite an already consumed selected symbol.');
if first>now
    stream.deferPUCCHPreparation(item,first,plan.Digest,planned.Report.Digest);
    deferred=true; return;
end
procedure="autonomous_csi"; response="";
if nargin>=5 && isa(book,'sixgr.phy.pucch.HARQACKCodebookState') && ~isempty(book.Events)
    % The same ordered received codebook supplies the PRI/last-row choice in
    % bindReceivedPUCCHCodebookRows. Never choose the last scheduled grant.
    assert(book.CodebookType=="TYPE2_DYNAMIC" && ...
        all(arrayfun(@(e)e.Data.ServingCell==b.DCIServingCellIndex && ...
            e.Data.ServingCellDomain=="configured_serving_cell_index",book.Events)), ...
        'sixgr:truth:PUCCHResponseOwnership','Initial scope is the original single-cell Type-2 resource selector.');
    lastEvent=book.Events(end).Data;
    assert(isfield(lastEvent,'ReceivedAssignmentDigest'), ...
        'sixgr:truth:PUCCHResponseOwnership','Retain the selected-resource received assignment identity.');
    responseDigests=string(lastEvent.ReceivedAssignmentDigest);
    controls=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
    candidates={};
    for k=1:numel(controls)
        ctl=controls{k}; a=ctl.ReceivedAssignment;
        if ~ctl.Allowed || isempty(fieldnames(a)) || string(a.Direction)~="DL", continue; end
        if a.RNTI==b.RNTI && a.HARQFeedbackAbsoluteSlot+1==item.Context.Slot && ...
                string(a.AssignmentDigest)==responseDigests
            candidates{end+1}=a; %#ok<AGROW>
        end
    end
    assert(numel(candidates)==1,'sixgr:truth:PUCCHMultipleResponseDCIs', ...
        'The received resource selector must join exactly one original completed control.');
    response=string(candidates{1}.AssignmentDigest); procedure="dci_response";
elseif isempty(planned.Report.Data.CSIReports)
    procedure="autonomous_sr";
end
o=struct('ObservationID',string(item.Context.ObservationID),'ResourceID',double(plan.Resource.ID), ...
    'ResourceDigest',string(plan.Resource.Digest),'ReportDigest',string(planned.Report.Digest), ...
    'TimingDigest',string(sixgr.util.sha256Hex(char(jsonencode(timing)))), ...
    'UEID',double(ue),'RNTI',b.RNTI,'ServingCell',b.ServingCell,'ComponentCarrier',b.ComponentCarrier, ...
    'ActiveULBWP',b.ActiveULBWP,'ClosedLoopIndex',b.ClosedLoopIndex,'P0PUCCHID',b.P0PUCCHID, ...
    'StartSample',double(first),'EndSampleExclusive',double(last), ...
    'StartSymbolBoundary',double(14*(item.Context.Slot-1)+r.StartSymbol),'DecisionSample',double(now), ...
    'SampleRateHz',stream.SampleRateHz,'ClockEpoch',double(stream.Physical.ConfigurationEpoch), ...
    'SubcarrierSpacingKHz',double(c.SubcarrierSpacing),'RepetitionCount',1, ...
    'Procedure',procedure,'ResponseAssignmentDigest',response);
binding=struct('Owner',owner,'Proposal',owner.resolveOccasion(o));
end
