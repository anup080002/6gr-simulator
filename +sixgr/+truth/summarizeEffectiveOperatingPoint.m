function summary = summarizeEffectiveOperatingPoint(scfg, dlTrials, ulTrials)
%SUMMARIZEEFFECTIVEOPERATINGPOINT Separate nominal config from effective runtime-selected operating points.

if nargin < 2 || ~istable(dlTrials)
    dlTrials = table();
end
if nargin < 3 || ~istable(ulTrials)
    ulTrials = table();
end

s = localResolvedStruct(scfg);
configured = localConfiguredView(s);
radio = localRadioView(s);

summary = struct();
summary.Configured = configured;
summary.Radio = radio;
summary.DL = localDirectionView("DL", dlTrials, configured.DL);
summary.UL = localDirectionView("UL", ulTrials, configured.UL);
summary.RuntimeNarrative = localRuntimeNarrative(summary);
summary.RuntimeQualifiedDescription = localRuntimeQualifiedDescription(s, summary);
end

function s = localResolvedStruct(scfg)
if isa(scfg, "sixgr.lls6g.config.ScenarioConfig")
    s = scfg.toStruct();
else
    s = scfg;
end
end

function configured = localConfiguredView(s)
txAnt = double(sixgr.util.structGet(s, "mimo.n_tx_ant", NaN));
rxAnt = double(sixgr.util.structGet(s, "mimo.n_rx_ant", NaN));
layers = double(sixgr.util.structGet(s, "mimo.n_layers", NaN));

configured = struct();
configured.TxAntennas = txAnt;
configured.RxAntennas = rxAnt;
configured.Layers = layers;
configured.MIMOText = localMIMOText(txAnt, rxAnt, layers);
configured.DL = localConfiguredDirection(s, "DL", layers);
configured.UL = localConfiguredDirection(s, "UL", layers);
end

function direction = localConfiguredDirection(s, dirName, layers)
dirName = upper(string(dirName));
direction = struct();
direction.Direction = dirName;
direction.Layers = double(layers);
direction.Rank = double(layers);
if dirName == "DL"
    direction.MCS = localFirstFiniteNumericScalar(sixgr.util.structGet(s, "modulation.dl_mcs_index", ...
        sixgr.util.structGet(s, "pdsch.mcs_index", NaN)));
    direction.Modulation = localConfiguredModulation(s, ...
        ["modulation.dl_modulation_order", "pdsch.modulation", "modulation_and_mapping.pdsch_modulation"]);
else
    direction.MCS = localFirstFiniteNumericScalar(sixgr.util.structGet(s, "modulation.ul_mcs_index", ...
        sixgr.util.structGet(s, "pusch.mcs_index", NaN)));
    direction.Modulation = localConfiguredULModulation(s);
end
direction.OperatingPointText = localConfiguredOperatingPointText(direction);
end

function value = localFirstFiniteNumericScalar(valueIn)
value = NaN;
raw = double(valueIn);
if isempty(raw)
    return;
end
raw = raw(:);
idx = find(isfinite(raw), 1, "first");
if ~isempty(idx)
    value = double(raw(idx));
end
end

function modText = localConfiguredModulation(s, paths)
modText = "";
for i = 1:numel(paths)
    value = sixgr.util.structGet(s, paths(i), []);
    if isempty(value)
        continue;
    end
    if isnumeric(value)
        modText = localOrderToModulation(value);
    else
        modText = string(value);
    end
    modText = strtrim(modText);
    if strlength(modText) > 0
        return;
    end
end
end

function modText = localConfiguredULModulation(s)
modText = localConfiguredModulation(s, ...
    ["modulation.ul_modulation_order", "pusch.modulation", "modulation_and_mapping.pusch_modulation"]);
if localUsePi2BPSKULMode(s)
    modText = "pi/2-BPSK";
end
end

function radio = localRadioView(s)
configuredGrid = double(sixgr.util.structGet(s, "resource_grid.num_rbs", NaN));
carrierGrid = double(sixgr.util.structGet(s, "frequency.n_size_grid", NaN));
activeMode = lower(string(sixgr.util.structGet(s, "bandwidth_operation.active_bandwidth_mode", "fullband")));
supportsPartial = logical(sixgr.util.structGet(s, "bandwidth_operation.supports_partial_band_activation", false));

