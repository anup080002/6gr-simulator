function [Hest, nVar, info] = channelEstimate(carrier, rxGrid, refInd, refSym, varargin)
%CHANNELESTIMATE Generic channel estimation wrapper (DMRS/CSI-RS based).
%
%   [Hest, nVar, info] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, refInd, refSym, ...)
%
%   This wraps 5G Toolbox nrChannelEstimate and standardizes outputs.
%
%   Inputs
%     carrier : nrCarrierConfig
%     rxGrid  : K-by-L-by-R received resource grid
%     refInd  : reference signal indices (DMRS/CSI-RS), as produced by
%               nrPDSCHDMRSIndices/nrPUSCHDMRSIndices/nrCSIRSIndices, etc.
%     refSym  : reference symbols, as produced by corresponding generators
%
%   Name-value pairs are forwarded to nrChannelEstimate (e.g.:
%     "CDMLengths", "AveragingWindow", "Interpolation", ...).
%   Local controls consumed here:
%     "UseFastMex"      : request the scalar LS MEX shortcut
%     "StrictMode"      : reject invalid scalar-estimator combinations
%     "ChannelModel"    : normalized channel token/profile for validation
%     "ExpectedTxPorts" : expected TX port count for truth validation
%     "ContextLabel"    : caller label for diagnostics
%     "Method"          : "LS" (default), "wiener", or "ideal"
%     "TrueChannel"     : channel tensor required by Method="ideal"
%     "Config"          : simulator cfg used for ideal nVar / DMRS defaults
%
%   Outputs
%     Hest : K-by-L-by-R-by-P channel estimate
%     nVar : estimated noise variance (scalar) if returned by the engine
%     info : metadata struct

    if nargin < 4
        error("sixgr:phy:channelEstimate:InvalidInput", ...
            "carrier, rxGrid, refInd, refSym are required.");
    end
    if isempty(refInd) || isempty(refSym)
        error("sixgr:phy:channelEstimate:InvalidReference", ...
            "refInd/refSym must be non-empty.");
    end
    localValidateReferenceSymbols(refSym);
    [refInd, refSym, refPruneInfo] = localPruneZeroReferenceSymbols(refInd, refSym);

    useFastMex = false;
    strictMode = false;
    expectedTxPorts = 1;
    expectedTxPortsProvided = false;
    channelModel = "";
    contextLabel = "channelEstimate";
    estimationMethod = "LS";
    trueChannel = [];
    methodCfg = struct();
    dmrsConfigType = [];
    fwd = varargin;
    if ~isempty(varargin)
        keep = true(size(varargin));
        i = 1;
        while i <= numel(varargin)-1
            k = varargin{i};
            if ischar(k) || isstring(k)
                key = string(k);
                if strcmpi(key, "UseFastMex")
                    useFastMex = logical(varargin{i+1});
                    keep(i:i+1) = false;
                    i = i + 2;
                    continue;
                elseif strcmpi(key, "StrictMode")
                    strictMode = logical(varargin{i+1});
                    keep(i:i+1) = false;
                    i = i + 2;
                    continue;
                elseif strcmpi(key, "ExpectedTxPorts")
                    expectedTxPorts = double(varargin{i+1});
                    expectedTxPortsProvided = true;
                    keep(i:i+1) = false;
                    i = i + 2;
                    continue;
                elseif strcmpi(key, "ChannelModel")
                    channelModel = string(varargin{i+1});
                    keep(i:i+1) = false;
                    i = i + 2;
                    continue;
                elseif strcmpi(key, "ContextLabel")
                    contextLabel = string(varargin{i+1});
                    keep(i:i+1) = false;
                    i = i + 2;
                    continue;
                elseif strcmpi(key, "Method")
                    estimationMethod = string(varargin{i+1});
                    keep(i:i+1) = false;
                    i = i + 2;
                    continue;
                elseif strcmpi(key, "TrueChannel")
                    trueChannel = varargin{i+1};
                    keep(i:i+1) = false;
                    i = i + 2;
                    continue;
                elseif strcmpi(key, "Config") || strcmpi(key, "Cfg")
                    methodCfg = varargin{i+1};
                    keep(i:i+1) = false;
                    i = i + 2;
                    continue;
                elseif strcmpi(key, "DMRSConfigType")
                    dmrsConfigType = varargin{i+1};
                    keep(i:i+1) = false;
                    i = i + 2;
                    continue;
                end
            end
            i = i + 2;
        end
        fwd = varargin(keep);
    end
    estimationMethod = localNormalizeEstimationMethod(estimationMethod);
    inferredReferencePortCount = localInferReferencePortCount(refInd, refSym);
    expectedTxPortsAdjustedFromReferenceGeometry = inferredReferencePortCount > localNormalizeTxPorts(expectedTxPorts);
    expectedTxPorts = max(localNormalizeTxPorts(expectedTxPorts), inferredReferencePortCount);

    policy = localResolveScalarFastPathPolicy(useFastMex, strictMode, channelModel, expectedTxPorts, rxGrid, contextLabel);
    if policy.InvalidStrictCombo
        error("sixgr:phy:channelEstimate:InvalidScalarFastPath", "%s", policy.ErrorMessage);
    end

    info = struct();
    info.ContextLabel = string(policy.ContextLabel);
    info.ChannelModel = string(policy.ChannelModel);
    info.ExpectedTxPorts = double(policy.ExpectedTxPorts);
    info.ExpectedTxPortsProvided = logical(expectedTxPortsProvided);
    info.InferredReferencePortCount = double(inferredReferencePortCount);
    info.ExpectedTxPortsAdjustedFromReferenceGeometry = logical(expectedTxPortsAdjustedFromReferenceGeometry);
    info.NumRxAnt = double(policy.NumRxAnt);
    info.StrictMode = logical(policy.StrictMode);
    info.ScalarFastPathRequested = logical(useFastMex);
    info.ScalarFastPathAllowed = logical(policy.ScalarFastPathAllowed);
    info.ScalarFastPathUsed = false;
    info.ScalarFastPathDisabledReason = string(policy.DisabledReason);
    info.Method = char(estimationMethod);
    info.RxGridSize = size(rxGrid);
    info.ReferenceSymbolsOriginalCount = double(refPruneInfo.OriginalCount);
    info.ReferenceSymbolsUsedCount = double(refPruneInfo.RetainedCount);
    info.ZeroReferenceSymbolCount = double(refPruneInfo.ZeroReferenceSymbolCount);
    info.PrunedZeroReferenceSymbols = logical(refPruneInfo.PrunedZeroReferenceSymbols);
    cdmLengths = localNormalizeCDMLengths(localResolveCDMLengths(refInd, refSym, fwd, methodCfg, dmrsConfigType));
    info.CDMLengths = double(cdmLengths);
    if isempty(cdmLengths)
        fwd = localRemoveFwdNameValue(fwd, "CDMLengths");
    elseif any(double(cdmLengths) > 1)
        fwd = localSetFwdNameValue(fwd, "CDMLengths", double(cdmLengths));
    end

    if estimationMethod == "ideal"
        if isempty(trueChannel)
            error("sixgr:phy:channelEstimate:IdealChannelMissing", ...
                "Method='ideal' requires non-empty TrueChannel runtime evidence.");
        end
        Hest = trueChannel;
        nVar = localNoiseVarianceFromConfig(methodCfg);
        info.EngineUsed = "ideal_true_channel_runtime_evidence";
        info.HestSize = size(Hest);
        info.NoiseVar = nVar;
        info.IdealChannelSource = "TrueChannel_name_value";
        return;
    elseif estimationMethod == "wiener"
        fwd = localSetFwdNameValue(fwd, "Interpolation", "linear");
        fwd = localSetFwdNameValue(fwd, "AveragingWindow", [0 0]);
    end

    if policy.UseFastMexEffective && ...
            (exist("sixgr_channel_est_ls_kernel_mex","file") == 3 || exist("sixgr_channel_est_ls_kernel","file") == 2)
        try
            rxRef = nrExtractResources(refInd, rxGrid);
            if ~isvector(rxRef)
                rxRef = rxRef(:,1);
            end
            refV = refSym(:);
            if ~isvector(refV)
                refV = refV(:,1);
            end
            if exist("sixgr_channel_est_ls_kernel_mex","file") == 3
                [hScalar, nVar] = sixgr_channel_est_ls_kernel_mex(rxRef(:), refV(:));
                engine = "sixgr_channel_est_ls_kernel_mex";
            else
                [hScalar, nVar] = sixgr_channel_est_ls_kernel(rxRef(:), refV(:));
                engine = "sixgr_channel_est_ls_kernel";
            end
            Hest = cast(ones(size(rxGrid)), "like", rxGrid) .* cast(hScalar, "like", rxGrid);
            info.EngineUsed = engine;
            info.HestSize = size(Hest);
            info.NoiseVar = nVar;
            info.ScalarFastPathUsed = true;
            return;
        catch ME
            info.FastMexError = string(ME.message);
            % Safe fallback to the resource-selective nrChannelEstimate path.
        end
    end

    engine = "nrChannelEstimate";
    try
        suppressZeroReferenceWarning = false;
        prevWarnMsg = "";
        prevWarnId = "";
        if double(refPruneInfo.ZeroReferenceSymbolCount) > 0 && ~logical(refPruneInfo.PrunedZeroReferenceSymbols)
            [prevWarnMsg, prevWarnId] = lastwarn;
            warnState = warning("query", "nr5g:nrChannelEstimate:ZeroValuedSym");
            cleanupWarn = onCleanup(@() warning(warnState.state, "nr5g:nrChannelEstimate:ZeroValuedSym")); %#ok<NASGU>
            warning("off", "nr5g:nrChannelEstimate:ZeroValuedSym");
            suppressZeroReferenceWarning = true;
        end
        % Most common signature: [Hest, nVar] = nrChannelEstimate(carrier, rxGrid, refInd, refSym, ...)
        [Hest, nVar] = nrChannelEstimate(carrier, rxGrid, refInd, refSym, fwd{:});
        if suppressZeroReferenceWarning
            [warnMsg, warnId] = lastwarn;
            if strcmp(string(warnId), "nr5g:nrChannelEstimate:ZeroValuedSym")
                lastwarn(prevWarnMsg, prevWarnId);
            end
        end
    catch ME
        error("sixgr:phy:channelEstimate:Failed", ...
            "nrChannelEstimate failed: %s", ME.message);
    end

    info.EngineUsed = engine;
    info.HestSize = size(Hest);
    info.NoiseVar = nVar;
