function prec = resolvePUSCHPrecoding(pusch, cfg)
%RESOLVEPUSCHPRECODING Describe the runtime-applied UL PUSCH precoder.
%
% This function reports only the precoding state carried by the
% nrPUSCHConfig object that is passed into nrPUSCH. Scheduler/config PMI is
% not considered applied until allocREsPUSCH/PUSCH_Tx has materialized it on
% that runtime object.

if nargin < 2 || ~isstruct(cfg)
    cfg = struct();
end

nLayers = double(localObjectValue(pusch, "NumLayers", 1));
if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
nLayers = max(1, round(nLayers));

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
end

prec = struct();
prec.Active = logical(isCodebook && ~transformPrecoding && isfinite(tpmi));
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
prec.BeamIndices = [];
prec.MatrixRows = NaN;
prec.MatrixCols = NaN;
prec.MatrixPorts = [];
prec.ExplicitBeamWeightsApplied = false;
prec.TransformPrecodingApplied = logical(transformPrecoding);
prec.BeamformingApplied = false;
prec.NativeCodebookApplied = false;
prec.BeamIndexDefinition = "";

if transformPrecoding
    prec.Active = true;
    prec.Mode = "transform_precoding";
    prec.Source = "ul_pusch_transform_precoding";
    prec.ApplicationStage = "dft_spread_before_re_mapping";
    prec.NumPorts = double(max(nPorts, nLayers));
    prec.MatrixRows = NaN;
    prec.MatrixCols = NaN;
    return;
end

if ~prec.Active
    return;
end

prec.Mode = "ul_codebook_tpmi";
prec.Source = "ul_pusch_native_codebook_tpmi";
prec.ApplicationStage = "nrPUSCH_native_codebook_precoding_during_modulation";
prec.PMI = double(round(tpmi));
prec.PMIType = "pusch_codebook";
prec.CodebookMode = string(localObjectValue(pusch, "CodebookType", ...
    sixgr.util.structGet(cfg, "phy.pusch.codebookType", "")));
if strlength(strtrim(prec.CodebookMode)) == 0
    prec.CodebookMode = "nr_pusch_codebook";
end
prec.MatrixRows = double(max(nPorts, nLayers));
prec.MatrixCols = double(nLayers);
prec.BeamformingApplied = true;
prec.NativeCodebookApplied = true;
[Wnative, beamIndices] = localNativePUSCHCodebookCandidate(nLayers, nPorts, tpmi, transformPrecoding);
if ~isempty(Wnative)
    prec.MatrixPorts = Wnative.';
    prec.MatrixRows = double(size(prec.MatrixPorts, 1));
    prec.MatrixCols = double(size(prec.MatrixPorts, 2));
    prec.BeamIndices = double(beamIndices);
    prec.BeamIndexDefinition = "nrPUSCHCodebook_nonzero_antenna_port_support";
end
end

function [W, beamIndices] = localNativePUSCHCodebookCandidate(nLayers, nPorts, tpmi, transformPrecoding)
W = [];
beamIndices = [];
if exist("nrPUSCHCodebook", "file") ~= 2
    return;
end
try
    W = nrPUSCHCodebook(max(1, round(double(nLayers))), max(1, round(double(nPorts))), ...
        round(double(tpmi)), logical(transformPrecoding));
catch
    try
        W = nrPUSCHCodebook(max(1, round(double(nLayers))), max(1, round(double(nPorts))), ...
            round(double(tpmi)));
    catch
        W = [];
        return;
    end
end
if isempty(W)
    return;
end
portPower = sum(abs(double(W)).^2, 1, "omitnan");
beamIndices = find(isfinite(portPower) & portPower > (eps(max(portPower, [], "omitnan")) * 16));
if isempty(beamIndices)
    W = [];
end
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
