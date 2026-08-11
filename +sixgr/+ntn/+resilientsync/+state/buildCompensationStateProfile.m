function profiles = buildCompensationStateProfile(document, enabledIds)
%BUILDCOMPENSATIONSTATEPROFILE Select immutable YAML-defined state profiles.

if ~isstruct(document) || ~isfield(document, "profiles")
    error("sixgr:ntn:resilientsync:InvalidStateProfileDocument", ...
        "State-profile YAML must contain a profiles sequence.");
end
available = localNormalizeProfiles(document.profiles);
if ~isstruct(available)
    error("sixgr:ntn:resilientsync:InvalidStateProfileDocument", ...
        "state_profiles.profiles must decode to a structure sequence.");
end
enabledIds = string(enabledIds(:));
profiles = repmat(available(1), 0, 1);
for id = enabledIds.'
    index = find(string({available.id}) == id, 1);
    if isempty(index)
        error("sixgr:ntn:resilientsync:UnknownStateProfile", ...
            "Enabled compensation-state profile %s is not defined.", char(id));
    end
    profile = available(index);
    sixgr.ntn.resilientsync.state.validateCompensationStateProfile(profile);
    profiles(end+1,1) = profile; %#ok<AGROW>
end
if numel(unique(string({profiles.id}))) ~= numel(profiles)
    error("sixgr:ntn:resilientsync:DuplicateStateProfile", ...
        "Enabled compensation-state profile IDs must be unique.");
end
end

function profiles = localNormalizeProfiles(raw)
if iscell(raw)
    cells=raw(:);
elseif isstruct(raw)
    cells=num2cell(raw(:));
else
    profiles=raw;
    return;
end
allFields=strings(0,1);
for index=1:numel(cells)
    if ~isstruct(cells{index}) || ~isscalar(cells{index})
        error("sixgr:ntn:resilientsync:InvalidStateProfileDocument", ...
            "Every state profile must decode to a scalar mapping.");
    end
    allFields=unique([allFields;string(fieldnames(cells{index}))],"stable"); %#ok<AGROW>
end
template=cell2struct(cell(numel(allFields),1),cellstr(allFields),1);
profiles=repmat(template,numel(cells),1);
for index=1:numel(cells)
    value=template;
    fields=fieldnames(cells{index});
    for fieldIndex=1:numel(fields)
        value.(fields{fieldIndex})=cells{index}.(fields{fieldIndex});
    end
    profiles(index)=value;
end
end
