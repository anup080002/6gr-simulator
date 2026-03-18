function [pb, info] = PBCH_Recovery(rxSSBGrid, sync, cfg, varargin)
%PBCH_Recovery Recover PBCH and decode BCH from an SS/PBCH block resource grid.
%
%   [pb, info] = sixgr.phy.dl.PBCH_Recovery(rxSSBGrid, sync, cfg)
%
% Inputs:
%   rxSSBGrid : 240x4 or 240x4xNr complex grid (subcarriers x symbols x RxAnt)
%   sync      : struct from sixgr.phy.dl.SSB_Rx containing at least:
%               - NCellID
%               - Lmax (optional)
%   cfg       : config struct (used only for defaults)
%
% Name-Value:
%   "PolarListLength" : default 8
%   "AveragingWindow" : default [0 1]
%   "NoiseVarFloor"   : default 1e-10
%   "Verbose"         : default false
%
% Output pb fields:
%   Ok, ErrFlag, NCellID, SSBIndex, iBar_SSB, v, k_SSB, msbidxoffset,
%   SFN4LSB, HalfFrame, TransportBlock, ScrambledTransportBlock, NoiseVar
%
% Notes:
%   This implementation follows the MathWorks reference flow:
%   nrChannelEstimate -> nrEqualizeMMSE -> nrPBCHDecode -> nrBCHDecode.

% -----------------------------
% Parse inputs
% -----------------------------
p = inputParser;
p.addParameter('PolarListLength', 8);
p.addParameter('AveragingWindow', [0 1]);
p.addParameter('NoiseVarFloor', 1e-10);
p.addParameter('Verbose', false);
p.parse(varargin{:});
opt = p.Results;

% -----------------------------
% Validate rxSSBGrid shape
% -----------------------------
sz = size(rxSSBGrid);
if numel(sz) < 2
    error('rxSSBGrid must be 240x4 or 240x4xNr.');
end
if sz(1) ~= 240 || sz(2) ~= 4
    error('rxSSBGrid must be 240-by-4 or 240-by-4-by-Nr.');
end
if numel(sz) == 2
    rxGrid = reshape(rxSSBGrid, 240, 4, 1);
else
    rxGrid = rxSSBGrid;
end
Nr = size(rxGrid, 3);

% -----------------------------
% Get NCellID and Lmax
% -----------------------------
if isstruct(sync) && isfield(sync, 'NCellID')
    ncellid = double(sync.NCellID);
else
    error('sync must contain NCellID.');
end

Lmax = [];
if isstruct(sync) && isfield(sync, 'Lmax')
    Lmax = double(sync.Lmax);
end
if isempty(Lmax)
    Lmax = sixgr.util.structGet(cfg, 'phy.ssb.Lmax', 8);
    Lmax = double(Lmax);
end
if ~(Lmax == 4 || Lmax == 8 || Lmax == 64)
    % allow other values but cap DMRS search below
    if opt.Verbose
        fprintf('[PBCH] Warning: unexpected Lmax=%g, continuing.\n', Lmax);
    end
end

% PBCH DM-RS only supports ibar_SSB in [0..7]
if Lmax == 4
    ibarCandidates = 0:3;
else
    ibarCandidates = 0:7;
end

% -----------------------------
% Precompute indices
% -----------------------------
dmrsInd = nrPBCHDMRSIndices(ncellid);
sssInd  = nrSSSIndices;
[pbchInd, pbchIndInfo] = nrPBCHIndices(ncellid);

% -----------------------------
% Candidate loop (try all ibar until BCH CRC passes)
% -----------------------------
info = struct();
info.PerCandidate = repmat(struct( ...
    'iBar_SSB', [], ...
    'v', [], ...
    'MetricDMRS', [], ...
    'NoiseVar', [], ...
    'ErrFlag', [], ...
    'msbidxoffset', []), numel(ibarCandidates), 1);

bestIdx = 1;
bestMetric = -Inf;

selected = struct();
selectedFound = false;

