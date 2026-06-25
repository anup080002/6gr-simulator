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
transformPrecoding = logical(localObjectValue(pusch, "TransformPrecoding", false));
scheme = string(localObjectValue(pusch, "TransmissionScheme", "nonCodebook"));
isCodebook = strcmpi(char(scheme), "codebook");

nPorts = double(localObjectValue(pusch, "NumAntennaPorts", NaN));
if ~(isscalar(nPorts) && isfinite(nPorts) && nPorts >= 1)
    nPorts = double(sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "tx", nLayers));
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
prec.MatrixNR = [];
prec.MatrixRightInverse = [];
prec.ExplicitBeamWeightsApplied = false;
prec.TransformPrecodingApplied = logical(transformPrecoding);
prec.BeamformingApplied = false;
prec.NativeCodebookApplied = false;
prec.BeamIndexDefinition = "";
prec.FixedReferenceMode = logical(opt.FixedReferenceMode);

if transformPrecoding && ~isCodebook
    prec.Mode = "transform_precoding";
    prec.Source = "ul_pusch_transform_precoding";
    prec.ApplicationStage = "dft_spread_before_re_mapping";
    prec.MatrixRows = double(size(prec.MatrixPorts, 1));
    prec.MatrixCols = double(size(prec.MatrixPorts, 2));
    return;
end

if ~isCodebook
    prec.MatrixPorts = localRectIdentity(nLayers, nLayers);
    prec.MatrixRows = NaN;
    prec.MatrixCols = NaN;
    prec.NumPorts = double(nLayers);
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
prec.MatrixNR = Wtx;
prec.MatrixRightInverse = Winv;
prec.MatrixRows = double(size(Wports, 1));
prec.MatrixCols = double(size(Wports, 2));
prec.NumPorts = double(size(Wports, 1));
prec.BeamIndices = double(localActiveCodebookPorts(Wtx));
prec.BeamIndexDefinition = "nrPUSCHCodebook_nonzero_antenna_port_support";
prec.CodebookStatus = string(codebookStatus);
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
