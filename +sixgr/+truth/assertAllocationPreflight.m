function assertAllocationPreflight(checkT)
%ASSERTALLOCATIONPREFLIGHT Stop before slot zero on unresolved enabled PHY.
if ~istable(checkT)
    error("sixgr:truth:InvalidAllocationPreflight", ...
        "Allocation preflight evidence must be a table.");
end
required = ["feature","enabled","resolved","status","error_id","detail"];
if ~all(ismember(required,string(checkT.Properties.VariableNames)))
    error("sixgr:truth:InvalidAllocationPreflight", ...
        "Allocation preflight table is missing its fail-closed schema.");
end
bad = logical(checkT.enabled) & ~logical(checkT.resolved);
if ~any(bad), return; end
items = strings(nnz(bad),1); rows = find(bad);
for i=1:numel(rows)
    r=rows(i);
    items(i)=string(checkT.feature(r))+" ["+string(checkT.error_id(r))+ ...
        "]: "+string(checkT.detail(r));
end
error("sixgr:truth:EnabledAllocationUnresolved", ...
    "Enabled PHY allocation preflight failed: %s",strjoin(items," | "));
end