for k = 1:numel(ibarCandidates)
    ibar = ibarCandidates(k);

    % v configuration per TS 38.211 and MathWorks example
    if Lmax == 4
        v = mod(ibar, 4);
    else
        v = ibar; % for Lmax=8 or 64, v is 3 LSBs (0..7)
    end

    % DMRS correlation metric (robust, also works when nVar is ~0)
    refDmrs = nrPBCHDMRS(ncellid, ibar);
    rxDmrs = nrExtractResources(dmrsInd, rxGrid); % [Ndmrs x Nr]
    metric = 0;
    for r = 1:Nr
        metric = metric + abs(sum(conj(refDmrs(:)) .* rxDmrs(:, r))).^2;
    end
    if metric > bestMetric
        bestMetric = metric;
        bestIdx = k;
    end

    % Channel estimation using PBCH DM-RS and SSS (as in MathWorks example)
    refGrid = zeros(240, 4);
    refGrid(dmrsInd) = nrPBCHDMRS(ncellid, ibar);
    refGrid(sssInd)  = nrSSS(ncellid);

    try
        [hest, nVar] = nrChannelEstimate(rxGrid, refGrid, ...
            'AveragingWindow', opt.AveragingWindow);
    catch
        % Some versions return 3 outputs; accept that too
        [hest, nVar] = nrChannelEstimate(rxGrid, refGrid);
    end

    nVarUse = max(double(nVar), double(opt.NoiseVarFloor));

    % PBCH equalization
    pbchRx = nrExtractResources(pbchInd, rxGrid);
    pbchHest = nrExtractResources(pbchInd, hest);
    [pbchEq, csi] = nrEqualizeMMSE(pbchRx, pbchHest, nVarUse);

    % CSI replication per bit (same pattern as MathWorks example)
    Qm = pbchIndInfo.G / pbchIndInfo.Gd;
    Qm = round(Qm);
    csiBits = repmat(csi.', Qm, 1);
    csiBits = reshape(csiBits, [], 1);

    % PBCH decode (nrPBCHDecode returns ONE output: LLRs)
    pbchBits = nrPBCHDecode(pbchEq, ncellid, v, nVarUse);
    pbchBits = pbchBits .* csiBits;

    % BCH decode (nrBCHDecode 2nd output is errFlag / CRC)
    [scrblk, errFlag, trblk, sfn4lsb, nHalfFrame, msbidxoffset] = ...
        nrBCHDecode(pbchBits, double(opt.PolarListLength), double(Lmax), ncellid);

    info.PerCandidate(k).iBar_SSB = ibar;
    info.PerCandidate(k).v = v;
    info.PerCandidate(k).MetricDMRS = metric;
    info.PerCandidate(k).NoiseVar = nVarUse;
    info.PerCandidate(k).ErrFlag = errFlag;
    info.PerCandidate(k).msbidxoffset = msbidxoffset;

    if errFlag == 0
        selectedFound = true;
        selected.ibar = ibar;
        selected.v = v;
        selected.metric = metric;
        selected.nVar = nVarUse;
        selected.errFlag = errFlag;
        selected.scrblk = scrblk;
        selected.trblk = trblk;
        selected.sfn4lsb = sfn4lsb;
        selected.nHalfFrame = nHalfFrame;
        selected.msbidxoffset = msbidxoffset;
        break;
    end
end

% If nothing passed CRC, fall back to best DMRS metric candidate to return debug info
if ~selectedFound
    ibar = ibarCandidates(bestIdx);
    if Lmax == 4
        v = mod(ibar, 4);
    else
        v = ibar;
    end

    refGrid = zeros(240, 4);
    refGrid(dmrsInd) = nrPBCHDMRS(ncellid, ibar);
    refGrid(sssInd)  = nrSSS(ncellid);

    try
        [hest, nVar] = nrChannelEstimate(rxGrid, refGrid, ...
            'AveragingWindow', opt.AveragingWindow);
    catch
        [hest, nVar] = nrChannelEstimate(rxGrid, refGrid);
    end
    nVarUse = max(double(nVar), double(opt.NoiseVarFloor));

    pbchRx = nrExtractResources(pbchInd, rxGrid);
    pbchHest = nrExtractResources(pbchInd, hest);
    [pbchEq, csi] = nrEqualizeMMSE(pbchRx, pbchHest, nVarUse);

    Qm = pbchIndInfo.G / pbchIndInfo.Gd;
    Qm = round(Qm);
    csiBits = repmat(csi.', Qm, 1);
    csiBits = reshape(csiBits, [], 1);

    pbchBits = nrPBCHDecode(pbchEq, ncellid, v, nVarUse);
    pbchBits = pbchBits .* csiBits;

    [scrblk, errFlag, trblk, sfn4lsb, nHalfFrame, msbidxoffset] = ...
        nrBCHDecode(pbchBits, double(opt.PolarListLength), double(Lmax), ncellid);

    selected.ibar = ibar;
    selected.v = v;
    selected.metric = bestMetric;
    selected.nVar = nVarUse;
    selected.errFlag = errFlag;
    selected.scrblk = scrblk;
    selected.trblk = trblk;
    selected.sfn4lsb = sfn4lsb;
    selected.nHalfFrame = nHalfFrame;
    selected.msbidxoffset = msbidxoffset;
end

% -----------------------------
% Derive SSBIndex and k_SSB (matches MathWorks example logic)
% -----------------------------
ssbIndex = selected.v;
k_SSB = 0;

if Lmax == 64
    msb = localBitsToInt(selected.msbidxoffset);
    ssbIndex = ssbIndex + msb * 8;
    k_SSB = 0;
else
    k_SSB = double(selected.msbidxoffset) * 16;
end

% -----------------------------
% Pack outputs
% -----------------------------
pb = struct();
pb.Ok = logical(selected.errFlag == 0);
pb.ErrFlag = selected.errFlag;
pb.NCellID = ncellid;

pb.iBar_SSB = selected.ibar;
pb.v = selected.v;
pb.SSBIndex = double(ssbIndex);

pb.k_SSB = double(k_SSB);
pb.msbidxoffset = selected.msbidxoffset;

pb.SFN4LSB = selected.sfn4lsb;
pb.HalfFrame = double(selected.nHalfFrame);

pb.TransportBlock = selected.trblk;
pb.ScrambledTransportBlock = selected.scrblk;
pb.NoiseVar = double(selected.nVar);

info.Selected = selected;
info.Nr = Nr;
info.Lmax = Lmax;

if opt.Verbose
    fprintf('[PBCH] NCellID=%d Lmax=%d selected iBar=%d v=%d ssbIndex=%d ErrFlag=%d\n', ...
        pb.NCellID, Lmax, pb.iBar_SSB, pb.v, pb.SSBIndex, double(pb.ErrFlag));
end

end

% -------------------------------------------------------------------------
function val = localBitsToInt(bits)
% localBitsToInt Convert MSB-first bit vector to integer (no tool dependency).
if isempty(bits)
    val = 0;
    return;
end
b = double(bits(:).');
val = 0;
for i = 1:numel(b)
    val = val + b(i) * 2^(numel(b)-i);
end
end