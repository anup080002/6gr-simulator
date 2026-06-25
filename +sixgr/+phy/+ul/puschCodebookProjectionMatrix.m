function [Wlayer, status] = puschCodebookProjectionMatrix(nLayers, nPorts, tpmi)
%PUSCHCODEBOOKPROJECTIONMATRIX NR PUSCH codebook layer-to-port matrix.
%   Wlayer is NumPorts-by-NumLayers. Port-domain symbols are X=S*Wlayer.'
%   and layer-domain symbols are recovered as S=X*conj(Wlayer) for the
%   unit-norm one-layer codebook entries implemented here.

Wlayer = [];
status = "unsupported_pusch_codebook_configuration";
nLayers = round(double(nLayers));
nPorts = round(double(nPorts));
tpmi = round(double(tpmi));
if ~(isscalar(nLayers) && isscalar(nPorts) && isscalar(tpmi) && ...
        isfinite(nLayers) && isfinite(nPorts) && isfinite(tpmi))
    status = "invalid_pusch_codebook_parameters";
    return;
end
if nLayers ~= 1 || nPorts ~= 2
    status = sprintf("unsupported_pusch_codebook_%dports_%dlayers", nPorts, nLayers);
    return;
end

switch tpmi
    case 0
        Wlayer = [1; 0];
    case 1
        Wlayer = [0; 1];
    case 2
        Wlayer = [1; 1] ./ sqrt(2);
    case 3
        Wlayer = [1; -1] ./ sqrt(2);
    case 4
        Wlayer = [1; 1i] ./ sqrt(2);
    case 5
        Wlayer = [1; -1i] ./ sqrt(2);
    otherwise
        status = sprintf("unsupported_pusch_2port_1layer_tpmi_%d", tpmi);
        return;
end
status = "nr_pusch_2port_1layer_codebook_ts38214";
end
