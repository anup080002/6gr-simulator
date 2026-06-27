function decision = resolveRankExecutionPolicy(cfg, direction, requestedRank, varargin)
%RESOLVERANKEXECUTIONPOLICY Resolve executable MIMO rank without silent collapse.
%
% The scheduler may adapt rank only in adaptive modes. Fixed-rank anchor
% configurations must either execute the requested rank or fail before a
% waveform/grant is built.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
direction = upper(strtrim(string(direction)));
if direction ~= "DL" && direction ~= "UL"
    error("sixgr:mimo:RankExecutionPolicy:BadDirection", ...
        "Direction must be DL or UL.");
end
requestedRank = localPositiveInteger(requestedRank, 1);

opt = struct( ...
    "WaveformFadingULSafetyRequested", false, ...
    "TransmissionScheme", "", ...
    "TPMI", NaN);
if ~isempty(varargin)
    if mod(numel(varargin), 2) ~= 0
        error("sixgr:mimo:RankExecutionPolicy:BadNameValue", ...
            "Name-value arguments must come in pairs.");
    end
    for i = 1:2:numel(varargin)
        key = lower(strtrim(string(varargin{i})));
        switch key
            case "waveformfadingulsafetyrequested"
                opt.WaveformFadingULSafetyRequested = logical(varargin{i + 1});
            case "transmissionscheme"
                opt.TransmissionScheme = string(varargin{i + 1});
            case "tpmi"
                opt.TPMI = double(varargin{i + 1});
            otherwise
                error("sixgr:mimo:RankExecutionPolicy:UnknownOption", ...
                    "Unknown rank policy option '%s'.", key);
        end
    end
end

policy = localRankPolicy(cfg);
fixedAnchor = ismember(policy, ["fixed", "fixed_rank", "fixed_rank_anchor", ...
    "configured_fixed", "anchor", "no_adaptation"]);
adaptiveRank = ismember(policy, ["adaptive", "ri", "measured_ri", ...
    "throughput", "runtime", "runtime_ri"]);

[maxLayers, support] = localSupportedLayers(cfg, direction);
if requestedRank > maxLayers
    if fixedAnchor
        error("sixgr:mimo:RankExecutionPolicy:UnsupportedFixedRank", ...
            "%s fixed-rank anchor requested rank %d but only %d layer(s) are supported by ports/codebook.", ...
            direction, requestedRank, maxLayers);
    end
    effectiveRank = maxLayers;
    downgrade = true;
    reason = "requested_rank_exceeds_supported_layers";
else
    effectiveRank = requestedRank;
    downgrade = false;
    reason = "requested_rank_supported";
end

if direction == "UL" && logical(opt.WaveformFadingULSafetyRequested)
    if requestedRank > 1 && maxLayers >= requestedRank && localULRank2WaveformSupported(cfg, opt, requestedRank)
        reason = "waveform_fading_ul_rank_supported_by_ports_and_codebook";
    elseif requestedRank > 1 && fixedAnchor
        error("sixgr:mimo:RankExecutionPolicy:UnsupportedFixedRank", ...
            "UL fixed-rank anchor requested rank %d, but waveform fading PUSCH rank support was not proven for the configured ports/codebook.", ...
            requestedRank);
    elseif requestedRank > 1
        effectiveRank = 1;
        downgrade = true;
        reason = "legacy_waveform_fading_ul_safety_rank1";
    end
end

decision = struct();
decision.Direction = char(direction);
decision.Policy = char(policy);
decision.RequestedRank = double(requestedRank);
decision.EffectiveRank = double(effectiveRank);
decision.MaxSupportedLayers = double(maxLayers);
decision.DowngradeApplied = logical(downgrade);
decision.DecisionReason = char(reason);
decision.FixedRankAnchor = logical(fixedAnchor);
decision.AdaptiveRank = logical(adaptiveRank);
decision.NumPorts = double(support.NumPorts);
decision.NumRxPorts = double(support.NumRxPorts);
decision.CodebookSupported = logical(support.CodebookSupported);
decision.TransmissionScheme = char(string(support.TransmissionScheme));
decision.ValueSource = "sixgr.mimo.resolveRankExecutionPolicy";
end

function policy = localRankPolicy(cfg)
policy = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankPolicy", ...
    sixgr.util.structGet(cfg, "phy.mimo.rankPolicy", ...
    sixgr.util.structGet(cfg, "mimo.rank_adaptation_policy", ...
    sixgr.util.structGet(cfg, "link_adaptation.rank_policy", "fixed")))))));
if policy == ""
    policy = "fixed";
end
policy = replace(policy, "-", "_");
end

