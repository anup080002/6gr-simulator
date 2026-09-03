function T = annotateFrozenMUMIMOTrialEvidence(T, grant)
%ANNOTATEFROZENMUMIMOTRIALEVIDENCE Preserve exact MU grant evidence.
% Receiver completion owns decoded PHY measurements. The frozen scheduler
% grant owns whether a transmitted waveform belonged to a shared-resource
% MU opportunity. This function copies only that immutable MU contract and
% never reconstructs pairing evidence from configured values or outcomes.

if ~(istable(T) && ~isempty(T))
    return;
end
if ~(isstruct(grant) && isscalar(grant))
    error("sixgr:truth:InvalidFrozenMUMIMOGrant", ...
        "MU trial annotation requires one frozen grant structure.");
end

n = height(T);
logicalFields = "MUMIMOEnabled";
numericFields = ["MUMIMOGroupSize","MUMIMOGroupId", ...
    "MUMIMOPairingMetricValue_dB","MUMIMOPairingWorstMetricValue_dB", ...
    "MUMIMORequiredLeakageThreshold_dB","MUMIMODesiredSubspaceGain_dB", ...
    "MUMIMORequiredMinimumDesiredGain_dB","NumLogicalPorts","NumRFChains"];
stringFields = ["MUMIMOPairingStatus","MUMIMOPairingMetricSource", ...
    "MUMIMOPairingEvidenceSource","MUMIMOPrecoderType", ...
    "MUMIMOSpatialDesignStatus","MUMIMOSpatialDesignContractVersion", ...
    "MUMIMOSpatialSignatureSubspaceMode", ...
    "MUMIMOSpatialDesignEvidenceSource", ...
    "MUMIMOSpatialFilterMatrixSHA256","MUMIMOReceiveCombiningMatrixSHA256", ...
    "MUMIMOAdmissionReceiveCombiningMatrixSHA256","MUMIMOReceiveProcessingMode", ...
    "MUMIMOReceiverAlgorithm","MUMIMOHybridRFDesignPolicy", ...
    "MUMIMOHybridRFDesignStatus","MUMIMOTransmitArchitecture", ...
    "HybridElementToPortMatrixSHA256", ...
    "BaseHybridElementToPortMatrixSHA256"];

for fieldName = logicalFields
    value = logical(sixgr.util.structGet(grant, fieldName, false));
    T.(char(fieldName)) = repmat(value, n, 1);
end
for fieldName = numericFields
    value = double(sixgr.util.structGet(grant, fieldName, NaN));
    if ~(isscalar(value) && (isfinite(value) || isnan(value)))
        error("sixgr:truth:InvalidFrozenMUMIMOEvidence", ...
            "Frozen grant field %s must be a finite scalar or NaN.", fieldName);
    end
    T.(char(fieldName)) = repmat(value, n, 1);
end
for fieldName = stringFields
    value = string(sixgr.util.structGet(grant, fieldName, ""));
    if isempty(value) || any(ismissing(value))
        value = "";
    elseif ~isscalar(value)
        error("sixgr:truth:InvalidFrozenMUMIMOEvidence", ...
            "Frozen grant field %s must be scalar text.", fieldName);
    end
    T.(char(fieldName)) = repmat(value, n, 1);
end

% Shared-resource execution is part of the immutable grant contract. Keep
% its allocation beside the waveform trial so downstream MU validation
% compares the two actually transmitted members without joining on a
% report-time scheduler approximation.
prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
symbolAllocation = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
muEnabled = logical(sixgr.util.structGet(grant, "MUMIMOEnabled", false));
if muEnabled && (isempty(prbSet) || numel(symbolAllocation) ~= 2 || ...
        any(~isfinite(prbSet(:))) || any(~isfinite(symbolAllocation(:))))
    error("sixgr:truth:MissingFrozenMUMIMOAllocation", ...
        "A frozen MU-MIMO grant requires finite PRBSet and [start count] SymbolAllocation values.");
end
if ~isempty(prbSet)
    T.PRBStart = repmat(double(min(prbSet(:))), n, 1);
    T.PRBCount = repmat(double(numel(unique(prbSet(:)))), n, 1);
end
if numel(symbolAllocation) == 2 && all(isfinite(symbolAllocation(:)))
    T.SymbolStart = repmat(double(symbolAllocation(1)), n, 1);
    T.NumSymbols = repmat(double(symbolAllocation(2)), n, 1);
end
end