end

function localValidateReferenceSymbols(refSym)
try
    refValues = refSym(:);
catch
    error("sixgr:phy:channelEstimate:InvalidReference", ...
        "refSym must be an array of numeric reference symbols.");
end
if ~isnumeric(refValues) || isempty(refValues)
    error("sixgr:phy:channelEstimate:InvalidReference", ...
        "refSym must contain numeric reference symbols.");
end
finiteMask = isfinite(real(refValues)) & isfinite(imag(refValues));
if ~all(finiteMask)
    error("sixgr:phy:channelEstimate:InvalidReference", ...
        "refSym contains non-finite reference symbols.");
end
if ~any(abs(refValues) > 0)
    error("sixgr:phy:channelEstimate:InvalidReference", ...
        "refSym contains no non-zero reference symbols; channel estimation requires real DMRS/CSI-RS evidence.");
end
end

function method = localNormalizeEstimationMethod(raw)
method = lower(strtrim(string(raw)));
if strlength(method) == 0
    method = "ls";
end
switch method
    case {"ls","least_squares","least-squares"}
        method = "LS";
    case {"wiener","wiener_interpolation","wiener_interpolated"}
        method = "wiener";
    case {"ideal","true","true_channel"}
        method = "ideal";
    otherwise
        error("sixgr:phy:channelEstimate:UnknownMethod", ...
            "Unknown channel estimation Method '%s'. Use LS, wiener, or ideal.", char(method));