activeGrid = configuredGrid;
activeSource = "resource_grid.num_rbs";
if (~supportsPartial || activeMode == "fullband") && isfinite(carrierGrid)
    activeGrid = carrierGrid;
    activeSource = "frequency.n_size_grid";
elseif isfinite(configuredGrid)
    activeGrid = configuredGrid;
elseif isfinite(carrierGrid)
    activeGrid = carrierGrid;
    activeSource = "frequency.n_size_grid";
end

duplex = upper(strtrim(string(sixgr.util.structGet(s, "frequency.duplex_mode", ...
    sixgr.util.structGet(s, "global_radio_scope.duplex_mode", "")))));
configuredPattern = string(sixgr.util.structGet(s, "frame.tdd_pattern", ...
    sixgr.util.structGet(s, "frame_timing.tdd_pattern", "")));
patternApplicable = duplex == "TDD";
activePattern = configuredPattern;
if ~patternApplicable
    activePattern = "not_applicable";
end

radio = struct();
radio.ConfiguredGridNumRBs = configuredGrid;
radio.CarrierGridNumRBs = carrierGrid;
radio.ActiveGridNumRBs = activeGrid;
radio.ActiveGridSource = activeSource;
radio.ActiveBandwidthMode = activeMode;
radio.SupportsPartialBandwidthActivation = supportsPartial;
radio.ActiveDuplexMode = duplex;
radio.ConfiguredTDDPattern = configuredPattern;
radio.TDDPatternApplicable = patternApplicable;
radio.ActiveTDDPattern = activePattern;
end

function direction = localDirectionView(dirName, trialT, configured)
dirName = upper(string(dirName));
direction = struct();
direction.Direction = dirName;
direction.SampleCount = 0;
direction.LayerHistogram = "";
direction.RankHistogram = "";
direction.RecommendedRIHistogram = "";
direction.ModulationHistogram = "";
direction.MCSHistogram = "";
direction.DominantLayer = NaN;
direction.DominantRank = NaN;
direction.DominantRecommendedRI = NaN;
direction.DominantModulation = "";
direction.DominantMCS = NaN;
direction.DominantOperatingPointText = "";
direction.ConfiguredMatchCount = NaN;
direction.ConfiguredMatchRate = NaN;
direction.Narrative = "No runtime-selected samples were emitted.";
direction.HasSamples = false;

Te = localEffectiveTrialRows(trialT);
if isempty(Te)
    return;
end

direction.SampleCount = height(Te);
direction.HasSamples = true;

layers = localFiniteNumericVector(Te, "Layers");
rank = localActualRankVector(Te);
recommendedRI = localFiniteNumericVector(Te, "RankIndicator");
mods = localEffectiveStringVector(Te, "Modulation");
mcs = localFiniteNumericVector(Te, "MCS");

[direction.LayerHistogram, direction.DominantLayer] = localNumericHistogramSummary(layers);
[direction.RankHistogram, direction.DominantRank] = localNumericHistogramSummary(rank);
[direction.RecommendedRIHistogram, direction.DominantRecommendedRI] = localNumericHistogramSummary(recommendedRI);
[direction.ModulationHistogram, direction.DominantModulation] = localStringHistogramSummary(mods);
[direction.MCSHistogram, direction.DominantMCS] = localNumericHistogramSummary(mcs);

[direction.DominantOperatingPointText, dominantCount] = localDominantOperatingPointText(Te);
[direction.ConfiguredMatchCount, direction.ConfiguredMatchRate] = localConfiguredMatchStats(Te, configured);
direction.Narrative = localDirectionNarrative(direction, configured, dominantCount);
end

function T = localEffectiveTrialRows(T)
if ~(istable(T) && ~isempty(T))
    T = table();
    return;
