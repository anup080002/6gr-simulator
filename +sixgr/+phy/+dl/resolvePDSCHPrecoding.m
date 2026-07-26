function prec = resolvePDSCHPrecoding(pdsch, cfg, varargin)
%RESOLVEPDSCHPRECODING Normalize the explicit PDSCH precoding contract.
%
%   PREC = sixgr.phy.dl.resolvePDSCHPrecoding(PDSCH, CFG) keeps the 1x1
%   path on a direct map and enables explicit wideband or PRG-bundled
%   precoding for multi-layer or explicitly configured transmissions.

ip = inputParser;
ip.addParameter("PrecodingMatrix", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("NormalizeW", [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("FixedReferenceMode", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;
strictMIMO = logical(sixgr.util.structGet(cfg,"mimo.strict", ...
    sixgr.util.structGet(cfg,"phy.mimo.strict",false)));

nLayers = double(pdsch.NumLayers);
nCodewords = localNumCodewords(pdsch, nLayers);
arch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg, "bs", ...
    "Signal", "PDSCH", "MinimumPorts", max(1, nLayers));
arch = localCapPDSCHLogicalArchitecture(arch, nLayers);

prec = struct();
prec.Active = false;
prec.Mode = "siso-bypass";
prec.Source = "none";
prec.ApplicationStage = "none";
prec.NormalizeW = false;
prec.NumLayers = nLayers;
prec.NumPorts = nLayers;
prec.NumLogicalPorts = nLayers;
prec.NumWaveformColumns = nLayers;
prec.NumCodewords = nCodewords;
prec.WidebandOnly = true;
prec.PMI = NaN;
prec.PMIType = "";
prec.CodebookMode = "";
prec.BeamIndices = [];
prec.MatrixRows = max(nLayers, 1);
prec.MatrixCols = max(nLayers, 1);
prec.MatrixPorts = eye(max(nLayers, 1));
prec.MatrixPortsPerPRG = reshape(eye(max(nLayers, 1)), ...
    [max(nLayers, 1), max(nLayers, 1), 1]);
prec.MatrixLogicalPorts = prec.MatrixPorts;
prec.MatrixLogicalPortsPerPRG = prec.MatrixPortsPerPRG;
prec.MatrixNR = reshape(eye(max(nLayers, 1)), [max(nLayers, 1), max(nLayers, 1), 1]);
prec.MatrixLogicalNR = prec.MatrixNR;
prec.ChannelMatrixNR = permute(prec.MatrixNR, [2 1 3]);
prec.NumPRG = 1;
prec.HybridBeamformingApplied = false;
prec.HybridElementDomainApplied = false;
prec.HybridAnalogPrecoderMatrix = [];
prec.HybridDigitalPortToRFChainMatrix = [];
prec.HybridElementToPortMatrix = [];
prec.StrictMIMO = strictMIMO;
prec.SelectedMatrixSHA256 = "";
prec.AppliedMatrixSHA256 = "";
prec.MatrixRegenerated = false;
prec.Orientation = "Nport_by_Nlayer";
prec.ActiveTCIStateID = NaN;
prec = localAttachArchitecture(prec, arch);
prec = localAttachPowerInfo(prec, prec.MatrixPorts, nLayers);

localAssertPDSCHCodewordLayerScope(nLayers, nCodewords);

Wcfg = opt.PrecodingMatrix;
if isempty(Wcfg)
    Wcfg = sixgr.util.structGet(cfg, "phy.pdsch.precoding.matrix", []);
end
if isempty(Wcfg)
    Wcfg = sixgr.util.structGet(cfg, "phy.pdsch.precodingMatrix", []);
end
if isempty(Wcfg)
    Wcfg = sixgr.util.structGet(cfg, "phy.pdsch.W", []);
end

requestedPorts = localResolvePDSCHRequestedPorts(cfg);
portsRequestedByConfig = ~isempty(requestedPorts);
explicitPorts = [];
if isempty(requestedPorts) && ~isempty(Wcfg) && localExplicitMatrixHasLayerShape(Wcfg, nLayers)
    explicitPorts = localExplicitMatrixPortCount(Wcfg, nLayers);
    if ~isempty(explicitPorts) && explicitPorts <= localMaxNRLogicalPDSCHPorts()
        requestedPorts = explicitPorts;
    end
end
if isempty(requestedPorts)
    requestedPorts = double(arch.NumPorts);
end
requestedPorts = max(nLayers, round(double(requestedPorts)));
if ~portsRequestedByConfig && ~isempty(explicitPorts) && explicitPorts > localMaxNRLogicalPDSCHPorts()
    error("sixgr:phy:dl:PDSCHPrecoding:ExplicitMatrixPortCountUnsupported", ...
        "Explicit matrix has %d ports, exceeding the supported logical-port count.", ...
        explicitPorts);
end

if ~isempty(Wcfg) && ~localExplicitMatrixHasLayerShape(Wcfg, nLayers)
    if logical(opt.FixedReferenceMode)
        sz = size(Wcfg);
        error("sixgr:phy:dl:PDSCHPrecoding:ExplicitMatrixLayerMismatch", ...
            "Fixed-reference PDSCH precoding requires the frozen explicit matrix to be Nports-by-Nlayers or Nlayers-by-Nports. Got %dx%d for %d layer(s).", ...
            sz(1), sz(2), nLayers);
    else
        sz = size(Wcfg);
        error("sixgr:phy:dl:PDSCHPrecoding:StaleExplicitMatrixContext", ...
            ["Explicit PDSCH precoding matrix is %dx%d for %d layer(s). " ...
            "An available PMI does not authorize discarding or replacing it."], ...
            sz(1), sz(2), nLayers);
    end
end

if isempty(Wcfg)
    if strictMIMO && ~(nLayers == 1 && requestedPorts == 1)
        error("sixgr:mimo:MissingAppliedPrecoder", ...
            "Strict multi-port PDSCH requires the scheduler-selected immutable Nport-by-Nlayer matrix.");
    end
    [Wcfg, pmiMeta] = localResolvePMIPrecodingMatrix(cfg, nLayers, requestedPorts);
else
    pmiMeta = localResolveExplicitMatrixMetadata(cfg, Wcfg, nLayers, requestedPorts);
end

normalizeW = opt.NormalizeW;
if isempty(normalizeW)
    normalizeW = logical(sixgr.util.structGet(cfg, "phy.pdsch.normalizePrecodingMatrix", ~strictMIMO));
end
if strictMIMO && normalizeW
    error("sixgr:mimo:PrecoderNormalizationMismatch", ...
        "Strict PDSCH must apply the selected matrix unchanged; runtime normalization is forbidden.");
end

if isempty(Wcfg)
    if nLayers == 1 && requestedPorts == 1
        if ~logical(sixgr.util.structGet(arch, "HybridBeamformingEnabled", false)) && ~strictMIMO
            prec.NormalizeW = normalizeW;
            return;
        end
        Wports = eye(1);
        source = "identity";
    elseif requestedPorts ~= nLayers
        error("sixgr:phy:dl:PDSCHPrecoding:NumPortsNeedsMatrix", ...
            "Requested %d PDSCH port(s) for %d layer(s). Provide an explicit PrecodingMatrix or PMI/TPMI for multi-port DL precoding.", ...
            requestedPorts, nLayers);
    else
        Wports = eye(nLayers);
        source = "identity";
    end
else
    WportsPerPRG = localNormalizeExplicitMatrixPages(Wcfg, nLayers, normalizeW, strictMIMO);
    Wports = WportsPerPRG(:, :, 1);
    if isstruct(pmiMeta) && isfield(pmiMeta, "Source") && strlength(string(pmiMeta.Source)) > 0
        source = string(pmiMeta.Source);
    else
        source = "explicit-matrix";
    end
end

if size(Wports, 2) ~= nLayers
    error("sixgr:phy:dl:PDSCHPrecoding:DimMismatch", ...
        "Resolved precoding matrix must be Nports-by-Nlayers. Got %dx%d for %d layer(s).", ...
        size(Wports, 1), size(Wports, 2), nLayers);
end

if size(Wports, 1) < nLayers
    error("sixgr:phy:dl:PDSCHPrecoding:TooFewPorts", ...
        "Explicit PDSCH precoding requires NumPorts >= NumLayers. Got %d port(s) for %d layer(s).", ...
        size(Wports, 1), nLayers);
end

if ~isempty(requestedPorts) && size(Wports, 1) ~= requestedPorts
    error("sixgr:phy:dl:PDSCHPrecoding:NumPortsMismatch", ...
        "PrecodingMatrix resolves to %d port(s), but cfg.phy.pdsch.numPorts/nPorts requests %d.", ...
        size(Wports, 1), requestedPorts);
end
WlogicalPorts = Wports;
if ~exist("WportsPerPRG", "var")
    WportsPerPRG = reshape(Wports, [size(Wports, 1), size(Wports, 2), 1]);
end
WlogicalPortsPerPRG = WportsPerPRG;
if size(WportsPerPRG, 3) > 1 && ...
        logical(sixgr.util.structGet(arch, "HybridBeamformingEnabled", false))
    error("sixgr:phy:dl:PDSCHPrecoding:PRGHybridUnsupported", ...
        "PRG-bundled PDSCH precoding is not supported with hybrid element-domain expansion.");
end
[Wports, hybridMeta] = localApplyHybridElementDomainPrecoder(WlogicalPorts, arch, nLayers);
if size(WlogicalPortsPerPRG, 3) == 1
    WportsPerPRG = reshape(Wports, [size(Wports, 1), size(Wports, 2), 1]);
end
if logical(sixgr.util.structGet(hybridMeta, "Applied", false))
    source = string(source) + "+hybrid-rf-element-domain";
end

dmrsPorts = localDMRSPortSet(pdsch, nLayers);
if numel(dmrsPorts) ~= nLayers || any(~isfinite(dmrsPorts)) || ...
        any(dmrsPorts ~= fix(dmrsPorts)) || any(dmrsPorts < 0) || ...
        numel(unique(dmrsPorts)) ~= numel(dmrsPorts)
    error("sixgr:phy:dl:PDSCHPrecoding:DMRSPortSetUnsupported", ...
        "Explicit PDSCH precoding requires one unique logical DM-RS port per layer.");
end

if exist("nrPDSCHPrecode", "file") ~= 2
    error("sixgr:phy:dl:PDSCHPrecoding:Missing5G", ...
        "nrPDSCHPrecode is required for explicit downlink precoding.");
end

prec.Active = true;
if size(WportsPerPRG, 3) > 1
    prec.Mode = "explicit-prg-bundled";
else
    prec.Mode = "explicit-wideband";
end
prec.Source = source;
prec.ApplicationStage = "nrPDSCHPrecode_before_RE_mapping";
prec.NormalizeW = normalizeW;
prec.NumPorts = size(Wports, 1);
prec.NumLogicalPorts = size(WlogicalPorts, 1);
prec.NumWaveformColumns = size(Wports, 1);
prec.MatrixRows = size(Wports, 1);
prec.MatrixCols = size(Wports, 2);
prec.MatrixPorts = Wports;
prec.MatrixPortsPerPRG = WportsPerPRG;
prec.MatrixLogicalPorts = WlogicalPorts;
prec.MatrixLogicalPortsPerPRG = WlogicalPortsPerPRG;
prec.MatrixNR = permute(WportsPerPRG, [2 1 3]);
prec.MatrixLogicalNR = permute(WlogicalPortsPerPRG, [2 1 3]);
prec.ChannelMatrixNR = permute(prec.MatrixNR, [2 1 3]);
prec.NumPRG = size(WportsPerPRG, 3);
prec.WidebandOnly = prec.NumPRG == 1;
prec.HybridBeamformingApplied = logical(sixgr.util.structGet(hybridMeta, "Applied", false));
prec.HybridElementDomainApplied = logical(sixgr.util.structGet(hybridMeta, "ElementDomainApplied", false));
prec.HybridAnalogPrecoderMatrix = sixgr.util.structGet(hybridMeta, "AnalogPrecoderMatrix", []);
prec.HybridDigitalPortToRFChainMatrix = sixgr.util.structGet(hybridMeta, "DigitalPortToRFChainMatrix", []);
prec.HybridElementToPortMatrix = sixgr.util.structGet(hybridMeta, "ElementToPortMatrix", []);
prec.HybridEquation = string(sixgr.util.structGet(hybridMeta, "Equation", ""));
prec = localAttachArchitecture(prec, arch);
prec = localAttachPowerInfo(prec, Wports, nLayers);
prec = localAttachPRGPowerInfo(prec, WportsPerPRG, nLayers);
if strictMIMO
    for prg = 1:size(WportsPerPRG,3)
        sixgr.phy.mimo.MatrixContract.validate( ...
            WportsPerPRG(:,:,prg),size(WportsPerPRG,1),nLayers);
    end
    selectedDigest = string(sixgr.util.structGet(cfg, ...
        "phy.pdsch.selectedPrecoderSHA256",""));
    appliedDigest = sixgr.phy.mimo.MatrixContract.digest(WportsPerPRG);
    if strlength(selectedDigest) == 0
        error("sixgr:mimo:MissingAppliedPrecoder", ...
            "Strict PDSCH requires the scheduler-selected matrix SHA-256 identity.");
    end
    if ~strcmpi(selectedDigest,appliedDigest)
        error("sixgr:mimo:PrecoderDigestMismatch", ...
            "Selected and applied PDSCH precoder matrix identities differ.");
    end
    prec.SelectedMatrixSHA256 = selectedDigest;
    prec.AppliedMatrixSHA256 = appliedDigest;
    tciState = double(sixgr.util.structGet(cfg,"phy.pdsch.activeTCIStateID",NaN));
    requireTCI = logical(sixgr.util.structGet(cfg,"phy.mimo.requireActiveTCIState",false));
    if requireTCI && ~isfinite(tciState)
        error("sixgr:mimo:InactiveTCIState", ...
            "Strict beamformed PDSCH requires a decoded active TCI state.");
    end
    prec.ActiveTCIStateID = tciState;
    prec.PrecoderTraceTarget = 1;
    prec.PrecoderTraceError = abs(real(trace(Wports*Wports'))-1);
    prec.TotalPowerPreservingTrace = prec.PrecoderTraceError <= 1e-10;
    prec.NormativeNormalizationPreserved = true;
end
if isstruct(pmiMeta)
    if isfield(pmiMeta, "PMI")
        prec.PMI = double(pmiMeta.PMI);
    end
    if isfield(pmiMeta, "PMIType")
        prec.PMIType = string(pmiMeta.PMIType);
    end
    if isfield(pmiMeta, "CodebookMode")
        prec.CodebookMode = string(pmiMeta.CodebookMode);
    end
    if isfield(pmiMeta, "BeamIndices")
        prec.BeamIndices = double(pmiMeta.BeamIndices);
    end
end

end

function requestedPorts = localResolvePDSCHRequestedPorts(cfg)
requestedPorts = [];
paths = ["phy.pdsch.numPorts", "phy.pdsch.nPorts", "phy.pdsch.NumAntennaPorts", "phy.pdsch.numAntennaPorts"];
for i = 1:numel(paths)
    value = sixgr.util.structGet(cfg, paths(i), []);
    if isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) >= 1
        candidate = max(1, round(double(value)));
        if candidate <= localMaxNRLogicalPDSCHPorts()
            requestedPorts = candidate;
            return;
        end
    end
end
end

function arch = localCapPDSCHLogicalArchitecture(arch, nLayers)
if ~(isstruct(arch) && ~isempty(fieldnames(arch)))
    return;
end
nLayers = max(1, round(double(nLayers)));
numPorts = double(sixgr.util.structGet(arch, "NumPorts", NaN));
hybridEnabled = logical(sixgr.util.structGet(arch, "HybridBeamformingEnabled", false));
if ~(isfinite(numPorts) && numPorts >= nLayers)
    arch.NumPorts = double(nLayers);
    arch.NumLogicalPorts = double(nLayers);
    arch.NumWaveformColumns = double(nLayers);
    arch.PortCountSource = "logical_pdsch_ports_raised_to_rank";
elseif isfinite(numPorts) && numPorts > localMaxNRLogicalPDSCHPorts() && ~hybridEnabled
    arch.NumPorts = double(nLayers);
    arch.NumLogicalPorts = double(nLayers);
    arch.NumWaveformColumns = double(nLayers);
    arch.PortCountSource = "logical_pdsch_ports_capped_from_element_count";
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

function [Wout, meta] = localApplyHybridElementDomainPrecoder(Wlogical, arch, nLayers)
Wout = Wlogical;
meta = struct( ...
    "Applied", false, ...
    "ElementDomainApplied", false, ...
    "AnalogPrecoderMatrix", [], ...
    "DigitalPortToRFChainMatrix", [], ...
    "ElementToPortMatrix", [], ...
    "Equation", "X_port=S*W_logical''");
if ~logical(sixgr.util.structGet(arch, "HybridBeamformingEnabled", false))
    return;
end
elementToPort = double(sixgr.util.structGet(arch, "HybridElementToPortMatrix", ...
    sixgr.util.structGet(arch, "PortToElementMatrix", [])));
if isempty(elementToPort) || ~ismatrix(elementToPort)
    error("sixgr:phy:dl:PDSCHPrecoding:HybridMatrixMissing", ...
        "Hybrid PDSCH precoding requires an element-by-logical-port RF/baseband matrix.");
end
if size(elementToPort, 2) ~= size(Wlogical, 1)
    error("sixgr:phy:dl:PDSCHPrecoding:HybridLogicalPortMismatch", ...
        "Hybrid element matrix is %dx%d but logical PDSCH precoder is %dx%d.", ...
        size(elementToPort, 1), size(elementToPort, 2), size(Wlogical, 1), size(Wlogical, 2));
end
if size(Wlogical, 2) ~= nLayers
    error("sixgr:phy:dl:PDSCHPrecoding:HybridLayerMismatch", ...
        "Hybrid logical PDSCH precoder must have NumLayers=%d columns.", nLayers);
end
Wout = elementToPort * Wlogical;
if size(Wout, 1) ~= double(sixgr.util.structGet(arch, "NumElements", size(Wout, 1)))
    error("sixgr:phy:dl:PDSCHPrecoding:HybridElementMismatch", ...
        "Hybrid PDSCH precoder produced %d waveform columns but architecture declares %d elements.", ...
        size(Wout, 1), double(sixgr.util.structGet(arch, "NumElements", NaN)));
end
meta.Applied = true;
meta.ElementDomainApplied = true;
meta.AnalogPrecoderMatrix = sixgr.util.structGet(arch, "AnalogPrecoderMatrix", []);
meta.DigitalPortToRFChainMatrix = sixgr.util.structGet(arch, "DigitalPortToRFChainMatrix", []);
meta.ElementToPortMatrix = elementToPort;
meta.Equation = "X_elem=S*(F_RF*F_BB*W_logical)'', F_RF columns unit-norm";
end

function prec = localAttachPowerInfo(prec, Wports, nLayers)
Wports = double(Wports);
traceWWH = real(trace(Wports * Wports'));
traceTarget = double(nLayers);
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
prec.TotalPowerPreservationEquation = "trace((alpha*W)*(alpha*W)'')=NumLayers, alpha=sqrt(NumLayers/trace(W*W''))";
prec.TotalPowerPreservingTrace = logical(isfinite(traceWWH) && abs(traceWWH - traceTarget) <= 1e-12 * max(1, traceTarget));
prec.TotalPowerPreservingNormalizedTrace = logical(isfinite(normalizedTrace) && abs(normalizedTrace - traceTarget) <= 1e-12 * max(1, traceTarget));
end

function prec = localAttachPRGPowerInfo(prec, WportsPerPRG, nLayers)
nPRG = size(WportsPerPRG, 3);
traceValues = zeros(1, nPRG);
gramErrors = zeros(1, nPRG);
for prg = 1:nPRG
    W = double(WportsPerPRG(:, :, prg));
    traceValues(prg) = real(trace(W * W'));
    gramErrors(prg) = norm(W' * W - eye(size(W, 2)), "fro");
end
target = double(nLayers);
tolerance = 1e-12 * max(1, target);
prec.PRGPrecoderTraceWWH = double(traceValues);
prec.PRGPrecoderLayerGramFroError = double(gramErrors);
prec.PRGPrecoderTraceTarget = target;
prec.PRGPrecoderTraceMaxError = double(max(abs(traceValues - target), [], "all"));
prec.AllPRGTotalPowerPreserving = logical(all(abs(traceValues - target) <= tolerance));
prec.PRGBundleContractVersion = "PDSCHPRGPrecoding/v1";
end

function nCodewords = localNumCodewords(pdsch, nLayers)
nCodewords = 1 + (nLayers > 4);
try
    nCodewords = double(pdsch.NumCodewords);
catch
end
end

function localAssertPDSCHCodewordLayerScope(nLayers, nCodewords)
nLayers = round(double(nLayers));
nCodewords = round(double(nCodewords));
if nLayers < 1 || nLayers > 8
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH supports ranks 1-8 in this truth path. Requested NumLayers=%d.", nLayers);
end
expected = 1 + double(nLayers > 4);
if nCodewords ~= expected
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH rank-%d requires NumCodewords=%d by TS 38.211 codeword-to-layer mapping. Requested %d.", ...
        nLayers, expected, nCodewords);
end
end

function tf = localExplicitMatrixHasLayerShape(Wcfg, nLayers)
tf = false;
if isempty(Wcfg)
    return;
end
Wcfg = localSqueezeSingletonPage(Wcfg);
if ndims(Wcfg) > 3
    return;
end
sz = size(Wcfg);
tf = (sz(2) == nLayers && sz(1) >= nLayers) || ...
    (sz(1) == nLayers && sz(2) >= nLayers);
end

function nPorts = localExplicitMatrixPortCount(Wcfg, nLayers)
nPorts = [];
Wcfg = localSqueezeSingletonPage(Wcfg);
if ndims(Wcfg) > 3
    return;
end
sz = size(Wcfg);
if sz(2) == nLayers && sz(1) >= nLayers
    nPorts = sz(1);
elseif sz(1) == nLayers && sz(2) >= nLayers
    nPorts = sz(2);
end
if ~isempty(nPorts)
    nPorts = max(1, round(double(nPorts)));
end
end

function WportsPerPRG = localNormalizeExplicitMatrixPages(Wcfg, nLayers, normalizeW, strictMIMO)
Wcfg = localSqueezeSingletonPage(Wcfg);
if ndims(Wcfg) > 3
    error("sixgr:phy:dl:PDSCHPrecoding:BadPRGMatrixRank", ...
        "Explicit PDSCH precoding must be a 2-D matrix or a 3-D PRG matrix array.");
end
sz = size(Wcfg);
if sz(2) == nLayers && sz(1) >= nLayers
    WportsPerPRG = double(Wcfg);
elseif sz(1) == nLayers && sz(2) >= nLayers
    if strictMIMO
        error("sixgr:mimo:PrecoderDimensionMismatch", ...
            "Strict precoders use Nport-by-Nlayer orientation; transpose guessing is forbidden.");
    end
    WportsPerPRG = permute(double(Wcfg), [2 1 3]);
else
    error("sixgr:phy:dl:PDSCHPrecoding:ExplicitMatrixLayerMismatch", ...
        "Explicit PDSCH precoding must have one matrix dimension equal to NumLayers=%d. Got %s.", ...
        nLayers, mat2str(size(Wcfg)));
end
if ismatrix(WportsPerPRG)
    WportsPerPRG = reshape(WportsPerPRG, ...
        [size(WportsPerPRG, 1), size(WportsPerPRG, 2), 1]);
end
for prg = 1:size(WportsPerPRG, 3)
    [~, pageInfo] = sixgr.phy.mimo.precoder(eye(nLayers), ...
        WportsPerPRG(:, :, prg), "NormalizeW", normalizeW);
    WportsPerPRG(:, :, prg) = double(pageInfo.W);
end
end

function nPorts = localMaxNRLogicalPDSCHPorts()
% Large BS element counts are not logical NR PDSCH waveform ports. If such
% a matrix is supplied without explicit PDSCH port configuration, the
% architecture/default logical port count must drive codebook generation.
nPorts = 32;
end

function tf = localHasFinitePMI(cfg)
tf = false;
paths = ["phy.pdsch.tpmi", "phy.pdsch.TPMI", "phy.pdsch.pmi", "phy.pdsch.PMI"];
for i = 1:numel(paths)
    v = sixgr.util.structGet(cfg, paths(i), []);
    if isnumeric(v) && isscalar(v) && isfinite(double(v))
        tf = true;
        return;
    end
end
end

function dmrsPorts = localDMRSPortSet(pdsch, nLayers)
dmrsPorts = [];
try
    dmrsPorts = double(pdsch.DMRS.DMRSPortSet(:).');
catch
end
if isempty(dmrsPorts)
    dmrsPorts = 0:(nLayers-1);
end
end

function [Wcfg, meta] = localResolvePMIPrecodingMatrix(cfg, nLayers, requestedPorts)
meta = struct();
Wcfg = zeros(0, 0);
tpmi = sixgr.util.structGet(cfg, "phy.pdsch.tpmi", []);
if isempty(tpmi)
    tpmi = sixgr.util.structGet(cfg, "phy.pdsch.TPMI", []);
end
if isempty(tpmi)
    tpmi = sixgr.util.structGet(cfg, "phy.pdsch.pmi", []);
end
if isempty(tpmi)
    tpmi = sixgr.util.structGet(cfg, "phy.pdsch.PMI", []);
end
if isempty(tpmi)
    return;
end
if isnumeric(tpmi) && isscalar(tpmi) && ~isfinite(double(tpmi))
    return;
end

if ~(isnumeric(tpmi) && isscalar(tpmi) && isfinite(tpmi))
    error("sixgr:phy:dl:PDSCHPrecoding:BadTPMI", ...
        "phy.pdsch.PMI/TPMI must be a finite scalar numeric value.");
end

numPorts = requestedPorts;
if isempty(numPorts)
    numPorts = nLayers;
end
numPorts = max(1, round(double(numPorts)));

mode = string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", ""));
if strlength(strtrim(mode)) == 0
    codebookType = lower(string(sixgr.util.structGet(cfg, "phy.csi.codebookType", "type1")));
    switch codebookType
        case "type1"
            mode = "type1_su_mimo";
        case "type2"
            mode = "type2_mu_mimo";
        case "etype2"
            mode = "etype2_candidate";
        otherwise
            mode = "noncodebook";
    end
end
mode = lower(strtrim(mode));
if mode == "noncodebook"
    error("sixgr:phy:dl:PDSCHPrecoding:NonCodebookPMIUnsupported", ...
        "Scalar PMI/TPMI selection is not defined for noncodebook PDSCH precoding.");
end

[candidates, info] = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, numPorts, "Mode", mode);
if isempty(candidates)
    error("sixgr:phy:dl:PDSCHPrecoding:EmptyPMICodebook", ...
        "No PMI/codebook candidates were available for %d port(s), %d layer(s), mode '%s'.", ...
        numPorts, nLayers, mode);
end

pmiIndex = round(double(tpmi));
if pmiIndex < 0 || pmiIndex >= numel(candidates)
    error("sixgr:phy:dl:PDSCHPrecoding:TPMIOutOfRange", ...
        "PMI/TPMI=%d is out of range for mode '%s' with %d candidate(s).", ...
        pmiIndex, mode, numel(candidates));
end

Wcfg = candidates(pmiIndex + 1).W;
meta.Source = "pmi-codebook";
meta.Mode = info.Mode;
meta.PMI = double(pmiIndex);
meta.PMIType = string(candidates(pmiIndex + 1).PMIType);
meta.CodebookMode = string(candidates(pmiIndex + 1).CodebookMode);
meta.BeamIndices = double(candidates(pmiIndex + 1).BeamIndices);
end

function meta = localResolveExplicitMatrixMetadata(cfg, Wcfg, nLayers, requestedPorts)
meta = struct( ...
    "Source", "", ...
    "PMI", NaN, ...
    "PMIType", "", ...
    "CodebookMode", "", ...
    "BeamIndices", []);

userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
userSource = string(sixgr.util.structGet(userMeta, "PrecoderSource", ""));
if strlength(strtrim(userSource)) > 0
    meta.Source = userSource;
else
    meta.Source = "explicit-matrix";
end

beamToken = string(sixgr.util.structGet(userMeta, "BeamIndexSet", ""));
parsedBeamIdx = localParseBeamIndexSet(beamToken);
if ~isempty(parsedBeamIdx)
    meta.BeamIndices = parsedBeamIdx;
end

Wports = localNormalizeExplicitMatrix(Wcfg, nLayers);
if isempty(Wports)
    return;
end
numPorts = requestedPorts;
if isempty(numPorts)
    numPorts = size(Wports, 1);
end
numPorts = max(1, round(double(numPorts)));

mode = string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", ""));
if strlength(strtrim(mode)) == 0
    codebookType = lower(string(sixgr.util.structGet(cfg, "phy.csi.codebookType", "type1")));
    switch codebookType
        case "type1"
            mode = "type1_su_mimo";
        case "type2"
            mode = "type2_mu_mimo";
        case "etype2"
            mode = "etype2_candidate";
        otherwise
            mode = "";
    end
end
mode = lower(strtrim(mode));
if strlength(mode) == 0 || mode == "noncodebook"
    return;
end

try
    [candidates, info] = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, numPorts, "Mode", mode);
catch
    candidates = struct([]);
    info = struct();
end
if isempty(candidates)
    return;
end

matchIdx = NaN;
for i = 1:numel(candidates)
    if localMatricesEquivalent(Wports, candidates(i).W)
        matchIdx = i;
        break;
    end
end
if ~(isfinite(matchIdx) && matchIdx >= 1 && matchIdx <= numel(candidates))
    return;
end

matched = candidates(matchIdx);
meta.PMI = double(matched.PMI);
meta.PMIType = string(matched.PMIType);
meta.CodebookMode = string(matched.CodebookMode);
meta.BeamIndices = double(matched.BeamIndices);
if strlength(strtrim(meta.Source)) == 0 || meta.Source == "explicit-matrix"
    meta.Source = "codebook_dft";
end
if isstruct(info) && isfield(info, "Mode") && strlength(string(info.Mode)) > 0
    meta.CodebookMode = string(info.Mode);
end
end

function Wports = localNormalizeExplicitMatrix(Wcfg, nLayers)
Wports = [];
if isempty(Wcfg)
    return;
end
Wtry = Wcfg;
Wtry = localSqueezeSingletonPage(Wtry);
if ~ismatrix(Wtry)
    return;
end
sz = size(Wtry);
if sz(2) ~= nLayers && sz(1) == nLayers
    Wtry = Wtry.';
end
if size(Wtry, 2) ~= nLayers
    return;
end
if size(Wtry, 1) < nLayers
    return;
end
try
    [~, precInfo] = sixgr.phy.mimo.precoder(eye(nLayers), Wtry, "NormalizeW", true);
    Wports = double(precInfo.W);
catch
    Wports = [];
end
end

function tf = localMatricesEquivalent(Wlhs, Wrhs)
tf = false;
if isempty(Wlhs) || isempty(Wrhs) || ~isequal(size(Wlhs), size(Wrhs))
    return;
end
Wlhs = double(Wlhs);
Wrhs = double(Wrhs);
for c = 1:size(Wlhs, 2)
    lhs = Wlhs(:, c);
    rhs = Wrhs(:, c);
    lhsNorm = norm(lhs);
    rhsNorm = norm(rhs);
    if ~(isfinite(lhsNorm) && lhsNorm > 0 && isfinite(rhsNorm) && rhsNorm > 0)
        return;
    end
    overlap = abs((lhs' * rhs) / (lhsNorm * rhsNorm));
    if ~(isfinite(overlap) && overlap >= (1 - 1e-9))
        return;
    end
end
tf = true;
end

function beamIdx = localParseBeamIndexSet(raw)
beamIdx = [];
raw = string(raw);
if strlength(strtrim(raw)) == 0
    return;
end
tok = regexp(char(raw), "\d+", "match");
if isempty(tok)
    return;
end
beamIdx = unique(round(str2double(string(tok))), "stable");
beamIdx = beamIdx(isfinite(beamIdx) & beamIdx >= 1);
beamIdx = double(beamIdx(:).');
end

function x = localSqueezeSingletonPage(x)
sz = size(x);
if numel(sz) > 2 && all(sz(3:end) == 1)
    x = reshape(x, sz(1), sz(2));
end
end
