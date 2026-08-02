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
    "MUMIMOSpatialDesignEvidenceSource", ...
    "MUMIMOSpatialFilterMatrixSHA256","MUMIMOReceiveCombiningMatrixSHA256", ...
    "MUMIMOReceiverAlgorithm","MUMIMOHybridRFDesignPolicy", ...
    "MUMIMOHybridRFDesignStatus","HybridElementToPortMatrixSHA256", ...
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
end
