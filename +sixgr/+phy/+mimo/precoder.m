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
%   Name-value options:
%     "NormalizeW"     : legacy study-only column normalization (default false)
%     "Strict"         : enforce the immutable Phase-07 contract (default false)
%     "ExpectedDigest" : selected matrix digest required in strict mode
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

opts.NormalizeW = false;
opts.Strict = false;
opts.ExpectedDigest = "";
if rem(numel(varargin),2) ~= 0
    error("sixgr:phy:precoder:BadNV", "Name-value arguments must be in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    val  = varargin{i+1};
    switch lower(name)
        case "normalizew"
            opts.NormalizeW = logical(val);
        case "strict"
            opts.Strict = logical(val);
        case "expecteddigest"
            opts.ExpectedDigest = string(val);
        otherwise
            error("sixgr:phy:precoder:BadNV", "Unknown option: %s", name);
    end
end

if iscell(layers)
    % Apply per codeword
    ports = cell(size(layers));
    info = cell(size(layers));
    for k = 1:numel(layers)
        [ports{k}, info{k}] = sixgr.phy.mimo.precoder(layers{k}, W, ...
            "NormalizeW", opts.NormalizeW, "Strict", opts.Strict, ...
            "ExpectedDigest", opts.ExpectedDigest);
    end
    return;
end

layers = layers;
if ~isnumeric(layers)
    error("sixgr:phy:precoder:BadLayers", "LAYERS must be numeric.");
end
if isempty(W)
    if opts.Strict
        error("sixgr:mimo:UnsupportedResearchFallback", ...
            "Strict precoding requires the selected matrix; identity substitution is forbidden.");
    end
    ports = layers;
    info = struct("Mode","identity","nLayers",size(layers,2),"nPorts",size(layers,2), ...
        "NormalizeW",false,"W",eye(size(layers,2), class(layers)));
    return;
end

if ~isnumeric(W)
    error("sixgr:phy:precoder:BadW", "W must be numeric.");
end

[Nsym, nLayers] = size(layers);

% Strict paths accept one orientation only. Transpose guessing is retained
% solely for explicitly non-strict legacy studies.
if size(W,2) == nLayers
    Wuse = W;
elseif ~opts.Strict && size(W,1) == nLayers
    Wuse = W.'; % transpose
else
    error("sixgr:mimo:PrecoderDimensionMismatch", ...
        "W must be exactly Nports-by-Nlayers. Got %dx%d, Nlayers=%d.", ...
        size(W,1), size(W,2), nLayers);
end

if opts.Strict && opts.NormalizeW
    error("sixgr:mimo:PrecoderNormalizationMismatch", ...
        "Strict application cannot mutate a selected precoder by normalization.");
end

% Legacy study-only normalization.
if opts.NormalizeW
    for l = 1:size(Wuse,2)
        nrm = sqrt(sum(abs(Wuse(:,l)).^2));
        if nrm > 0
            Wuse(:,l) = Wuse(:,l) / nrm;
        end
    end
end

if opts.Strict
    matrixInfo = sixgr.phy.mimo.MatrixContract.validate(Wuse, size(Wuse,1), nLayers, ...
        ExpectedDigest=opts.ExpectedDigest);
else
    matrixInfo = struct( ...
        "Orientation", "Nport_by_Nlayer", ...
        "Rows", size(Wuse,1), ...
        "Columns", size(Wuse,2), ...
        "FrobeniusPower", sum(abs(Wuse(:)).^2), ...
        "OrthogonalityError", NaN, ...
        "MatrixSHA256", sixgr.phy.mimo.MatrixContract.digest(Wuse));
end

% Apply: ports(t,:) = layers(t,:) * W.'  (Nsym-by-Nports)
ports = layers * (Wuse.');

info = struct();
info.Mode = "linear";
info.nLayers = nLayers;
info.nPorts = size(Wuse,1);
info.NormalizeW = opts.NormalizeW;
info.Strict = opts.Strict;
info.WSize = [size(Wuse,1) size(Wuse,2)];
info.W = Wuse;
info.Orientation = matrixInfo.Orientation;
info.MatrixSHA256 = matrixInfo.MatrixSHA256;
info.SelectedMatrixSHA256 = string(opts.ExpectedDigest);
info.AppliedMatrixSHA256 = matrixInfo.MatrixSHA256;
info.MatrixRegenerated = false;
info.FrobeniusPower = matrixInfo.FrobeniusPower;

end
