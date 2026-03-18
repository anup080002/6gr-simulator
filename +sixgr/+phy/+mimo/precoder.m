function [ports, info] = precoder(layers, W, varargin)
%PRECODER Apply a linear precoding matrix (digital beamforming).
%
%   PORTS = sixgr.phy.mimo.precoder(LAYERS, W) applies the precoding matrix W
%   to layer symbols.
%
%   Conventions:
%     - LAYERS is Nsym-by-Nlayers (columns are layers).
%     - W is Nports-by-Nlayers (columns correspond to layers).
%     - Output PORTS is Nsym-by-Nports.
%
%   If W is empty, this function returns LAYERS unchanged.
%
%   Name-value options:
%     "NormalizeW" : true (default). Normalizes each column of W to unit norm.
%
%   Notes:
%   - This block is implementation-level precoding. 5G Toolbox does not
%     automatically apply MIMO precoding in nrPDSCH/nrPUSCH, so system modules
%     should call this explicitly when needed.

if nargin < 1
    error("sixgr:phy:precoder:MissingArgs", "Provide LAYERS.");
end
if nargin < 2
    W = [];
end

opts.NormalizeW = true;
if rem(numel(varargin),2) ~= 0
    error("sixgr:phy:precoder:BadNV", "Name-value arguments must be in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    val  = varargin{i+1};
    switch lower(name)
        case "normalizew"
            opts.NormalizeW = logical(val);
        otherwise
            error("sixgr:phy:precoder:BadNV", "Unknown option: %s", name);
    end
end

if iscell(layers)
    % Apply per codeword
    ports = cell(size(layers));
    info = cell(size(layers));
    for k = 1:numel(layers)
        [ports{k}, info{k}] = sixgr.phy.mimo.precoder(layers{k}, W, "NormalizeW", opts.NormalizeW);
    end
    return;
end

layers = layers;
if ~isnumeric(layers)
    error("sixgr:phy:precoder:BadLayers", "LAYERS must be numeric.");
end
if isempty(W)
    ports = layers;
    info = struct("Mode","identity","nLayers",size(layers,2),"nPorts",size(layers,2), ...
        "NormalizeW",false);
    return;
end

if ~isnumeric(W)
    error("sixgr:phy:precoder:BadW", "W must be numeric.");
end

[Nsym, nLayers] = size(layers);

% Accept either Nports-by-Nlayers or Nlayers-by-Nports (transpose)
if size(W,2) == nLayers
    Wuse = W;
elseif size(W,1) == nLayers
    Wuse = W.'; % transpose
else
    error("sixgr:phy:precoder:DimMismatch", ...
        "W must be Nports-by-Nlayers or Nlayers-by-Nports. Got %dx%d, Nlayers=%d.", ...
        size(W,1), size(W,2), nLayers);
end

% Normalize each column (per-layer weights)
if opts.NormalizeW
    for l = 1:size(Wuse,2)
        nrm = sqrt(sum(abs(Wuse(:,l)).^2));
        if nrm > 0
            Wuse(:,l) = Wuse(:,l) / nrm;
        end
    end
end

% Apply: ports(t,:) = layers(t,:) * W.'  (Nsym-by-Nports)
ports = layers * (Wuse.');

info = struct();
info.Mode = "linear";
info.nLayers = nLayers;
info.nPorts = size(Wuse,1);
info.NormalizeW = opts.NormalizeW;
info.WSize = [size(Wuse,1) size(Wuse,2)];

end
