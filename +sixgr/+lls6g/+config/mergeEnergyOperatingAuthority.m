function authority=mergeEnergyOperatingAuthority(authority,authored)
% Preserve last-document authorship of each semantic energy-policy pair.
% Setting one alias in a child replaces inherited authority of BOTH aliases.
% If a document authors both, retain both for explicit conflict validation.
pairs={ ...
    ["energy_and_complexity.sleep_state_model","energy_efficiency.sleep_state_model"], ...
    ["energy_and_complexity.race_to_sleep_metrics","energy_efficiency.race_to_sleep_enabled"]};
for k=1:numel(pairs)
    paths=pairs{k}; present=false(1,2); values=cell(1,2);
    for n=1:2
        parts=split(paths(n),'.');
        present(n)=isfield(authored,parts(1)) && isfield(authored.(parts(1)),parts(2));
        if present(n), values{n}=authored.(parts(1)).(parts(2)); end
    end
    if ~any(present), continue; end
    for n=1:2
        parts=split(paths(n),'.');
        if isfield(authority,parts(1)) && isfield(authority.(parts(1)),parts(2))
            authority.(parts(1))=rmfield(authority.(parts(1)),parts(2));
        end
        if present(n), authority=sixgr.util.structSet(authority,paths(n),values{n}); end
    end
end
end
