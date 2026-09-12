function prec = resolvePUSCHPrecoding(pusch, cfg, varargin)
%RESOLVEPUSCHPRECODING Describe the runtime-applied UL PUSCH precoder.
%
% The returned MatrixPorts is Nports-by-Nlayers. For codebook PUSCH the
% Toolbox forward matrix is MatrixNR, with X = S * MatrixNR.

if nargin < 2 || ~isstruct(cfg)
    cfg = struct();
end
ip = inputParser;
ip.addParameter("FixedReferenceMode", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("SRSDecision", [], @(x) isempty(x) || (isstruct(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;
strictMIMO = logical(sixgr.util.structGet(cfg,"mimo.strict", ...
    sixgr.util.structGet(cfg,"phy.mimo.strict",false)));
normalizationConvention = localResolveNormalizationConvention(cfg);

nLayers = localPositiveInteger(localObjectValue(pusch, "NumLayers", 1), "NumLayers");
arch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg, "ue", ...
    "Signal", "PUSCH", "MinimumPorts", max(1, nLayers));
transformPrecoding = logical(localObjectValue(pusch, "TransformPrecoding", false));
scheme = string(localObjectValue(pusch, "TransmissionScheme", "nonCodebook"));
isCodebook = strcmpi(char(scheme), "codebook");

nPorts = double(localObjectValue(pusch, "NumAntennaPorts", NaN));
if ~(isscalar(nPorts) && isfinite(nPorts) && nPorts >= 1)
    nPorts = localResolvePUSCHConfiguredPorts(cfg);
end
if ~(isscalar(nPorts) && isfinite(nPorts) && nPorts >= 1)
    nPorts = double(arch.NumPorts);
end
nPorts = max(1, round(double(nPorts)));

tpmi = NaN;
receivedDCI=sixgr.util.structGet(cfg,'phy.pusch.receivedDCIAssignment',struct());
hasReceivedDCI=isstruct(receivedDCI) && ~isempty(fieldnames(receivedDCI));
assert(~hasReceivedDCI || isCodebook, ...
    'sixgr:phy:ul:ReceivedPrecodingMismatch', ...
    'A received codebook command cannot authorize non-codebook transmission.');
if isCodebook
    tpmi = double(localObjectValue(pusch, "TPMI", NaN));
    srsDecision = opt.SRSDecision;
    if isempty(srsDecision)
        srsDecision = sixgr.util.structGet(cfg,"phy.pusch.srsDecision",[]);
    end
    if hasReceivedDCI
        receivedContext=sixgr.phy.pdcch.validateConnectedAssignment(cfg,receivedDCI);
        assert(receivedDCI.Direction=="UL" && receivedDCI.TPMI==tpmi && ...
            receivedDCI.NumLayers==nLayers && receivedContext.Data.ULPrecoding.num_ports==nPorts && ...
            receivedContext.Data.TransformPrecodingEnabled==transformPrecoding && ...
            receivedDCI.RNTI==pusch.RNTI && ...
            receivedDCI.DataAbsoluteSlot==cfg.lls6g.runtime.AbsoluteSlotIndex0, ...
            'sixgr:phy:ul:ReceivedPrecodingMismatch', ...
            'UE codebook transmission must retain received TPMI, rank, identity, ports and data slot.');
    elseif strictMIMO
        localValidateSRSAuthority(srsDecision,nLayers,nPorts,tpmi);
        tpmi = double(srsDecision.TPMI);
    end
    localValidateCodebookInputs(nLayers, nPorts, tpmi);
else
    srsDecision = opt.SRSDecision;
end

prec = struct();
prec.Active = logical(transformPrecoding || isCodebook);
prec.Mode = "direct_mapping_no_explicit_beam_weights";
prec.Source = "ul_direct_mapping_no_explicit_beam_weights";
prec.ApplicationStage = "re_mapping_without_explicit_beam_weights";
prec.NormalizeW = false;
prec.NumLayers = double(nLayers);
prec.NumPorts = double(max(nPorts, nLayers));
prec.NumLogicalPorts = double(max(nPorts, nLayers));
prec.NumWaveformColumns = double(max(nPorts, nLayers));
prec.NumCodewords = double(localObjectValue(pusch, "NumCodewords", 1));
prec.WidebandOnly = true;
prec.PMI = NaN;
prec.PMIType = "";
prec.CodebookMode = "";
prec.CodebookStatus = "";
prec.CodebookCatalogSource = "";
prec.CodebookCatalogValidTPMISet = [];
prec.CodebookCatalogNumCandidates = NaN;
prec.BeamIndices = [];
prec.CodebookPortIndices1Based = [];
prec.CodebookPortIndexDefinition = "";
prec.MatrixRows = double(max(nPorts, nLayers));
prec.MatrixCols = double(nLayers);
prec.MatrixPorts = localRectIdentity(max(nPorts, nLayers), nLayers, ...
    normalizationConvention);
prec.MatrixLogicalPorts = prec.MatrixPorts;
prec.MatrixNR = [];
prec.MatrixRightInverse = [];
prec.ExplicitBeamWeightsApplied = false;
prec.TransformPrecodingApplied = logical(transformPrecoding);
prec.BeamformingApplied = false;
prec.NativeCodebookApplied = false;
prec.HybridBeamformingApplied = false;
prec.HybridElementDomainApplied = false;
prec.HybridElementToPortMatrix = [];
prec.HybridAnalogPrecoderMatrix = [];
prec.HybridDigitalPortToRFChainMatrix = [];
prec.HybridEquation = "";
prec.BeamIndexDefinition = "";
prec.FixedReferenceMode = logical(opt.FixedReferenceMode);
prec.StrictMIMO = logical(strictMIMO);
prec.AuthoritativeSRSDecisionUsed = false;
prec.AuthoritativeDCIDecisionUsed = false;
prec.DecodedDCIAssignmentDigest = "";
prec.SRSMeasurementID = "";
prec.SRSMeasurementSlot = NaN;
prec.SelectedMatrixSHA256 = "";
prec.AppliedMatrixSHA256 = "";
prec.NormalizationConvention = normalizationConvention;
prec = localAttachArchitecture(prec, arch);
prec = localAttachPowerInfo(prec, prec.MatrixPorts, nLayers, ...
    normalizationConvention);

if transformPrecoding && ~isCodebook
    if strictMIMO && isempty(srsDecision)
        error("sixgr:mimo:MissingSRSState", ...
            "Strict transform-precoded PUSCH requires a timestamped measured SRS decision.");
    end
    prec.Mode = "transform_precoding";
    prec.Source = "ul_pusch_transform_precoding";
    prec.ApplicationStage = "dft_spread_before_re_mapping";
    prec = localApplyHybridElementDomainPrecoder(prec, arch, nLayers);
    prec.MatrixRows = double(size(prec.MatrixPorts, 1));
    prec.MatrixCols = double(size(prec.MatrixPorts, 2));
    prec = localAttachPowerInfo(prec, prec.MatrixPorts, nLayers, ...
        normalizationConvention);
    return;
end

if ~isCodebook
    if strictMIMO && nLayers > 1 && isempty(srsDecision)
        error("sixgr:mimo:MissingSRSState", ...
            "Strict multi-layer non-codebook PUSCH requires a measured SRS precoder decision.");
    end
    if strictMIMO && ~isempty(srsDecision) && isfield(srsDecision,"MatrixPorts")
        Wmeasured = double(srsDecision.MatrixPorts);
        sixgr.phy.mimo.MatrixContract.validate(Wmeasured,size(Wmeasured,1),nLayers, ...
            "NormalizationConvention", normalizationConvention);
        prec.MatrixPorts = Wmeasured;
        prec.MatrixLogicalPorts = Wmeasured;
        prec.MatrixRows = size(Wmeasured,1);
        prec.MatrixCols = size(Wmeasured,2);
        prec.NumPorts = size(Wmeasured,1);
        prec.NumLogicalPorts = size(Wmeasured,1);
        prec.NumWaveformColumns = size(Wmeasured,1);
        prec.Source = "authoritative_measured_srs_noncodebook_precoder";
        prec.ApplicationStage = "explicit_measured_srs_precoder_before_re_mapping";
        prec.ExplicitBeamWeightsApplied = true;
        prec.BeamformingApplied = true;
        prec.AuthoritativeSRSDecisionUsed = true;
        prec = localAttachSRSIdentity(prec,srsDecision);
        prec.SelectedMatrixSHA256 = sixgr.phy.mimo.MatrixContract.digest(Wmeasured);
        prec = localApplyHybridElementDomainPrecoder(prec, arch, nLayers);
        prec.AppliedMatrixSHA256 = sixgr.phy.mimo.MatrixContract.digest(prec.MatrixPorts);
        prec = localAttachPowerInfo(prec, prec.MatrixPorts, nLayers, ...
            normalizationConvention);
        return;
    end
    % Non-codebook PUSCH still occupies the configured logical antenna-port
    % domain before any hybrid element expansion.  Retransmission grants can
    % carry NumAntennaPorts=NumLayers even when the runtime UE architecture
    % has more logical ports.  Collapsing the matrix to NumLayers-by-
    % NumLayers in that case makes the hybrid element-to-port matrix
    % impossible to compose (for example, 4x4 * 2x2 in a 4-element UE).
    % Preserve the architecture/configured logical-port count and use a
    % rectangular identity layer mapper instead.
    architectureLogicalPorts = nPorts;
    if logical(sixgr.util.structGet(arch, "HybridBeamformingEnabled", false))
        architectureLogicalPorts = double(sixgr.util.structGet(arch, ...
            "NumLogicalPorts",sixgr.util.structGet(arch,"NumPorts",nPorts)));
    end
    logicalPortCount = max([nLayers,nPorts,architectureLogicalPorts]);
    logicalPortCount = max(1, round(double(logicalPortCount)));
    [configuredLogicalMatrix, configuredMatrixSource] = ...
        localResolveConfiguredLogicalPrecoder(cfg, logicalPortCount, nLayers, ...
        normalizationConvention);
    if isempty(configuredLogicalMatrix)
        prec.MatrixPorts = localRectIdentity(logicalPortCount, nLayers, ...
            normalizationConvention);
        prec.Source = "ul_noncodebook_configured_normalization_identity";
        prec.ExplicitBeamWeightsApplied = normalizationConvention == "unit_frobenius" && nLayers > 1;
    else
        prec.MatrixPorts = configuredLogicalMatrix;
        prec.Source = configuredMatrixSource;
        prec.ApplicationStage = "explicit_layer_to_logical_port_precoding_before_re_mapping";
        prec.ExplicitBeamWeightsApplied = true;
        prec.BeamformingApplied = true;
        prec.SelectedMatrixSHA256 = sixgr.phy.mimo.MatrixContract.digest(configuredLogicalMatrix);
    end
    prec.MatrixLogicalPorts = prec.MatrixPorts;
    prec.MatrixRows = double(logicalPortCount);
    prec.MatrixCols = double(nLayers);
    prec.NumPorts = double(logicalPortCount);
    prec.NumLogicalPorts = double(logicalPortCount);
    prec.NumWaveformColumns = double(logicalPortCount);
    prec = localApplyHybridElementDomainPrecoder(prec, arch, nLayers);
    prec.AppliedMatrixSHA256 = sixgr.phy.mimo.MatrixContract.digest(prec.MatrixPorts);
    prec = localAttachPowerInfo(prec, prec.MatrixPorts, nLayers, ...
        normalizationConvention);
    return;
end

if transformPrecoding
    prec.Mode = "transform_precoding_codebook_tpmi";
    prec.Source = "ul_pusch_native_transform_codebook_tpmi";
    prec.ApplicationStage = "dft_spread_then_nrPUSCH_native_codebook_precoding";
else
    prec.Mode = "ul_codebook_tpmi";
    prec.Source = "ul_pusch_native_codebook_tpmi";
    prec.ApplicationStage = "nrPUSCH_native_codebook_precoding_during_modulation";
end
prec.PMI = double(round(tpmi));
prec.PMIType = "pusch_codebook";
prec.CodebookMode = string(localObjectValue(pusch, "CodebookType", ...
    sixgr.util.structGet(cfg, "phy.pusch.codebookType", "")));
if strlength(strtrim(prec.CodebookMode)) == 0
    error("sixgr:phy:ul:PUSCHPrecoding:MissingCodebookType", ...
        "Codebook PUSCH requires an explicit resolved nrPUSCHConfig.CodebookType.");
end
prec.BeamformingApplied = true;
prec.NativeCodebookApplied = true;
catalog = sixgr.phy.ul.puschCodebookCatalog(nLayers, nPorts, transformPrecoding);
prec.CodebookCatalogSource = string(catalog.Source);
prec.CodebookCatalogValidTPMISet = double(catalog.ValidTPMISet);
prec.CodebookCatalogNumCandidates = double(catalog.NumTPMICandidates);
try
    [Wports, codebookStatus, Wtx, Winv] = sixgr.phy.ul.puschCodebookProjectionMatrix( ...
        nLayers, nPorts, tpmi, transformPrecoding);
catch ME
    error("sixgr:phy:ul:PUSCHPrecoding:UnsupportedCodebook", ...
        "Invalid PUSCH codebook configuration: %s", ME.message);
end
prec.MatrixPorts = Wports;
prec.MatrixLogicalPorts = Wports;
prec.MatrixNR = Wtx;
prec.MatrixRightInverse = Winv;
prec.MatrixRows = double(size(Wports, 1));
prec.MatrixCols = double(size(Wports, 2));
prec.NumPorts = double(size(Wports, 1));
prec.NumLogicalPorts = double(size(Wports, 1));
prec.NumWaveformColumns = double(size(Wports, 1));
prec.CodebookPortIndices1Based = double(localActiveCodebookPorts(Wtx));
prec.CodebookPortIndexDefinition = "one_based_logical_antenna_port_support_not_spatial_beam_ID";
prec.CodebookStatus = string(codebookStatus);
if hasReceivedDCI
    prec.AuthoritativeDCIDecisionUsed=true;
    prec.DecodedDCIAssignmentDigest=receivedDCI.AssignmentDigest;
    prec.Source="ul_pusch_native_codebook_received_dci";
    prec.SRI=receivedDCI.SRSResourceIndex;
elseif strictMIMO
    selectedDigest = string(sixgr.util.structGet(srsDecision,"SelectionMatrixSHA256",""));
    actualDigest = sixgr.phy.mimo.MatrixContract.digest(Wports);
    if strlength(selectedDigest) > 0 && ~strcmpi(selectedDigest,actualDigest)
        error("sixgr:mimo:PrecoderDigestMismatch", ...
            "SRS-selected and PUSCH-applied TPMI matrices differ.");
    end
    prec.AuthoritativeSRSDecisionUsed = true;
    prec.SelectedMatrixSHA256 = actualDigest;
    prec = localAttachSRSIdentity(prec,srsDecision);
end
prec = localApplyHybridElementDomainPrecoder(prec, arch, nLayers);
if strlength(string(prec.SelectedMatrixSHA256)) == 0
    prec.SelectedMatrixSHA256 = sixgr.phy.mimo.MatrixContract.digest(prec.MatrixLogicalPorts);
end
prec.AppliedMatrixSHA256 = sixgr.phy.mimo.MatrixContract.digest(prec.MatrixPorts);
prec = localAttachPowerInfo(prec, prec.MatrixPorts, nLayers, ...
    normalizationConvention);
end

function localValidateSRSAuthority(decision,nLayers,nPorts,tpmi)
if isempty(decision) || ~isstruct(decision) || ...
        ~logical(sixgr.util.structGet(decision,"Authoritative",false))
    error("sixgr:mimo:MissingSRSState", ...
        "Strict codebook PUSCH requires an authoritative measured-SRS RI/SRI/TPMI decision.");
end
required = ["MeasurementID","MeasurementSlot","RI","TPMI"];
for name = required
    value = sixgr.util.structGet(decision,name,[]);
    if isempty(value) || (isstring(value) && all(strlength(value)==0))
        error("sixgr:mimo:MissingSRSState", ...
            "Authoritative SRS decision is missing %s.",name);
    end
end
if double(decision.RI) ~= double(nLayers)
    error("sixgr:mimo:RankIdentityMismatch", ...
        "SRS-selected RI %d differs from scheduled PUSCH layers %d.", ...
        double(decision.RI),double(nLayers));
end
if isfield(decision,"NumPorts") && double(decision.NumPorts) ~= double(nPorts)
    error("sixgr:mimo:PortIdentityMismatch", ...
        "SRS decision port count differs from the active PUSCH codebook.");
end
if isfinite(tpmi) && double(decision.TPMI) ~= double(tpmi)
    error("sixgr:mimo:PrecoderDigestMismatch", ...
        "Configured PUSCH TPMI differs from the authoritative measured-SRS TPMI.");
end
end

function prec = localAttachSRSIdentity(prec,decision)
prec.SRSMeasurementID = string(sixgr.util.structGet(decision,"MeasurementID",""));
prec.SRSMeasurementSlot = double(sixgr.util.structGet(decision,"MeasurementSlot",NaN));
prec.SRI = double(sixgr.util.structGet(decision,"SRI",NaN));
end

function nPorts = localResolvePUSCHConfiguredPorts(cfg)
nPorts = NaN;
paths = ["phy.pusch.NumAntennaPorts", "phy.pusch.numAntennaPorts", "phy.pusch.numPorts", "phy.pusch.nPorts"];
for i = 1:numel(paths)
    value = sixgr.util.structGet(cfg, paths(i), []);
    if isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) >= 1
        nPorts = max(1, round(double(value)));
        return;
    end
end
end

function prec = localAttachArchitecture(prec, arch)
prec.NumElements = double(sixgr.util.structGet(arch, "NumElements", NaN));
prec.NumRFChains = double(sixgr.util.structGet(arch, "NumRFChains", NaN));
prec.ArchitectureNumLogicalPorts = double(sixgr.util.structGet(arch, "NumLogicalPorts", sixgr.util.structGet(arch, "NumPorts", NaN)));
prec.ArchitectureNumWaveformColumns = double(sixgr.util.structGet(arch, "NumWaveformColumns", sixgr.util.structGet(arch, "NumPorts", NaN)));
prec.AntennaArchitecture = string(sixgr.util.structGet(arch, "Architecture", ""));
prec.WaveformDomain = string(sixgr.util.structGet(arch, "WaveformDomain", "logical_port"));
prec.PortCountSource = string(sixgr.util.structGet(arch, "PortCountSource", ""));
prec.RFChainCountSource = string(sixgr.util.structGet(arch, "RFChainCountSource", ""));
prec.PortToElementMatrix = sixgr.util.structGet(arch, "PortToElementMatrix", []);
prec.ElementToPortMatrix = sixgr.util.structGet(arch, "ElementToPortMatrix", []);
prec.PortToRFChainMatrix = sixgr.util.structGet(arch, "PortToRFChainMatrix", []);
prec.RFChainToPortMatrix = sixgr.util.structGet(arch, "RFChainToPortMatrix", []);
prec.AnalogPrecoderMatrix = sixgr.util.structGet(arch, "AnalogPrecoderMatrix", []);
prec.DigitalPortToRFChainMatrix = sixgr.util.structGet(arch, "DigitalPortToRFChainMatrix", []);
end

function prec = localApplyHybridElementDomainPrecoder(prec, arch, nLayers)
if ~isfield(prec, "MatrixLogicalPorts") || isempty(prec.MatrixLogicalPorts)
    prec.MatrixLogicalPorts = prec.MatrixPorts;
end
prec.NumLogicalPorts = double(size(prec.MatrixLogicalPorts, 1));
prec.NumWaveformColumns = double(size(prec.MatrixPorts, 1));
if ~logical(sixgr.util.structGet(arch, "HybridBeamformingEnabled", false))
    return;
end
elementToPort = double(sixgr.util.structGet(arch, "HybridElementToPortMatrix", ...
    sixgr.util.structGet(arch, "PortToElementMatrix", [])));
if isempty(elementToPort) || ~ismatrix(elementToPort)
    error("sixgr:phy:ul:PUSCHPrecoding:HybridMatrixMissing", ...
        "Hybrid PUSCH precoding requires an element-by-logical-port RF/baseband matrix.");
end
if size(elementToPort, 2) ~= size(prec.MatrixLogicalPorts, 1)
    error("sixgr:phy:ul:PUSCHPrecoding:HybridLogicalPortMismatch", ...
        "Hybrid element matrix is %dx%d but logical PUSCH precoder is %dx%d.", ...
        size(elementToPort, 1), size(elementToPort, 2), size(prec.MatrixLogicalPorts, 1), size(prec.MatrixLogicalPorts, 2));
end
if size(prec.MatrixLogicalPorts, 2) ~= nLayers
    error("sixgr:phy:ul:PUSCHPrecoding:HybridLayerMismatch", ...
        "Hybrid logical PUSCH precoder must have NumLayers=%d columns.", nLayers);
end
prec.MatrixPorts = elementToPort * double(prec.MatrixLogicalPorts);
prec.MatrixRows = double(size(prec.MatrixPorts, 1));
prec.MatrixCols = double(size(prec.MatrixPorts, 2));
prec.NumPorts = double(size(prec.MatrixPorts, 1));
prec.NumWaveformColumns = double(size(prec.MatrixPorts, 1));
prec.HybridBeamformingApplied = true;
prec.HybridElementDomainApplied = true;
prec.HybridElementToPortMatrix = elementToPort;
prec.HybridAnalogPrecoderMatrix = sixgr.util.structGet(arch, "AnalogPrecoderMatrix", []);
prec.HybridDigitalPortToRFChainMatrix = sixgr.util.structGet(arch, "DigitalPortToRFChainMatrix", []);
prec.HybridEquation = "X_elem=X_logical*(F_RF*F_BB)'', F_RF columns unit-norm";
prec.BeamformingApplied = true;
end

function prec = localAttachPowerInfo(prec, Wports, nLayers, normalizationConvention)
Wports = double(Wports);
traceWWH = real(trace(Wports * Wports'));
traceTarget = localNormalizationTraceTarget(normalizationConvention, nLayers, traceWWH);
if isempty(Wports)
    gramError = NaN;
else
    gramError = norm(Wports' * Wports - eye(size(Wports, 2)), "fro");
end
if isfinite(traceWWH) && traceWWH > 0 && isfinite(traceTarget) && traceTarget > 0
    powerScale = sqrt(traceTarget ./ traceWWH);
    Wpower = Wports .* powerScale;
    normalizedTrace = real(trace(Wpower * Wpower'));
else
    powerScale = NaN;
    Wpower = Wports;
    normalizedTrace = NaN;
end
prec.PrecoderTraceWWH = double(traceWWH);
prec.PrecoderRawTraceWWH = double(traceWWH);
prec.PrecoderTraceTarget = traceTarget;
prec.PrecoderTraceError = double(abs(traceWWH - traceTarget));
prec.PrecoderLayerGramFroError = double(gramError);
prec.PrecoderPowerScale = double(powerScale);
prec.PowerNormalizedMatrixPorts = Wpower;
prec.PrecoderNormalizedTraceWWH = double(normalizedTrace);
prec.PrecoderNormalizedTraceError = double(abs(normalizedTrace - traceTarget));
prec.TotalPowerPreservationEquation = ...
    "trace((alpha*W)*(alpha*W)'')=normalization_target";
prec.TotalPowerPreservingTrace = logical(isfinite(traceWWH) && abs(traceWWH - traceTarget) <= 1e-12 * max(1, traceTarget));
prec.TotalPowerPreservingNormalizedTrace = logical(isfinite(normalizedTrace) && abs(normalizedTrace - traceTarget) <= 1e-12 * max(1, traceTarget));
end
function localValidateCodebookInputs(nLayers, nPorts, tpmi)
if ~(isscalar(tpmi) && isfinite(tpmi) && tpmi >= 0 && abs(tpmi - round(tpmi)) < 1e-9)
    error("sixgr:phy:ul:PUSCHPrecoding:BadTPMI", ...
        "PUSCH codebook TransmissionScheme requires a finite non-negative integer TPMI.");
end
if nPorts < nLayers
    error("sixgr:phy:ul:PUSCHPrecoding:PortsLessThanLayers", ...
        "PUSCH codebook requires NumAntennaPorts >= NumLayers. Got ports=%d layers=%d.", ...
        round(double(nPorts)), round(double(nLayers)));
end
allowedPorts = [1 2 4 8];
if ~any(round(double(nPorts)) == allowedPorts)
    error("sixgr:phy:ul:PUSCHPrecoding:BadNumAntennaPorts", ...
        "PUSCH codebook NumAntennaPorts must be one of [1 2 4 8]. Got %d.", round(double(nPorts)));
end
end

function value = localPositiveInteger(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value >= 1 && abs(value - round(value)) < 1e-9)
    error("sixgr:phy:ul:PUSCHPrecoding:BadInteger", ...
        "%s must be a positive integer scalar.", char(string(name)));
end
value = round(value);
end

function W = localRectIdentity(nPorts, nLayers, normalizationConvention)
W = zeros(max(1, round(double(nPorts))), max(1, round(double(nLayers))));
activeStreams = min(size(W, 1), size(W, 2));
% Non-codebook nrPUSCH emits one unit-gain port per layer. Preserve that
% TS 38.211/Toolbox port mapping exactly; configured UE transmit power is
% applied later by the power-control/amplitude stage, not by silently
% renormalizing the immutable layer-to-port map.
coefficient = 1;
if lower(strtrim(string(normalizationConvention))) == "unit_frobenius"
    coefficient = 1 / sqrt(activeStreams);
end
for i = 1:activeStreams
    W(i, i) = coefficient;
end
end

function convention = localResolveNormalizationConvention(cfg)
convention = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.pusch.precoding.normalizationConvention", ...
    sixgr.util.structGet(cfg, "phy.pusch.precoderNormalizationConvention", ...
    sixgr.util.structGet(cfg, "pusch.precoder_normalization_convention", ...
    "semi_unitary"))))));
aliases = struct( ...
    "unit_total_power", "unit_frobenius", ...
    "equal_per_layer_unit_total_power", "unit_frobenius", ...
    "per_layer_unit_power", "semi_unitary");
field = matlab.lang.makeValidName(char(convention));
if isfield(aliases, field)
    convention = string(aliases.(field));
end
if ~any(convention == ["unit_frobenius","semi_unitary","explicit_no_normalization"])
    error("sixgr:mimo:PrecoderNormalizationConventionUnsupported", ...
        "Unsupported PUSCH precoder normalization convention '%s'.", convention);
end
end

function target = localNormalizationTraceTarget(convention, nLayers, observed)
switch lower(strtrim(string(convention)))
    case "unit_frobenius"
        target = 1;
    case "semi_unitary"
        target = double(nLayers);
    otherwise
        target = double(observed);
end
end

function [W, source] = localResolveConfiguredLogicalPrecoder( ...
        cfg, nPorts, nLayers, normalizationConvention)
W = [];
source = "";
paths = ["phy.pusch.precoding.matrix", "phy.pusch.precodingMatrix", "phy.pusch.W"];
for path = paths
    raw = sixgr.util.structGet(cfg, path, []);
    if isempty(raw)
        continue;
    end
    if ~isnumeric(raw) || ~ismatrix(raw)
        error("sixgr:phy:ul:PUSCHPrecoding:BadConfiguredMatrix", ...
            "Configured %s must be a finite numeric Nport-by-Nlayer matrix.", path);
    end
    raw = double(raw);
    if isequal(size(raw), [nPorts nLayers])
        W = raw;
    elseif isequal(size(raw), [nLayers nPorts]) && nPorts ~= nLayers
        W = raw.';
    else
        error("sixgr:phy:ul:PUSCHPrecoding:ConfiguredMatrixShapeMismatch", ...
            "Configured %s has shape %s; expected %dx%d Nport-by-Nlayer.", ...
            path, mat2str(size(raw)), nPorts, nLayers);
    end
    sixgr.phy.mimo.MatrixContract.validate(W, nPorts, nLayers, ...
        "NormalizationConvention", normalizationConvention);
    source = "configured_noncodebook_logical_precoder:" + path;
    return;
end
end

function beamIndices = localActiveCodebookPorts(Wtx)
portPower = sum(abs(double(Wtx)).^2, 1, "omitnan");
threshold = eps(max([portPower(:); 1])) * 16;
beamIndices = find(isfinite(portPower) & portPower > threshold);
end

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    raw = obj.(propName);
catch
    return;
end
if isempty(raw)
    return;
end
value = raw;
end
