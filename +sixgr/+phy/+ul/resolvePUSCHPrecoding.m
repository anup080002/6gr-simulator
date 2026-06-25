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
ip.parse(varargin{:});
opt = ip.Results;

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
if isCodebook
    tpmi = double(localObjectValue(pusch, "TPMI", NaN));
    localValidateCodebookInputs(nLayers, nPorts, tpmi);
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
prec.BeamIndices = [];
prec.MatrixRows = double(max(nPorts, nLayers));
prec.MatrixCols = double(nLayers);
prec.MatrixPorts = localRectIdentity(max(nPorts, nLayers), nLayers);
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
prec = localAttachArchitecture(prec, arch);
prec = localAttachPowerInfo(prec, prec.MatrixPorts, nLayers);

if transformPrecoding && ~isCodebook
    prec.Mode = "transform_precoding";
    prec.Source = "ul_pusch_transform_precoding";
    prec.ApplicationStage = "dft_spread_before_re_mapping";
    prec = localApplyHybridElementDomainPrecoder(prec, arch, nLayers);
    prec.MatrixRows = double(size(prec.MatrixPorts, 1));
    prec.MatrixCols = double(size(prec.MatrixPorts, 2));
    prec = localAttachPowerInfo(prec, prec.MatrixPorts, nLayers);
    return;
end

if ~isCodebook
    prec.MatrixPorts = localRectIdentity(nLayers, nLayers);
    prec.MatrixLogicalPorts = prec.MatrixPorts;
    prec.MatrixRows = NaN;
    prec.MatrixCols = NaN;
    prec.NumPorts = double(nLayers);
    prec.NumLogicalPorts = double(nLayers);
    prec.NumWaveformColumns = double(nLayers);
    prec = localApplyHybridElementDomainPrecoder(prec, arch, nLayers);
    prec = localAttachPowerInfo(prec, prec.MatrixPorts, nLayers);
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
    prec.CodebookMode = "nr_pusch_codebook";
end
prec.BeamformingApplied = true;
prec.NativeCodebookApplied = true;
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
prec.BeamIndices = double(localActiveCodebookPorts(Wtx));
prec.BeamIndexDefinition = "nrPUSCHCodebook_nonzero_antenna_port_support";
prec.CodebookStatus = string(codebookStatus);
prec = localApplyHybridElementDomainPrecoder(prec, arch, nLayers);
prec = localAttachPowerInfo(prec, prec.MatrixPorts, nLayers);
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
allowedPorts = [1 2 4];
if ~any(round(double(nPorts)) == allowedPorts)
    error("sixgr:phy:ul:PUSCHPrecoding:BadNumAntennaPorts", ...
        "PUSCH codebook NumAntennaPorts must be one of [1 2 4]. Got %d.", round(double(nPorts)));
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

function W = localRectIdentity(nPorts, nLayers)
W = zeros(max(1, round(double(nPorts))), max(1, round(double(nLayers))));
for i = 1:min(size(W, 1), size(W, 2))
    W(i, i) = 1;
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
