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
%   "CandidateSelection" : crc_aided_legacy or dmrs_metric_then_single_decode
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
p.addParameter('CandidateSelection', "crc_aided_legacy", ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
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
if ~any(Lmax == [4, 8, 64])
    error("sixgr:phy:ia:InvalidLmax", ...
        "PBCH recovery requires Lmax 4, 8, or 64; got %g.", Lmax);
end

% PBCH DM-RS only supports ibar_SSB in [0..7]
if Lmax == 4
    ibarCandidates = 0:3;
else
    ibarCandidates = 0:7;
end
singleDMRSSelection=strcmpi(string(opt.CandidateSelection), ...
    "dmrs_metric_then_single_decode");
if ~singleDMRSSelection&&~strcmpi(string(opt.CandidateSelection),"crc_aided_legacy")
    error("sixgr:phy:ia:PBCHCandidateSelection", ...
        "PBCH CandidateSelection must be crc_aided_legacy or dmrs_metric_then_single_decode.");
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
info.DMRSHypothesesEvaluated = double(numel(ibarCandidates));
info.PolarDecodesAttempted = 0;

if singleDMRSSelection
    rxDmrsPre = nrExtractResources(dmrsInd, rxGrid);
    metricsPre = zeros(size(ibarCandidates));
    for candidateIndex=1:numel(ibarCandidates)
        refPre=nrPBCHDMRS(ncellid,ibarCandidates(candidateIndex));
        for receiveIndex=1:Nr
            metricsPre(candidateIndex)=metricsPre(candidateIndex)+ ...
                abs(sum(conj(refPre(:)).*rxDmrsPre(:,receiveIndex))).^2;
        end
    end
    [~,preselectedIndex]=max(metricsPre);
    ibarCandidates=ibarCandidates([preselectedIndex, ...
        setdiff(1:numel(ibarCandidates),preselectedIndex,"stable")]);
end

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
    evidence = localPBCHReceiverEvidence( ...
        hest, pbchHest, pbchEq, csi, dmrsInd, nVarUse, nVar);

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
    info.PolarDecodesAttempted = info.PolarDecodesAttempted + 1;

    info.PerCandidate(k).iBar_SSB = ibar;
    info.PerCandidate(k).v = v;
    info.PerCandidate(k).MetricDMRS = metric;
    info.PerCandidate(k).NoiseVar = nVarUse;
    info.PerCandidate(k).ErrFlag = errFlag;
    info.PerCandidate(k).msbidxoffset = msbidxoffset;

    if errFlag == 0 || singleDMRSSelection
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
        selected.evidence = evidence;
        selected.hest = hest;
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
    evidence = localPBCHReceiverEvidence( ...
        hest, pbchHest, pbchEq, csi, dmrsInd, nVarUse, nVar);

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
    selected.evidence = evidence;
    selected.hest = hest;
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
pb.PreEqualizationNoiseVariance = double(sixgr.util.structGet( ...
    selected.evidence, "PreEqualizationNoiseVariance", selected.nVar));
pb.PreEqualizationNoiseVarianceDomain = string(sixgr.util.structGet( ...
    selected.evidence, "PreEqualizationNoiseVarianceDomain", ""));
pb.PreEqualizationNoiseVarianceSource = string(sixgr.util.structGet( ...
    selected.evidence, "PreEqualizationNoiseVarianceSource", ""));
pb.PreEqualizationNoiseVarianceFloorApplied = logical(sixgr.util.structGet( ...
    selected.evidence, "PreEqualizationNoiseVarianceFloorApplied", false));
pb.PreEqualizationNoiseVarianceEstimatorValue = double(sixgr.util.structGet( ...
    selected.evidence, "PreEqualizationNoiseVarianceEstimatorValue", NaN));
trblkBits = int8(selected.trblk(:));
scrblkBits = int8(selected.scrblk(:));
pb.BCHTransportBlockNumBits = double(numel(trblkBits));
pb.BCHTransportBlockHex = sixgr.rrc.asn1.bitsToHex(trblkBits);
pb.BCHTransportBlockHash = sixgr.rrc.asn1.asn1SHA256Hex(uint8(trblkBits));
pb.BCHScrambledBlockNumBits = double(numel(scrblkBits));
pb.BCHScrambledBlockHex = sixgr.rrc.asn1.bitsToHex(scrblkBits);
pb.BCHScrambledBlockHash = sixgr.rrc.asn1.asn1SHA256Hex(uint8(scrblkBits));
pb.MIBDecodedBitSource = "nrBCHDecode";
if pb.Ok
    mib = sixgr.phy.broadcast.decodeMIBTransportBlock(trblkBits);
else
    mib = struct();
end
pb.PDCCHConfigSIB1 = double(sixgr.util.structGet(mib, "PDCCHConfigSIB1", NaN));
pb.CORESET0Index = double(sixgr.util.structGet(mib, "CORESET0Index", NaN));
pb.SearchSpaceZero = double(sixgr.util.structGet(mib, "SearchSpaceZero", NaN));
pb.PDCCHConfigSIB1BitString = string(sixgr.util.structGet(mib, "PDCCHConfigSIB1BitString", ""));
pb.PDCCHConfigSIB1BitStart = double(sixgr.util.structGet(mib, "PDCCHConfigSIB1BitStart", NaN));
pb.PDCCHConfigSIB1BitEnd = double(sixgr.util.structGet(mib, "PDCCHConfigSIB1BitEnd", NaN));
pb.MIBDMRSTypeAPosition = double(sixgr.util.structGet(mib, "DMRSTypeAPosition", NaN));
pb.MIBCellBarredBit = double(sixgr.util.structGet(mib, "CellBarredBit", NaN));
pb.MIBIntraFreqReselectionBit = double(sixgr.util.structGet(mib, "IntraFreqReselectionBit", NaN));
pb.MIBSFN4LSBValue = localBitsToInt(selected.sfn4lsb);
pb.MIBSFN4LSBBitString = localBitsToString(selected.sfn4lsb);
pb.MIBHalfFrameBit = localFirstBitScalar(selected.nHalfFrame);
pb.MIBKSSBSubcarrierOffset = double(k_SSB);
pb.MIBSSBIndex = double(ssbIndex);
evidence = sixgr.util.structGet(selected, "evidence", struct());
pb.ChannelEstimateAvailable = logical(sixgr.util.structGet(evidence, "ChannelEstimateAvailable", false));
pb.ChannelEstimateGrid = sixgr.util.structGet(selected,"hest",complex(zeros(0,0,0)));
pb.ChannelEstimateSource = string(sixgr.util.structGet(evidence, "ChannelEstimateSource", ""));
pb.EqualizationAvailable = logical(sixgr.util.structGet(evidence, "EqualizationAvailable", false));
pb.EqualizerType = string(sixgr.util.structGet(evidence, "EqualizerType", ""));
pb.PBCHDecodeAvailable = true;
pb.BCHDecodeAvailable = true;
pb.ReceiverHestSINR_dB = double(sixgr.util.structGet(evidence, "ReceiverHestSINR_dB", NaN));
pb.ReceiverHestSINRSource = string(sixgr.util.structGet(evidence, "ReceiverHestSINRSource", ""));
pb.ReceiverHestSINRValueRole = string(sixgr.util.structGet(evidence, "ReceiverHestSINRValueRole", ""));
pb.ReceiverHestSINRValueStatus = string(sixgr.util.structGet(evidence, "ReceiverHestSINRValueStatus", ""));
pb.ReceiverHestSINRNAReason = string(sixgr.util.structGet(evidence, "ReceiverHestSINRNAReason", ""));
pb.MeasuredTrialSINR_dB = pb.ReceiverHestSINR_dB;
pb.MeasuredTrialSINRSource = pb.ReceiverHestSINRSource;
pb.MeasuredTrialSINRValueRole = "measured";
pb.MeasuredTrialSINRValueStatus = pb.ReceiverHestSINRValueStatus;
pb.MeasuredTrialSINRNAReason = pb.ReceiverHestSINRNAReason;
pb.PostEqSINR_dB = double(sixgr.util.structGet(evidence, "PostEqSINR_dB", NaN));
pb.PostEqSINRAvailable = logical(sixgr.util.structGet( ...
    evidence, "PostEqSINRAvailable", false));
pb.PostEqSINRSource = string(sixgr.util.structGet(evidence, "PostEqSINRSource", ""));
pb.PostEqSINRValueRole = string(sixgr.util.structGet(evidence, "PostEqSINRValueRole", ""));
pb.PostEqSINRValueStatus = string(sixgr.util.structGet(evidence, "PostEqSINRValueStatus", ""));
pb.PostEqSINRNAReason = string(sixgr.util.structGet(evidence, "PostEqSINRNAReason", ""));
pb.PostEqualizationNoiseVariance = double(sixgr.util.structGet( ...
    evidence, "PostEqualizationNoiseVariance", NaN));
pb.PostEqualizationNoiseVarianceDomain = string(sixgr.util.structGet( ...
    evidence, "PostEqualizationNoiseVarianceDomain", ""));
pb.PostEqualizationNoiseVarianceSource = string(sixgr.util.structGet( ...
    evidence, "PostEqualizationNoiseVarianceSource", ""));
pb.StrictReceiverEvidenceOk = logical(pb.ChannelEstimateAvailable) && logical(pb.EqualizationAvailable) && ...
    isfinite(pb.ReceiverHestSINR_dB) && logical(pb.PostEqSINRAvailable) && ...
    isfinite(pb.PostEqSINR_dB) && logical(pb.PBCHDecodeAvailable) && ...
    logical(pb.BCHDecodeAvailable);
if logical(sixgr.util.structGet(cfg, "run.strictMode", false))
    sixgr.phy.rx.validatePBCHNoiseDomainEvidence(pb);
end
if pb.Ok
    pb.DecodedMIBState = sixgr.phy.ia.DecodedMIBState.create( ...
        pb, sixgr.util.structGet(cfg, ...
        "initial_access.configuration_epoch", 1));
else
    pb.DecodedMIBState = struct();
end

info.Selected = selected;
info.Nr = Nr;
info.Lmax = Lmax;

if opt.Verbose
    fprintf('[PBCH] NCellID=%d Lmax=%d selected iBar=%d v=%d ssbIndex=%d ErrFlag=%d\n', ...
        pb.NCellID, Lmax, pb.iBar_SSB, pb.v, pb.SSBIndex, double(pb.ErrFlag));
end

end

% -------------------------------------------------------------------------
function evidence = localPBCHReceiverEvidence( ...
        hest, pbchHest, pbchEq, csi, dmrsInd, nVarUse, nVarEstimator)
evidence = struct( ...
    "ChannelEstimateAvailable", false, ...
    "ChannelEstimateSource", "", ...
    "EqualizationAvailable", false, ...
    "EqualizerType", "MMSE", ...
    "ReceiverHestSINR_dB", NaN, ...
    "ReceiverHestSINRSource", "", ...
    "ReceiverHestSINRValueRole", "unavailable", ...
    "ReceiverHestSINRValueStatus", "unavailable", ...
    "ReceiverHestSINRNAReason", "pbch_dmrs_channel_estimate_not_available", ...
    "PreEqualizationNoiseVariance", NaN, ...
    "PreEqualizationNoiseVarianceDomain", ...
        "resource_grid_pre_equalization_per_receive_branch", ...
    "PreEqualizationNoiseVarianceSource", "", ...
    "PreEqualizationNoiseVarianceFloorApplied", false, ...
    "PreEqualizationNoiseVarianceEstimatorValue", double(nVarEstimator), ...
    "PostEqSINR_dB", NaN, ...
    "PostEqSINRAvailable", false, ...
    "PostEqSINRSource", "", ...
    "PostEqSINRValueRole", "unavailable", ...
    "PostEqSINRValueStatus", "unavailable", ...
    "PostEqSINRNAReason", "pbch_equalizer_channel_or_noise_evidence_not_available", ...
    "PostEqualizationNoiseVariance", NaN, ...
    "PostEqualizationNoiseVarianceDomain", ...
        "unit_energy_pbch_symbol_post_equalization", ...
    "PostEqualizationNoiseVarianceSource", "", ...
    "PostEqSINRAggregation", "harmonic_mean_across_pbch_resource_elements");

evidence.ChannelEstimateAvailable = ~isempty(hest) && all(isfinite(real(hest(:)))) && all(isfinite(imag(hest(:))));
if evidence.ChannelEstimateAvailable
    evidence.ChannelEstimateSource = "nrChannelEstimate_pbch_dmrs_sss";
end
evidence.EqualizationAvailable = ~isempty(pbchEq) && all(isfinite(real(pbchEq(:)))) && ...
    all(isfinite(imag(pbchEq(:)))) && ~isempty(csi) && all(isfinite(double(csi(:))));

noiseVariance = double(nVarUse);
noiseAvailable = isscalar(noiseVariance) && isfinite(noiseVariance) && ...
    noiseVariance > 0;
if noiseAvailable
    estimatorValue = double(nVarEstimator);
    floorApplied = ~(isscalar(estimatorValue) && isfinite(estimatorValue) && ...
        estimatorValue > 0 && estimatorValue >= noiseVariance * (1 - 32 * eps));
    evidence.PreEqualizationNoiseVarianceFloorApplied = floorApplied;
    evidence.PreEqualizationNoiseVariance = noiseVariance;
    if floorApplied
        evidence.PreEqualizationNoiseVarianceSource = ...
            "configured_numeric_floor_after_nrChannelEstimate_pbch_dmrs_sss";
    else
        evidence.PreEqualizationNoiseVarianceSource = ...
            "nrChannelEstimate_pbch_dmrs_sss_grid_noise_variance";
    end
end

if evidence.ChannelEstimateAvailable && noiseAvailable
    try
        hDmrs = nrExtractResources(dmrsInd, hest);
        dmrsChannelPower = sum(abs(hDmrs).^2, 2);
        dmrsChannelPower = dmrsChannelPower( ...
            isfinite(dmrsChannelPower) & dmrsChannelPower > 0);
        if ~isempty(dmrsChannelPower)
            dmrsSINRLinear = mean(dmrsChannelPower) / noiseVariance;
            evidence.ReceiverHestSINR_dB = 10 * log10(dmrsSINRLinear);
            evidence.ReceiverHestSINRSource = ...
                "pbch_dmrs_hest_power_over_nrChannelEstimate_noise_variance";
            evidence.ReceiverHestSINRValueRole = "estimated";
            evidence.ReceiverHestSINRValueStatus = localNoiseStatus( ...
                evidence.PreEqualizationNoiseVarianceFloorApplied);
            evidence.ReceiverHestSINRNAReason = "";
        end
    catch ME
        evidence.ReceiverHestSINRNAReason = "pbch_dmrs_sinr_measurement_failed:" + string(ME.identifier);
    end
end

if evidence.EqualizationAvailable && noiseAvailable && ~isempty(pbchHest)
    channelPower = sum(abs(pbchHest).^2, 2);
    valid = isfinite(channelPower) & channelPower > 0;
    if any(valid)
        postEqNoisePerRE = noiseVariance ./ channelPower(valid);
        postEqNoiseVariance = mean(postEqNoisePerRE);
        if isfinite(postEqNoiseVariance) && postEqNoiseVariance > 0
            evidence.PostEqualizationNoiseVariance = postEqNoiseVariance;
            evidence.PostEqualizationNoiseVarianceSource = ...
                "pbch_mmse_channel_power_and_pre_equalization_noise_variance";
            evidence.PostEqSINR_dB = -10 * log10(postEqNoiseVariance);
            evidence.PostEqSINRAvailable = true;
            evidence.PostEqSINRSource = ...
                "pbch_mmse_harmonic_mean_channel_power_over_pre_equalization_noise";
            evidence.PostEqSINRValueRole = "estimated_post_equalization";
            evidence.PostEqSINRValueStatus = localNoiseStatus( ...
                evidence.PreEqualizationNoiseVarianceFloorApplied);
            evidence.PostEqSINRNAReason = "";
        end
    end
end
end

function status = localNoiseStatus(floorApplied)
if logical(floorApplied)
    status = "LOWER_BOUND_NOISE_FLOOR";
else
    status = "OK";
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

function txt = localBitsToString(bits)
if isempty(bits)
    txt = "";
    return;
end
b = int8(bits(:)) ~= 0;
chars = repmat('0', 1, numel(b));
chars(b) = '1';
txt = string(chars);
end

function val = localFirstBitScalar(bits)
if isempty(bits)
    val = NaN;
    return;
end
vals = double(bits(:));
vals = vals(isfinite(vals));
if isempty(vals)
    val = NaN;
else
    val = double(vals(1) ~= 0);
end
end