end
end

function nVar = localNoiseVarianceFromConfig(cfg)
nVar = NaN;
if isstruct(cfg)
    snr_dB = double(sixgr.util.structGet(cfg, "channel.snr_dB", ...
        sixgr.util.structGet(cfg, "simulation.snr_db", NaN)));
    if isscalar(snr_dB) && isfinite(snr_dB)
        nVar = 10 .^ (-snr_dB ./ 10);
    end
end
if ~(isscalar(nVar) && isfinite(nVar) && nVar >= 0)
    nVar = 0;
end
end

function cdm = localResolveCDMLengths(refInd, refSym, fwd, cfg, dmrsConfigType)
cdm = [];
for i = 1:2:numel(fwd)-1
    if strcmpi(char(string(fwd{i})), 'CDMLengths')
        cdm = localNormalizeCDMLengths(fwd{i+1});
        return;
    end
end
dmrsType = localResolveDMRSConfigType(cfg, dmrsConfigType);
if dmrsType == 1
    cdm = [2 1];
    return;
elseif dmrsType == 2
    cdm = [2 2];
    return;
end
cdm = localNormalizeCDMLengths(localDetectCDMLengths(refInd, refSym));
end

function dmrsType = localResolveDMRSConfigType(cfg, explicitValue)
dmrsType = NaN;
raw = explicitValue;
if isempty(raw) && isstruct(cfg)
    raw = sixgr.util.structGet(cfg, "phy.dmrs.configType", ...
        sixgr.util.structGet(cfg, "phy.pdsch.dmrs.configType", ...
        sixgr.util.structGet(cfg, "phy.pusch.dmrs.configType", [])));
