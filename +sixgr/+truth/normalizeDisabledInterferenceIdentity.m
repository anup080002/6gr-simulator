function T = normalizeDisabledInterferenceIdentity(T, scopeToken)
%NORMALIZEDISABLEDINTERFERENCEIDENTITY Repair only a proved off-path identity.
%
% A historical categorical filler could label InterferencePowerSource as
% active merely because InterferencePowerReferencePlane was populated.
% Correct that auto-generated token only when the same runtime row proves
% the complete disabled identity: disabled mode, zero contributors, no
% finite aggregate interference power and no interferer truth channel.
% Arbitrary nonempty sources remain untouched so reconciliation fails
% closed instead of concealing a contradictory runtime observation.

arguments
    T table
    scopeToken (1,1) string
end

required = ["InterferenceMode", "InterferenceContributorCount", ...
    "InterferenceAggregatedRxPower_dBm", "InterferencePowerSource", ...
    "FullInterfererChannelTruthUsed"];
if isempty(T) || ~all(ismember(required, string(T.Properties.VariableNames)))
    return;
end

mode = lower(strtrim(string(T.InterferenceMode)));
contributors = localNumeric(T.InterferenceContributorCount);
power_dBm = localNumeric(T.InterferenceAggregatedRxPower_dBm);
truthUsed = localLogical(T.FullInterfererChannelTruthUsed);
source = string(T.InterferencePowerSource);
normalizedSource = lower(strtrim(fillmissing(source, "constant", "")));

scope = lower(regexprep(scopeToken, "[^a-z0-9]+", "_"));
disabledSource = "not_emitted_by_active_" + scope + "_runtime";
% The same physical trial rows have two canonical persisted views: the
% live channel table and the fixed-link campaign table.  Older finalizers
% could stamp either view name before copying the row into the other view.
% Treat only those known same-direction aliases as repairable.  Do not
% accept a generic active_* token, because that would conceal a genuinely
% contradictory source identity.
sourceAliases = scope;
if any(scope == ["dl_pdsch_trials", "dl_fixed_link_campaign_trials"])
    sourceAliases = ["dl_pdsch_trials", "dl_fixed_link_campaign_trials"];
elseif any(scope == ["ul_pusch_trials", "ul_fixed_link_campaign_trials"])
    sourceAliases = ["ul_pusch_trials", "ul_fixed_link_campaign_trials"];
end
staleActiveAliases = "active_" + sourceAliases + "_runtime_table";
disabledAliases = "not_emitted_by_active_" + sourceAliases + "_runtime";
disabledMode = mode == "none" | mode == "disabled" | mode == "off" | ...
    mode == "no_interference" | mode == "identity";
provedIdentity = disabledMode & isfinite(contributors) & contributors == 0 & ...
    ~isfinite(power_dBm) & ~truthUsed;
repairableSource = strlength(normalizedSource) == 0 | ...
    ismember(normalizedSource, staleActiveAliases) | ...
    ismember(normalizedSource, disabledAliases);
mask = provedIdentity & repairableSource;
source(mask) = disabledSource;
T.InterferencePowerSource = source;
end

function values = localNumeric(raw)
if isnumeric(raw) || islogical(raw)
    values = double(raw(:));
else
    values = str2double(strtrim(string(raw(:))));
end
end

function values = localLogical(raw)
if islogical(raw)
    values = raw(:);
elseif isnumeric(raw)
    numeric = double(raw(:));
    values = isfinite(numeric) & numeric ~= 0;
else
    token = lower(strtrim(string(raw(:))));
    values = token == "1" | token == "true" | token == "yes" | ...
        token == "pass" | token == "passed";
end
end
