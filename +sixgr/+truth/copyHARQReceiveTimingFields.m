function fields=copyHARQReceiveTimingFields(row)
% Lossless ledger projection. Absent evidence remains explicitly unavailable.
fields=sixgr.truth.harqFeedbackReceiveTimingFields(struct(),struct(),false);
% A retained ACK has a protocol availability event, not a new data decode.
fields.HARQProtocolDecisionEvidenceJSON="";
if istable(row)
    assert(height(row)==1,'sixgr:truth:HARQTimingRowRequired','Project one feedback reservation.');
    row=table2struct(row);
end
assert(isstruct(row) && isscalar(row),'sixgr:truth:HARQTimingRowRequired','Project one feedback reservation.');
for name=string(fieldnames(fields)).'
    if isfield(row,name), fields.(name)=row.(name); end
end
end
