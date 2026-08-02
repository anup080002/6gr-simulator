function contract = resolveGrantSpatialContract(grant, varargin)
%RESOLVEGRANTSPATIALCONTRACT Resolve and validate executable grant layers.
% Keep this file ASCII-only.

ip = inputParser;
ip.addParameter("Direction", "", @(x) ischar(x) || isstring(x));
ip.addParameter("TBContext", struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter("RequireTBContextMatch", false, @(x) islogical(x) || isnumeric(x));
ip.parse(varargin{:});
opt = ip.Results;

if nargin < 1 || ~(isstruct(grant) && isscalar(grant))
    error("sixgr:phy:grant:BadSpatialGrant", ...
        "Grant spatial-contract resolution requires one scalar grant struct.");
end

direction = upper(strtrim(string(opt.Direction)));
if strlength(direction) == 0
    direction = upper(strtrim(string(sixgr.util.structGet(grant, "Direction", ""))));
end

names = ["NumLayers", "Layers", "PHYGrant.CodingLayout.NumLayers", ...
    "PHYGrant.AntennaArchitecture.NumLayers"];
values = nan(size(names));
for i = 1:numel(names)
    values(i) = localPositiveIntegerOrNaN(sixgr.util.structGet(grant, names(i), NaN));
end

present = isfinite(values);
if ~any(present)
    error("sixgr:phy:grant:MissingGrantSpatialContract", ...
        "%s grant has no executable layer count in NumLayers, Layers, or its frozen PHYGrant.", ...
        char(localDirectionLabel(direction)));
end

authoritativeIndex = find(present, 1, "first");
numLayers = values(authoritativeIndex);
if any(values(present) ~= numLayers)
    error("sixgr:phy:grant:GrantSpatialAliasMismatch", ...
        "%s grant spatial aliases disagree: %s. Finalized grants must carry one exact executable layer count.", ...
        char(localDirectionLabel(direction)), char(localValueSummary(names, values)));
end

tbContext = opt.TBContext;
if isempty(tbContext)
    tbContext = struct();
end
tbLayers = localPositiveIntegerOrNaN(sixgr.util.structGet(tbContext, "OriginalNumLayers", NaN));
requireTBContextMatch = logical(opt.RequireTBContextMatch);
if requireTBContextMatch && ~isfinite(tbLayers)
    error("sixgr:phy:grant:MissingHARQSpatialContract", ...
        "%s retransmission has no HARQ OriginalNumLayers value.", ...
        char(localDirectionLabel(direction)));
end
if requireTBContextMatch && tbLayers ~= numLayers
    error("sixgr:phy:grant:HARQSpatialContractMismatch", ...
        "%s retransmission grant layers=%d but its immutable HARQ TB context layers=%d.", ...
        char(localDirectionLabel(direction)), round(numLayers), round(tbLayers));
end

contract = struct( ...
    "ContractVersion", "GrantSpatialContract/v1", ...
    "Direction", char(direction), ...
    "NumLayers", double(numLayers), ...
    "Authority", char(names(authoritativeIndex)), ...
    "AliasSummary", char(localValueSummary(names, values)), ...
    "TBContextNumLayers", double(tbLayers), ...
    "TBContextRequired", logical(requireTBContextMatch), ...
    "ExactMatch", logical(~requireTBContextMatch || tbLayers == numLayers));
end

function value = localPositiveIntegerOrNaN(candidate)
value = NaN;
if isempty(candidate) || ~(isnumeric(candidate) || islogical(candidate))
    return;
end
candidate = double(candidate(:));
candidate = candidate(isfinite(candidate));
if isempty(candidate)
    return;
end
if numel(candidate) ~= 1 || candidate < 1 || candidate ~= round(candidate)
    error("sixgr:phy:grant:BadGrantSpatialValue", ...
        "Grant layer aliases must be positive integer scalars.");
end
value = double(candidate);
end

function token = localValueSummary(names, values)
parts = strings(0, 1);
for i = 1:numel(names)
    if isfinite(values(i))
        parts(end + 1, 1) = names(i) + "=" + string(round(values(i))); %#ok<AGROW>
    end
end
token = strjoin(parts, ", ");
end

function label = localDirectionLabel(direction)
if strlength(direction) == 0
    label = "PHY";
else
    label = direction;
end
end
