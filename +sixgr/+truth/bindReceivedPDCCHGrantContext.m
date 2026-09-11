function grant=bindReceivedPDCCHGrantContext(grant,row)
%BINDRECEIVEDPDCCHGRANTCONTEXT Keep one coherent received CCE hypothesis.
names=["PDCCHSelectedCCEIndex","AvailableCCECount", ...
    "PDCCHSelectedAggregationLevel","PDCCHSelectedCandidateIndex"];
values=nan(1,4);
if istable(row) && height(row)==1
    for k=1:numel(names)
        if ismember(names(k),string(row.Properties.VariableNames))
            value=row.(names(k));
            if isnumeric(value) && isscalar(value), values(k)=double(value); end
        end
    end
end
first=values(1); capacity=values(2); level=values(3); ordinal=values(4);
if ~all(isfinite(values)) || any(values~=fix(values)) || ...
        first<0 || capacity<1 || ~ismember(level,[1 2 4 8 16]) || ...
        ordinal<0 || first+level>capacity || mod(first,level)~=0
    error('sixgr:truth:MissingDecodedPDCCHCCEContext', ...
        'Received CCE context invalid: first=%g, capacity=%g, AL=%g, candidate=%g. No TX-context substitution is allowed.', ...
        first,capacity,level,ordinal);
end
grant.PDCCHGrantFirstCCE=first;
grant.PDCCHGrantNumCCE=capacity;
grant.PDCCHGrantAggregationLevel=level;
grant.PDCCHGrantCandidateIndex=ordinal;
end
