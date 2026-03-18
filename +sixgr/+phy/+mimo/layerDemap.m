function [sym, info] = layerDemap(layers, varargin)
%LAYERDEMAP NR layer demapping wrapper.
%
%   [SYM,INFO] = sixgr.phy.mimo.layerDemap(LAYERS) converts spatial layers
%   back to a single stream per codeword.
%
%   By default, if NR returns a single codeword (common for nLayers <= 4),
%   this wrapper returns a vector (not a 1x1 cell array) so that simple
%   workflows are convenient:
%       sym = sixgr.phy.mimo.layerDemap(layers);
%
%   If you need the raw cell-array output (1 or 2 codewords), set:
%       sym = sixgr.phy.mimo.layerDemap(layers, "ReturnCell", true);
%
%   This wrapper calls nrLayerDemap when available.
%
%   LAYERS can be:
%     - complex matrix (single codeword), or
%     - cell array of layer matrices {cw1Layers,cw2Layers}

if nargin < 1
    error("sixgr:phy:layerDemap:MissingArgs", "Provide LAYERS.");
end

% ---- options
p = inputParser;
p.addParameter("ReturnCell", false, @(x)islogical(x) && isscalar(x));
p.parse(varargin{:});
returnCell = p.Results.ReturnCell;

% ---- engine
useNR = (exist("nrLayerDemap","file") == 2);
if useNR
    out = nrLayerDemap(layers);
else
    % Minimal fallback for single-codeword (nLayers columns) transpose mapping.
    % This matches the common case and keeps the toolkit functional even if
    % 5G Toolbox is unavailable.
    if iscell(layers)
        error("sixgr:phy:layerDemap:FallbackCell", "Fallback layerDemap does not support cell-array inputs.");
    end
    out = {reshape(layers.', [], 1)};
end

% ---- unwrap for convenience
if returnCell
    sym = out;
else
    if iscell(out) && numel(out) == 1
        sym = out{1};
    else
        sym = out; % 2 codewords -> return cell array
    end
end

info = struct();
info.EngineUsed = ternary(useNR, "nrLayerDemap", "fallback");
info.ReturnCell = returnCell;
info.NumCodewords = (iscell(out) * numel(out)) + (~iscell(out));

end

function y = ternary(cond, a, b)
%TERNARY simple inline conditional.
if cond, y = a; else, y = b; end
end
