function catalog = puschCodebookCatalog(nLayers, nPorts, transformPrecoding)
%PUSCHCODEBOOKCATALOG Exact supported PUSCH TPMI catalog for NR codebook mode.
% The TPMI ranges follow TS 38.211 section 6.3.1.5 for PUSCH codebook
% transmission on 1, 2 or 4 antenna ports. Transform precoding uses the
% same valid (ports,layers,TPMI) catalog; the matrix values are still
% produced by nrPUSCHCodebook in the waveform path.

if nargin < 3
    transformPrecoding = false;
end
nLayers = round(double(nLayers));
nPorts = round(double(nPorts));
transformPrecoding = logical(transformPrecoding);

catalog = struct( ...
    "Valid", false, ...
    "NumLayers", double(nLayers), ...
    "NumPorts", double(nPorts), ...
    "TransformPrecoding", logical(transformPrecoding), ...
    "ValidTPMISet", zeros(1, 0), ...
    "NumTPMICandidates", 0, ...
    "Source", "3GPP_TS_38_211_6_3_1_5_PUSCH_codebook_TPMI_catalog", ...
    "Reason", "");

if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1 && ...
        isscalar(nPorts) && isfinite(nPorts) && nPorts >= 1)
    catalog.Reason = "nonfinite_or_nonpositive_layers_or_ports";
    return;
end
if ~any(nPorts == [1 2 4])
    catalog.Reason = "pusch_codebook_supports_1_2_or_4_antenna_ports";
    return;
end
if nLayers > nPorts
    catalog.Reason = "num_layers_exceeds_num_antenna_ports";
    return;
end

switch nPorts
    case 1
        if nLayers == 1
            validSet = 0;
        else
            validSet = [];
        end
    case 2
        if nLayers == 1
            validSet = 0:5;
        elseif nLayers == 2
            validSet = 0:2;
        else
            validSet = [];
        end
    case 4
        switch nLayers
            case 1
                validSet = 0:27;
            case 2
                validSet = 0:21;
            case 3
                validSet = 0:6;
            case 4
                validSet = 0:4;
            otherwise
                validSet = [];
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