end
mask = true(height(T), 1);
if ismember("IsWarmupFrame", string(T.Properties.VariableNames))
    warmMask = logical(T.IsWarmupFrame);
    if any(~warmMask)
        mask = ~warmMask;
    end
end
T = T(mask, :);
end

function values = localFiniteNumericVector(T, varName)
values = [];
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
values = double(T.(varName));
values = values(isfinite(values));
end

function values = localActualRankVector(T)
values = localFiniteNumericVector(T, "Layers");
if ~isempty(values)
    return;
end
values = localFiniteNumericVector(T, "RankIndicator");
end

function values = localEffectiveStringVector(T, varName)
values = strings(0, 1);
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
values = string(T.(varName));
values = strtrim(values(:));
values = values(strlength(values) > 0);
end

function [histText, dominantValue] = localNumericHistogramSummary(values)
histText = "";
dominantValue = NaN;
if isempty(values)
    return;
end
[uVals, ~, idx] = unique(values(:));
counts = accumarray(idx, 1);
rows = [(1:numel(uVals)).' counts];
sortKey = [ -counts(:) double(uVals(:)) ];
[~, order] = sortrows(sortKey, [1 2]);
uVals = uVals(order);
counts = counts(order);
parts = strings(numel(uVals), 1);
for i = 1:numel(uVals)
    parts(i) = string(localFormatNumericToken(uVals(i))) + ":" + string(counts(i));
end
histText = strjoin(parts, "|");
dominantValue = uVals(1);
end

function [histText, dominantValue] = localStringHistogramSummary(values)
histText = "";
dominantValue = "";
if isempty(values)
    return;
end
values = string(values(:));
[uVals, ~, idx] = unique(values);
counts = accumarray(idx, 1);
sortKey = [ -counts(:) double((1:numel(uVals)).') ];
[~, order] = sortrows(sortKey, [1 2]);
uVals = uVals(order);
counts = counts(order);
parts = strings(numel(uVals), 1);
for i = 1:numel(uVals)
    parts(i) = uVals(i) + ":" + string(counts(i));
end
histText = strjoin(parts, "|");
dominantValue = uVals(1);
end

function token = localFormatNumericToken(value)
if ~isfinite(value)
    token = "nan";
elseif abs(value - round(value)) < 1e-12
    token = string(round(value));
else
    token = string(value);
end
end

function [textOut, dominantCount] = localDominantOperatingPointText(T)
textOut = "";
dominantCount = 0;
if ~(istable(T) && ~isempty(T))
    return;
end

layers = localColumnNumericWithNaN(T, "Layers");
rank = layers;
fallbackRank = localColumnNumericWithNaN(T, "RankIndicator");
rank(~isfinite(rank)) = fallbackRank(~isfinite(rank));
mods = localColumnStringWithEmpty(T, "Modulation");
mcs = localColumnNumericWithNaN(T, "MCS");

combo = strings(height(T), 1);
for i = 1:height(T)
    combo(i) = "layer=" + localFormatNumericToken(layers(i)) + ...
        ", rank=" + localFormatNumericToken(rank(i)) + ...
        ", modulation=" + localDisplayStringToken(mods(i)) + ...
        ", mcs=" + localFormatNumericToken(mcs(i));
end
combo = combo(strlength(combo) > 0);
if isempty(combo)
    return;
end
[uVals, ~, idx] = unique(combo);
counts = accumarray(idx, 1);
[dominantCount, orderIdx] = max(counts);
textOut = uVals(orderIdx) + " (" + string(dominantCount) + "/" + string(numel(combo)) + ")";
end

function values = localColumnNumericWithNaN(T, varName)
values = NaN(height(T), 1);
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
values = double(T.(varName));
end

function values = localColumnStringWithEmpty(T, varName)
values = repmat("", height(T), 1);
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
values = strtrim(string(T.(varName)));
end

function token = localDisplayStringToken(value)
token = string(value);
if strlength(token) == 0
    token = "unknown";
end
end

function [matchCount, matchRate] = localConfiguredMatchStats(T, configured)
matchCount = NaN;
matchRate = NaN;
if ~(istable(T) && ~isempty(T))
    return;
end

mask = true(height(T), 1);
compared = false;

if isfinite(double(configured.Layers)) && ismember("Layers", string(T.Properties.VariableNames))
    vals = double(T.Layers);
    valid = isfinite(vals);
    if any(valid)
        mask(valid) = mask(valid) & vals(valid) == double(configured.Layers);
        compared = true;
    end
end
if isfinite(double(configured.Rank))
    rank = localColumnNumericWithNaN(T, "Layers");
    fallbackRank = localColumnNumericWithNaN(T, "RankIndicator");
    rank(~isfinite(rank)) = fallbackRank(~isfinite(rank));
    if any(isfinite(rank))
        valid = isfinite(rank);
        mask(valid) = mask(valid) & rank(valid) == double(configured.Rank);
        compared = true;
    end
end
if strlength(string(configured.Modulation)) > 0 && ismember("Modulation", string(T.Properties.VariableNames))
    vals = strtrim(string(T.Modulation));
    valid = strlength(vals) > 0;
    if any(valid)
        mask(valid) = mask(valid) & vals(valid) == string(configured.Modulation);
        compared = true;
    end
end
if isfinite(double(configured.MCS)) && ismember("MCS", string(T.Properties.VariableNames))
    vals = double(T.MCS);
    valid = isfinite(vals);
    if any(valid)
        mask(valid) = mask(valid) & vals(valid) == double(configured.MCS);
        compared = true;
    end
end

if ~compared
    return;
end
matchCount = sum(mask);
matchRate = matchCount / max(height(T), 1);
end

function note = localDirectionNarrative(direction, configured, dominantCount)
if ~direction.HasSamples
    note = "No runtime-selected samples were emitted.";
    return;
end

configuredItems = strings(0, 1);
if isfinite(direction.DominantLayer) && isfinite(double(configured.Layers)) && direction.DominantLayer ~= double(configured.Layers)
    configuredItems(end+1, 1) = "dominant layer " + string(localFormatNumericToken(direction.DominantLayer)) + ...
        " vs configured " + string(localFormatNumericToken(configured.Layers)); %#ok<AGROW>
end
if isfinite(direction.DominantRank) && isfinite(double(configured.Rank)) && direction.DominantRank ~= double(configured.Rank)
    configuredItems(end+1, 1) = "dominant rank " + string(localFormatNumericToken(direction.DominantRank)) + ...
        " vs configured " + string(localFormatNumericToken(configured.Rank)); %#ok<AGROW>
end
if isfinite(direction.DominantRecommendedRI) && isfinite(direction.DominantRank) && ...
        direction.DominantRecommendedRI ~= direction.DominantRank
    configuredItems(end+1, 1) = "dominant recommended RI " + ...
        string(localFormatNumericToken(direction.DominantRecommendedRI)) + ...
        " while transmitted rank remained " + string(localFormatNumericToken(direction.DominantRank)); %#ok<AGROW>
end
if strlength(direction.DominantModulation) > 0 && strlength(string(configured.Modulation)) > 0 && ...
        direction.DominantModulation ~= string(configured.Modulation)
    configuredItems(end+1, 1) = "dominant modulation " + direction.DominantModulation + ...
        " vs configured " + string(configured.Modulation); %#ok<AGROW>
end
if isfinite(direction.DominantMCS) && isfinite(double(configured.MCS)) && direction.DominantMCS ~= double(configured.MCS)
    configuredItems(end+1, 1) = "dominant MCS " + string(localFormatNumericToken(direction.DominantMCS)) + ...
        " vs configured " + string(localFormatNumericToken(configured.MCS)); %#ok<AGROW>
end

configuredMatch = "";
if isfinite(direction.ConfiguredMatchCount) && isfinite(direction.ConfiguredMatchRate)
    configuredMatch = " Exact configured-match rate: " + string(direction.ConfiguredMatchCount) + ...
        "/" + string(direction.SampleCount) + " (" + string(sprintf('%.1f', 100 * direction.ConfiguredMatchRate)) + "%).";
end

if isempty(configuredItems)
    note = "Runtime-selected operating point matched the configured nominal operating point across observed trials." + configuredMatch;
    return;
end

note = "Runtime-selected operating point diverged from the configured nominal operating point. Dominant effective point: " + ...
    direction.DominantOperatingPointText + ". Divergence: " + strjoin(configuredItems, "; ") + "." + configuredMatch;
if dominantCount <= 0
    note = "Runtime-selected operating point diverged from the configured nominal operating point." + configuredMatch;
end
end

function note = localRuntimeNarrative(summary)
parts = strings(0, 1);
if summary.DL.HasSamples
    parts(end+1, 1) = "DL: " + summary.DL.Narrative; %#ok<AGROW>
end
if summary.UL.HasSamples
    parts(end+1, 1) = "UL: " + summary.UL.Narrative; %#ok<AGROW>
end
if isempty(parts)
    note = "No runtime-selected operating-point samples were available.";
else
    note = strjoin(parts, " ");
end
end

function txt = localRuntimeQualifiedDescription(s, summary)
txt = strtrim(string(sixgr.util.structGet(s, "meta.description", ...
    sixgr.util.structGet(s, "meta.scenario_name", ""))));
if strlength(txt) == 0
    txt = "unspecified scenario";
end

clauses = strings(0, 1);
if summary.DL.HasSamples
    clauses(end+1, 1) = localRuntimeDescriptionClause(summary.DL); %#ok<AGROW>
end
if summary.UL.HasSamples
    clauses(end+1, 1) = localRuntimeDescriptionClause(summary.UL); %#ok<AGROW>
end

if isempty(clauses)
    txt = txt + " (configured intent only; no runtime-selected operating-point samples were emitted)";
else
    txt = txt + " (configured intent; " + strjoin(clauses, "; ") + ")";
end
end

function txt = localRuntimeDescriptionClause(direction)
prefix = string(direction.Direction) + " ";
if ~(direction.HasSamples && strlength(string(direction.DominantOperatingPointText)) > 0)
    txt = prefix + "runtime-selected operating point unavailable";
    return;
end

if isfinite(direction.ConfiguredMatchRate) && direction.ConfiguredMatchRate >= 0.999
    txt = prefix + "matched the nominal operating point";
    return;
end

txt = prefix + "dominant effective point " + string(direction.DominantOperatingPointText);
if isfinite(direction.ConfiguredMatchRate)
    txt = txt + ", configured-match rate " + string(sprintf('%.1f', 100 * direction.ConfiguredMatchRate)) + "%";
end
end

function txt = localConfiguredOperatingPointText(direction)
txt = "layers=" + localFormatNumericToken(direction.Layers) + ...
    ", rank=" + localFormatNumericToken(direction.Rank) + ...
    ", modulation=" + localDisplayStringToken(direction.Modulation) + ...
    ", mcs=" + localFormatNumericToken(direction.MCS);
end

function txt = localMIMOText(txAnt, rxAnt, layers)
txt = localFormatNumericToken(txAnt) + "x" + localFormatNumericToken(rxAnt) + ...
    " nominal rank-" + localFormatNumericToken(layers);
end

function modStr = localOrderToModulation(order)
modStr = "";
targetOrder = round(double(order));
if ~isfinite(targetOrder)
    return;
end
catalog = sixgr.lls6g.config.loadParameterCatalog("scenario");
entries = sixgr.util.structGet(catalog, "value_maps.modulation_order_to_name", struct([]));
for i = 1:numel(entries)
    if round(double(entries(i).order)) == targetOrder
        modStr = string(entries(i).name);
        return;
    end
end
end

function tf = localUsePi2BPSKULMode(s)
tf = logical(sixgr.util.structGet(s, "modulation.pi2_bpsk_enabled", false)) && ...
    logical(sixgr.util.structGet(s, "waveform.transform_precoding_enabled", false)) && ...
    upper(string(sixgr.util.structGet(s, "waveform.ul_waveform", ""))) == "DFT-S-OFDM" && ...
    round(double(sixgr.util.structGet(s, "modulation.ul_modulation_order", NaN))) == 1;
end