function [maxLayers, support] = localSupportedLayers(cfg, direction)
if direction == "UL"
    layerPaths = ["phy.pusch.numLayers", "phy.pusch.nLayers"];
    maxRankPaths = ["phy.pusch.maxLayers", "phy.mimo.maxRank", "mimo.max_rank", "mimo.MaxRank"];
    portPaths = ["phy.pusch.NumAntennaPorts", "phy.pusch.numAntennaPorts", ...
        "phy.pusch.nPorts", "phy.pusch.dmrs.nPorts", "scenario.ue.nTxAnt", ...
        "phy.nTxAnt", "channel.nTxAnt"];
    rxPortPaths = ["scenario.bs.nRxAnt", "phy.nRxAnt", "channel.nRxAnt"];
    scheme = string(sixgr.util.structGet(cfg, "phy.pusch.transmissionScheme", ...
        sixgr.util.structGet(cfg, "phy.pusch.txScheme", "codebook")));
else
    layerPaths = ["phy.pdsch.numLayers", "phy.pdsch.nLayers"];
    maxRankPaths = ["phy.pdsch.maxLayers", "phy.mimo.maxRank", "mimo.max_rank", "mimo.MaxRank"];
    portPaths = ["phy.pdsch.NumAntennaPorts", "phy.pdsch.numAntennaPorts", ...
        "phy.pdsch.nPorts", "phy.pdsch.dmrs.nPorts", "scenario.bs.nTxAnt", ...
        "phy.nTxAnt", "channel.nTxAnt"];
    rxPortPaths = ["scenario.ue.nRxAnt", "phy.nRxAnt", "channel.nRxAnt"];
    scheme = string(sixgr.util.structGet(cfg, "phy.pdsch.transmissionScheme", ...
        sixgr.util.structGet(cfg, "phy.pdsch.txScheme", "codebook")));
end

configuredLayers = localFirstNumeric(cfg, layerPaths, 1);
numPorts = localFirstNumeric(cfg, portPaths, configuredLayers);
numRxPorts = localFirstNumeric(cfg, rxPortPaths, numPorts);
configuredMaxRank = localFirstNumeric(cfg, maxRankPaths, 8);
numPorts = max(1, round(numPorts));
numRxPorts = max(1, round(numRxPorts));
configuredLayers = max(1, round(configuredLayers));
configuredMaxRank = max(1, round(configuredMaxRank));
codebookSupported = localCodebookRankSupported(direction, scheme, numPorts, configuredLayers);
maxLayers = min([8, configuredMaxRank, numPorts, numRxPorts]);
if ~codebookSupported
    maxLayers = min(maxLayers, 1);
end
maxLayers = max(1, round(maxLayers));

support = struct( ...
    "NumPorts", double(numPorts), ...
    "NumRxPorts", double(numRxPorts), ...
    "ConfiguredLayers", double(configuredLayers), ...
    "ConfiguredMaxRank", double(configuredMaxRank), ...
    "CodebookSupported", logical(codebookSupported), ...
    "TransmissionScheme", char(scheme));
end

function tf = localULRank2WaveformSupported(cfg, opt, requestedRank)
scheme = lower(strtrim(string(opt.TransmissionScheme)));
if scheme == ""
    scheme = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.pusch.transmissionScheme", ...
        sixgr.util.structGet(cfg, "phy.pusch.txScheme", "codebook")))));
end
tf = requestedRank <= 4 && ~contains(scheme, "unsupported");
if contains(scheme, "codebook")
    tf = tf && localCodebookRankSupported("UL", scheme, ...
        localFirstNumeric(cfg, ["phy.pusch.NumAntennaPorts", "phy.pusch.numAntennaPorts", ...
        "scenario.ue.nTxAnt", "phy.nTxAnt"], requestedRank), requestedRank);
end
end

function tf = localCodebookRankSupported(direction, scheme, numPorts, rankValue)
direction = upper(string(direction));
scheme = lower(strtrim(string(scheme)));
numPorts = max(1, round(double(numPorts)));
rankValue = max(1, round(double(rankValue)));
if contains(scheme, "noncodebook") || contains(scheme, "non-codebook")
    tf = rankValue <= numPorts;
elseif direction == "UL" && contains(scheme, "codebook")
    tf = (numPorts == 1 && rankValue == 1) || ...
        (numPorts == 2 && rankValue <= 2) || ...
        (numPorts == 4 && rankValue <= 4);
else
    tf = rankValue <= numPorts;
end
end

function value = localFirstNumeric(cfg, paths, defaultValue)
value = defaultValue;
for i = 1:numel(paths)
    candidate = sixgr.util.structGet(cfg, paths(i), []);
    if isnumeric(candidate) && isscalar(candidate) && isfinite(double(candidate))
        value = double(candidate);
        return;
    end
end
end

function n = localPositiveInteger(value, defaultValue)
n = defaultValue;
if isnumeric(value) && isscalar(value) && isfinite(double(value))
    n = double(value);
end
n = max(1, round(n));
end
