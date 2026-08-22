function [values, specified] = configuredFixedLinkSeedValues(cfg)
%CONFIGUREDFIXEDLINKSEEDVALUES Resolve the YAML-owned campaign seed set.
%
% The fixed-link campaign seed list is stronger authority than a generic
% run-count field. Reducers use this helper to bind persisted drop rows to
% the exact configured seed identities, not only to a minimum count.

paths = [ ...
    "validation.fixed_link_campaign.seeds"
    "validation.fixed_link_campaign.Seeds"
    "lls6g.resolvedConfig.validation.fixed_link_campaign.seeds"
    "lls6g.resolvedConfig.validation.fixed_link_campaign.Seeds"
    ];
values = zeros(0, 1);
specified = false;
for path = paths.'
    [raw, found] = localGet(cfg, path);
    if ~found
        continue;
    end
    specified = true;
    if isnumeric(raw) || islogical(raw)
        values = double(raw(:));
    else
        values = str2double(string(raw(:)));
    end
    break;
end

if ~specified
    return;
end
if isempty(values) || any(~isfinite(values)) || any(values < 0) || ...
        any(values ~= round(values)) || numel(unique(values)) ~= numel(values)
    error("sixgr:analytics:InvalidFixedLinkCampaignSeeds", ...
        "validation.fixed_link_campaign.seeds must contain unique nonnegative integer seed values.");
end
end

function [value, found] = localGet(S, dottedPath)
value = [];
found = false;
if ~isstruct(S) || ~isscalar(S)
    return;
end
cursor = S;
parts = split(string(dottedPath), ".");
for index = 1:numel(parts)
    name = char(parts(index));
    if ~isstruct(cursor) || ~isscalar(cursor) || ~isfield(cursor, name)
        return;
    end
    cursor = cursor.(name);
end
value = cursor;
found = true;
end
