function [report,overlap]=buildPUCCHSRWireIndicator(calendar,slot,resource,priority,states,selectedID,windows)
% Configured overlap owns the width. UE procedure snapshots own the value.
% A missing snapshot is not a negative SR. No receiver result enters here.
if nargin<6, selectedID=[]; end
assert(isa(resource,'sixgr.phy.pucch.PUCCHResource') && isscalar(resource));
if nargin<7, windows=[resource.Data.StartSymbol resource.Data.NumSymbols]; end
if ~isempty(selectedID)
    validateattributes(selectedID,{'numeric'},{'scalar','real','finite','integer','positive'});
end
format=resource.Format;
% Count overlap independently of pending-positive state. Short-format SR
% mapping is separate from the compact long-format resource indicator.
overlap=sixgr.truth.resolveConfiguredSROverlap(calendar,slot,windows,priority);
report=struct([]);
if overlap.OpportunityCount==0
    assert(isempty(selectedID),'sixgr:truth:InvalidSRSelection','No SR can be selected without an overlapping occasion.');
    return;
end
assert(isa(states,'sixgr.phy.pucch.SchedulingRequestState') && ~isempty(states), ...
    'sixgr:truth:MissingSRProcedureState','Every configured overlapping SR requires explicit UE procedure state, including negative SR.');
data=arrayfun(@(s)s.Data,states);
required={'SRResourceConfigurationID','SchedulingRequestID','UEIndex','RNTI','ServingCell', ...
    'ComponentCarrier','ActiveULBWP','ConfigurationEpoch','AbsoluteSlot','PeriodSlots','OffsetSlots','Priority'};
assert(all(isfield(data,required)) && numel(unique([data.SRResourceConfigurationID]))==numel(data), ...
    'sixgr:truth:InvalidSRProcedureIdentity','SR snapshots need unique resource identities and installed UE/BWP/epoch binding.');
positive=false(overlap.OpportunityCount,1); digests=strings(overlap.OpportunityCount,1);
for k=1:overlap.OpportunityCount
    row=calendar(calendar.SRResourceConfigurationID==overlap.SRResourceConfigurationIDs(k) & calendar.Slot==slot,:);
    index=find([data.SRResourceConfigurationID]==row.SRResourceConfigurationID);
    assert(isscalar(index),'sixgr:truth:MissingSRProcedureState','Missing explicit procedure state for a configured SR opportunity.');
    d=data(index);
    for pair={ {'SchedulingRequestID','SchedulingRequestID'}, {'UEIndex','UEIndex'}, {'RNTI','RNTI'}, ...
            {'ServingCell','ServingCell'}, {'ComponentCarrier','ComponentCarrier'}, {'ActiveULBWP','ActiveULBWP'}, ...
            {'ConfigurationEpoch','PUCCHConfigurationEpoch'}, {'PeriodSlots','PeriodSlots'}, ...
            {'OffsetSlots','OffsetSlots'}, {'Priority','PriorityIndex'} }
        names=pair{1};
        assert(isequal(d.(names{1}),row.(names{2})), ...
            'sixgr:truth:SRProcedureConfigurationMismatch','SR procedure field %s differs from installed occasion.',names{1});
    end
    assert(d.AbsoluteSlot==slot-1 && d.IsOccasion, ...
        'sixgr:truth:StaleSRProcedureState','Bind SR state to this exact transmission occasion.');
    positive(k)=d.Transmit; digests(k)=states(index).Digest;
end
chosen=find(positive);
if ~isempty(selectedID)
    chosen=find(overlap.SRResourceConfigurationIDs==selectedID & positive);
    assert(isscalar(chosen),'sixgr:truth:InvalidSRSelection','The selected SR must be an eligible positive request.');
elseif numel(chosen)>1
    error('sixgr:truth:UnresolvedPositiveSRSelection','Multiple eligible positive SRs require an explicit MAC-selected resource identity.');
end
ordinal=0; if ~isempty(chosen), ordinal=chosen; end
if format<=1
    assert(overlap.OpportunityCount==1,'sixgr:truth:UnresolvedShortFormatSRArbitration', ...
        'Multiple SR opportunities require the short-format resource arbitration procedure.');
    if format==1
        assert(ordinal==0,'sixgr:truth:UnresolvedFormat1SRResource', ...
            'Positive SR/Format-1 arbitration needs its configured resource procedure.');
        return; % Negative SR leaves Format-1 HARQ modulation unchanged.
    end
    bits=int8(ordinal>0); % Format 0 carries SR in its cyclic-shift interpretation.
else
    bits=int8(bitget(uint32(ordinal),overlap.EncodedBitCount:-1:1)).';
end
report=struct('Bits',bits,'SRResourceConfigurationIDs',overlap.SRResourceConfigurationIDs, ...
    'SelectedSRResourceConfigurationID',NaN,'ProcedureStateDigests',digests, ...
    'Source',"configured_overlap_and_explicit_UE_SR_procedure_state");
if ordinal>0, report.SelectedSRResourceConfigurationID=overlap.SRResourceConfigurationIDs(ordinal); end
end
