function catalog = puschCodebookCatalog(nLayers, nPorts, transformPrecoding, codebookType)
%PUSCHCODEBOOKCATALOG Exact supported PUSCH TPMI catalog for NR codebook mode.
% Pinned domain: TS 38.211 V18.8.0 section 6.3.1.5 and the R2026a
% nrPUSCHCodebook family names. Family is applicable only at eight ports,
% where it must be explicit. This is a matrix-domain catalog, not permission
% to use a rank/transform combination in a connected waveform procedure.

narginchk(2, 4);
familyProvided = nargin >= 4;
if nargin < 3
    transformPrecoding = false;
end
if nargin < 4
    codebookType = "";
end

catalog = struct( ...
    "Valid", false, ...
    "NumLayers", NaN, ...
    "NumPorts", NaN, ...
    "TransformPrecoding", false, ...
    "DeclaredCodebookType", "", ...
    "EffectiveCodebookType", "", ...
    "CodebookTypeApplicable", false, ...
    "ValidTPMISet", zeros(1, 0), ...
    "NumTPMICandidates", 0, ...
    "Source", "3GPP_TS_38_211_6_3_1_5_PUSCH_codebook_TPMI_catalog", ...
    "SpecificationVersion", "TS_38.211_V18.8.0", ...
    "NativeAPIContract", "MATLAB_R2026a_nrPUSCHCodebook", ...
    "Reason", "");

if ~(localPositiveInteger(nLayers) && localPositiveInteger(nPorts))
    catalog.Reason = "layers_and_ports_must_be_exact_positive_integers";
    return;
end
if ~((islogical(transformPrecoding) || isnumeric(transformPrecoding)) && ...
        isreal(transformPrecoding) && isscalar(transformPrecoding) && ...
        isfinite(transformPrecoding) && any(transformPrecoding == [0 1]))
    catalog.Reason = "transform_precoding_must_be_scalar_boolean";
    return;
end
if ~(ischar(codebookType) || isstring(codebookType))
    catalog.Reason = "codebook_type_must_be_scalar_text";
    return;
end
codebookType = lower(strtrim(string(codebookType)));
if ~isscalar(codebookType) || ismissing(codebookType)
    catalog.Reason = "codebook_type_must_be_scalar_text";
    return;
end
types = ["codebook1_ng1n4n1", "codebook1_ng1n2n2", ...
    "codebook2", "codebook3", "codebook4"];
if strlength(codebookType) > 0 && ~any(codebookType == types)
    catalog.Reason = "unknown_R2026a_pusch_codebook_type";
    return;
end
nLayers = double(nLayers);
nPorts = double(nPorts);
transformPrecoding = logical(transformPrecoding);
catalog.NumLayers = nLayers;
catalog.NumPorts = nPorts;
catalog.TransformPrecoding = transformPrecoding;
catalog.DeclaredCodebookType = codebookType;
if familyProvided && strlength(codebookType) == 0 && nPorts ~= 8
    catalog.Reason = "missing_explicit_codebook_type";
    return;
end
if ~any(nPorts == [1 2 4 8])
    catalog.Reason = "pusch_codebook_supports_1_2_4_or_8_antenna_ports";
    return;
end
if nLayers > nPorts
    catalog.Reason = "num_layers_exceeds_num_antenna_ports";
    return;
end

if nPorts == 1
    if nLayers == 1
        validSet = 0;
    else
        validSet = [];
    end
elseif nPorts == 2
    if nLayers == 1
        validSet = 0:5;
    elseif nLayers == 2
        validSet = 0:2;
    else
        validSet = [];
    end
elseif nPorts == 4
    maxima = [27 21 6 4];
    if nLayers <= numel(maxima)
        validSet = 0:maxima(nLayers);
    else
        validSet = [];
    end
else
    catalog.CodebookTypeApplicable = true;
    if strlength(codebookType) == 0
        catalog.Reason = "missing_eight_port_codebook_type";
        return;
    end
    catalog.EffectiveCodebookType = codebookType;
    % Tables 9--24, 29--36 and 39--47. Table 47 is not a contiguous
    % zero-origin range: rank-specific extensions must remain exact sets.
    counts = [16 32 24 24 8 8 4 4; ...
              16 32 24 24 8 8 8 8; ...
              33 272 264 68 32 16 8 4; ...
              17 105 305 280 160 80 32 16];
    familyIndex = find(codebookType == types, 1);
    if familyIndex <= 4
        validSet = 0:counts(familyIndex, nLayers)-1;
    else
        sets = {[0:7 255], [8:35 256], [36:91 257], [92:161 258], ...
            162:217, 218:245, 246:253, 254};
        validSet = sets{nLayers};
    end
end

if isempty(validSet)
    catalog.Reason = "unsupported_pusch_codebook_layer_port_combination";
    return;
end
catalog.Valid = true;
catalog.ValidTPMISet = double(validSet);
catalog.NumTPMICandidates = double(numel(validSet));
catalog.Reason = "valid_pusch_codebook_combination";
end

function tf = localPositiveInteger(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 1 && value == fix(value);
end