end
if isempty(raw)
    return;
end
if isnumeric(raw) || islogical(raw)
    val = double(raw);
    if ~isempty(val) && isfinite(val(1))
        dmrsType = round(val(1));
    end
else
    token = lower(strtrim(string(raw)));
    if any(token == ["1","type1","type_1","configurationtype1"])
        dmrsType = 1;
    elseif any(token == ["2","type2","type_2","configurationtype2"])
        dmrsType = 2;
    end
end
if ~ismember(dmrsType, [1 2])
    dmrsType = NaN;
end
end

function fwd = localSetFwdNameValue(fwd, name, value)
updated = false;
for i = 1:2:numel(fwd)-1
    if strcmpi(char(string(fwd{i})), char(string(name)))
        fwd{i+1} = value;
        updated = true;
        return;
    end
end
if ~updated
    fwd = [fwd, {char(string(name)), value}]; %#ok<AGROW>
end
end

function fwd = localRemoveFwdNameValue(fwd, name)
if isempty(fwd)
    return;
end
keep = true(size(fwd));
for i = 1:2:numel(fwd)-1
    if strcmpi(char(string(fwd{i})), char(string(name)))
        keep(i:i+1) = false;
    end
end
fwd = fwd(keep);
end

function cdm = localNormalizeCDMLengths(raw)
if isempty(raw)
    cdm = [];
    return;
end
cdm = double(raw);
cdm = cdm(:).';
cdm = cdm(isfinite(cdm));
if isempty(cdm)
    cdm = [];
    return;
end
cdm = max(1, round(cdm));
if numel(cdm) == 1
    cdm = [cdm 1];
elseif numel(cdm) > 2
    cdm = cdm(1:2);
end
end

function cdm = localDetectCDMLengths(refInd, refSym)
cdm = [];
try
    if ~isvector(refSym) && size(refSym, 2) >= 2
        a = refSym(:, 1);
        b = refSym(:, 2);
        corrVal = abs(sum(a(:) .* conj(b(:)), "omitnan"));
        energy = sqrt(sum(abs(a(:)).^2, "omitnan") * sum(abs(b(:)).^2, "omitnan"));
        if energy > 0
            ratio = corrVal / energy;
            if ratio < 0.1
                cdm = [2 1];
            elseif ratio > 0.9
                cdm = [1 1];
            end
        end
    elseif ~isempty(refInd) && numel(refInd) >= 2
        cdm = [1 1];
    end
catch
    cdm = [];
end
end

function [refIndOut, refSymOut, info] = localPruneZeroReferenceSymbols(refInd, refSym)
refIndOut = refInd;
refSymOut = refSym;
refValues = refSym(:);
keep = abs(refValues) > 0;

info = struct();
info.OriginalCount = double(numel(refValues));
info.RetainedCount = double(nnz(keep));
info.ZeroReferenceSymbolCount = double(numel(refValues) - nnz(keep));
info.PrunedZeroReferenceSymbols = info.ZeroReferenceSymbolCount > 0;

if ~logical(info.PrunedZeroReferenceSymbols)
    return;
end
if localShouldPreserveReferencePortShape(refInd, refSym)
    info.PrunedZeroReferenceSymbols = false;
    info.PreservedReferencePortShape = true;
    return;
end
if ~any(keep)
    error("sixgr:phy:channelEstimate:InvalidReference", ...
        "refSym contains no non-zero reference symbols; channel estimation requires real DMRS/CSI-RS evidence.");
end
if ~isnumeric(refInd)
    error("sixgr:phy:channelEstimate:InvalidReference", ...
        "refInd must be numeric when pruning zero reference symbols.");
end

if numel(refInd) == numel(refValues)
    refIndValues = refInd(:);
    refIndOut = refIndValues(keep);
    refSymOut = refValues(keep);
