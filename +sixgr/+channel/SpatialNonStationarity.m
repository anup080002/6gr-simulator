function vis = SpatialNonStationarity(cfg, varargin)
% sixgr.channel.SpatialNonStationarity
%
% Subarray visibility region generator (spatial non-stationarity) for large
% arrays. This is a lightweight hook that can be used by a CDL/TDL MIMO
% channel post-processing step or by an abstract PHY model.
%
% This function returns a struct describing which clusters are "visible" to
% which Tx/Rx subarrays.
%
% Inputs:
%   cfg : simulator config
%
% Name-value:
%   "NumTxAnt"    : number of Tx antenna elements
%   "NumRxAnt"    : number of Rx antenna elements
%   "NumClusters" : number of clusters (default: 12)
%   "Seed"        : RNG seed (optional)
%
% Output (struct):
%   .enable
%   .numTxSubarrays
%   .numRxSubarrays
%   .numClusters
%   .pVisible
%   .txMask  [numClusters x numTxSubarrays] logical
%   .rxMask  [numClusters x numRxSubarrays] logical
%
% Notes:
%   - This is a configurable placeholder. A full implementation would tie
%     visibility regions to geometry, cluster angles, and array layout.
%   - ASCII-only file.

opt.NumTxAnt = [];
opt.NumRxAnt = [];
opt.NumClusters = 12;
opt.Seed = [];

if mod(numel(varargin),2) ~= 0
    error("SpatialNonStationarity:BadNV","Name-value inputs must come in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    val  = varargin{i+1};
    switch lower(name)
        case {"numtxant","ntx"}
            opt.NumTxAnt = double(val);
        case {"numrxant","nrx"}
            opt.NumRxAnt = double(val);
        case {"numclusters","nclusters"}
            opt.NumClusters = double(val);
        case "seed"
            opt.Seed = val;
        otherwise
            error("SpatialNonStationarity:UnknownOpt","Unknown option: %s", name);
    end
end

enable = logical(sixgr.util.structGet(cfg, "channel.spatialNonStationary.enable", false));
pVisible = double(sixgr.util.structGet(cfg, "channel.spatialNonStationary.pVisible", 0.6));
nTxSub = double(sixgr.util.structGet(cfg, "channel.spatialNonStationary.numTxSubarrays", 1));
nRxSub = double(sixgr.util.structGet(cfg, "channel.spatialNonStationary.numRxSubarrays", 1));

if isempty(opt.NumTxAnt), opt.NumTxAnt = double(sixgr.util.structGet(cfg, "channel.nTxAnt", 1)); end
if isempty(opt.NumRxAnt), opt.NumRxAnt = double(sixgr.util.structGet(cfg, "channel.nRxAnt", 1)); end

% Sanity
nTxSub = max(1, round(nTxSub));
nRxSub = max(1, round(nRxSub));
pVisible = min(max(pVisible,0),1);

% RNG
if isempty(opt.Seed)
    seed = sixgr.util.structGet(cfg, "run.seed", 0);
else
    seed = opt.Seed;
end
rs = RandStream("mt19937ar","Seed",double(seed));

txMask = true(opt.NumClusters, nTxSub);
rxMask = true(opt.NumClusters, nRxSub);

if enable
    txMask = rand(rs, opt.NumClusters, nTxSub) <= pVisible;
    rxMask = rand(rs, opt.NumClusters, nRxSub) <= pVisible;

    % Ensure each cluster is visible to at least one subarray
    for c = 1:opt.NumClusters
        if ~any(txMask(c,:))
            txMask(c, randi(rs, nTxSub)) = true;
        end
        if ~any(rxMask(c,:))
            rxMask(c, randi(rs, nRxSub)) = true;
        end
    end
end

vis = struct();
vis.enable = enable;
vis.pVisible = pVisible;
vis.numTxSubarrays = nTxSub;
vis.numRxSubarrays = nRxSub;
vis.numClusters = opt.NumClusters;
vis.txMask = logical(txMask);
vis.rxMask = logical(rxMask);
vis.note = "Visibility masks are random placeholders; calibrate to geometry for research.";

end
