function [layers, info] = layerMap(sym, nLayers)
%LAYERMAP NR layer mapping wrapper.
%
%   [LAYERS,INFO] = sixgr.phy.mimo.layerMap(SYM, NLAYERS) maps a single stream
%   of modulation symbols to spatial layers. This wrapper calls nrLayerMap.
%
%   SYM can be:
%     - complex vector (single codeword), or
%     - cell array of codeword symbol vectors {cw1,cw2} (PDSCH supports up to 2)
%
%   Output LAYERS is whatever nrLayerMap returns (typically a matrix for one
%   codeword, or a cell array for two codewords).

if nargin < 2
    error("sixgr:phy:layerMap:MissingArgs", "Provide SYM and NLAYERS.");
end

if ~(isscalar(nLayers) && isnumeric(nLayers) && nLayers >= 1)
    error("sixgr:phy:layerMap:BadLayers", "NLAYERS must be a positive scalar.");
end
nLayers = double(nLayers);

% Basic validation for single-codeword case
if ~iscell(sym)
    sym = sym(:);
    if rem(numel(sym), nLayers) ~= 0
        error("sixgr:phy:layerMap:LenMismatch", ...
            "Symbol length (%d) must be a multiple of NLAYERS=%d.", numel(sym), nLayers);
    end
end

if exist("nrLayerMap","file") ~= 2
    error("sixgr:phy:layerMap:Missing5G", "nrLayerMap not found (5G Toolbox required).");
end

layers = nrLayerMap(sym, nLayers);

info = struct();
info.EngineUsed = "nrLayerMap";
info.nLayers = nLayers;

end