elseif size(refInd, 1) == numel(refValues)
    refIndOut = refInd(keep, :);
    refSymOut = refValues(keep);
else
    error("sixgr:phy:channelEstimate:InvalidReference", ...
        "Cannot prune zero reference symbols because refInd/refSym shapes do not align.");
end
end

function tf = localShouldPreserveReferencePortShape(refInd, refSym)
tf = isnumeric(refInd) && isnumeric(refSym) && ~isvector(refInd) && ~isvector(refSym) && ...
    size(refInd, 2) == size(refSym, 2) && size(refSym, 2) > 1;
end

function numPorts = localInferReferencePortCount(refInd, refSym)
numPorts = 1;
if isnumeric(refSym) && ~isvector(refSym)
    numPorts = max(numPorts, size(refSym, 2));
end
if isnumeric(refInd) && ~isvector(refInd)
    numPorts = max(numPorts, size(refInd, 2));
end
if ~(isscalar(numPorts) && isfinite(numPorts) && numPorts >= 1)
    numPorts = 1;
end
numPorts = max(1, round(double(numPorts)));
end

function policy = localResolveScalarFastPathPolicy(useFastMex, strictMode, channelModel, expectedTxPorts, rxGrid, contextLabel)
expectedTxPorts = localNormalizeTxPorts(expectedTxPorts);
numRxAnt = localNumRxAnt(rxGrid);
channelModel = localNormalizeChannelToken(channelModel);
contextLabel = string(contextLabel);
if strlength(contextLabel) == 0
    contextLabel = "channelEstimate";
end

isSelectiveChannel = localIsSelectiveChannel(channelModel);
requiresSpatialSelectivity = expectedTxPorts > 1 || numRxAnt > 1;
scalarFastPathAllowed = localIsExplicitFlatChannel(channelModel) && ...
    ~isSelectiveChannel && ~requiresSpatialSelectivity;

disabledReason = "";
if logical(useFastMex) && ~scalarFastPathAllowed
    if isSelectiveChannel
        disabledReason = "Selective fading truth validation requires a resource-selective estimator.";
    elseif requiresSpatialSelectivity
        disabledReason = "Multi-antenna truth validation requires a resource-selective estimator.";
    else
        disabledReason = "Scalar fast estimation is restricted to explicit AWGN/flat SISO validation modes.";
    end
end

policy = struct();
policy.ChannelModel = channelModel;
policy.ContextLabel = contextLabel;
policy.ExpectedTxPorts = expectedTxPorts;
policy.NumRxAnt = numRxAnt;
policy.StrictMode = logical(strictMode);
policy.ScalarFastPathAllowed = logical(scalarFastPathAllowed);
policy.UseFastMexEffective = logical(useFastMex) && logical(scalarFastPathAllowed);
policy.DisabledReason = disabledReason;
policy.InvalidStrictCombo = logical(useFastMex) && logical(strictMode) && ~logical(scalarFastPathAllowed);
policy.ErrorMessage = sprintf('%s: %s Channel=''%s'', TxPorts=%d, RxAnt=%d. Disable the scalar fast estimator or use an explicit AWGN/flat SISO validation mode.', ...
    char(contextLabel), char(disabledReason), localDisplayChannelToken(channelModel), expectedTxPorts, numRxAnt);
end

function numTxPorts = localNormalizeTxPorts(expectedTxPorts)
numTxPorts = double(expectedTxPorts);
if ~(isscalar(numTxPorts) && isfinite(numTxPorts) && numTxPorts >= 1)
    numTxPorts = 1;
end
numTxPorts = max(1, round(numTxPorts));
end

function numRxAnt = localNumRxAnt(rxGrid)
sz = size(rxGrid);
if numel(sz) < 3 || isempty(sz(3))
    numRxAnt = 1;
else
    numRxAnt = max(1, double(sz(3)));
end
end

function token = localNormalizeChannelToken(rawValue)
token = upper(strtrim(char(string(rawValue))));
end

function tf = localIsSelectiveChannel(channelModel)
tf = startsWith(channelModel, "TDL") || startsWith(channelModel, "CDL");
end

function tf = localIsExplicitFlatChannel(channelModel)
tf = any(strcmp(channelModel, {"AWGN", "NONE", "OFF"}));
end

function token = localDisplayChannelToken(channelModel)
token = char(channelModel);
if isempty(token)
    token = "<unspecified>";
end
end
