function out = generateMultiUESRSGrid(srsCfg, ueIds, varargin)
%GENERATEMULTIUESRSGRID Build simultaneous multi-UE SRS waveform evidence.
%
% The returned composite waveform is produced once from the shared slot grid.
% Per-UE receivers then extract their own SRS resources from that same
% waveform, so orthogonal and collision cases exercise the real mapper,
% OFDM path, detector and channel estimator.

p = inputParser;
p.FunctionName = "sixgr.phy.srs.generateMultiUESRSGrid";
addRequired(p, "srsCfg", @isstruct);
addRequired(p, "ueIds", @(x) isnumeric(x) || isstring(x) || iscellstr(x));
addParameter(p, "Mode", "orthogonal", @(x) ischar(x) || isstring(x));
addParameter(p, "SNRdB", srsCfg.HighSNRdB, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "Seed", srsCfg.Seed + 7100, @(x) isnumeric(x) && isscalar(x));
parse(p, srsCfg, ueIds, varargin{:});
opt = p.Results;

ueIds = double(ueIds(:).');
mode = lower(strtrim(string(opt.Mode)));
if isempty(ueIds)
    error("sixgr:phy:srs:MultiUENoUE", "At least one UE id is required for multi-UE SRS.");
end
if ~ismember(mode, ["orthogonal", "collision"])
    error("sixgr:phy:srs:MultiUEModeUnsupported", ...
        "Multi-UE SRS Mode must be orthogonal or collision.");
end

ueCfgs = repmat(srsCfg, numel(ueIds), 1);
bundles = repmat(localEmptyUEBundle(), numel(ueIds), 1);
for ii = 1:numel(ueIds)
    ueCfgs(ii) = localConfigForUE(srsCfg, ueIds(ii), ii, mode);
    one = sixgr.phy.srs.generateSRSWaveform(ueCfgs(ii));
    bundles(ii).UEId = double(ueIds(ii));
    bundles(ii).ConfigHash = string(ueCfgs(ii).ConfigHash);
    bundles(ii).Waveform = one.Waveform;
    bundles(ii).GridSlots = one.GridSlots;
    bundles(ii).Mapping = one.Mapping;
    bundles(ii).CombOffset = double(ueCfgs(ii).CombOffset);
    bundles(ii).CyclicShift = double(ueCfgs(ii).CyclicShift);
    bundles(ii).SequenceId = double(ueCfgs(ii).SequenceId);
end

[compositeSlots, compositeWaveform, ofdmInfo] = localCompositeWaveform(srsCfg, bundles);
overlap = localOverlapMatrix(bundles);
collisionInjected = mode == "collision";

compositeTx = struct();
compositeTx.Waveform = compositeWaveform;
compositeTx.GridSlots = compositeSlots;
compositeTx.Carrier = srsCfg.ToolboxCarrier;
compositeTx.SRS = srsCfg.ToolboxSRS;
compositeTx.OFDMInfo = ofdmInfo;
compositeTx.ConfigHash = string(srsCfg.ConfigHash);
compositeTx.ExpectedRECount = sum(arrayfun(@(b) height(b.Mapping.ResourceMappingTable), bundles));
compositeTx.ExpectedRBCount = double(srsCfg.NumRB);
compositeTx.ExpectedCoverageStatus = "multi_ue_shared_slot_waveform_superposition";

rows = repmat(localMultiUERow(), numel(ueIds), 1);
for ii = 1:numel(ueIds)
    rx = sixgr.phy.srs.applySRSChannel(compositeTx, ueCfgs(ii), ...
        "SNRdB", double(opt.SNRdB), "TimingOffsetSamples", 0, ...
        "FaultMode", "normal", "Seed", double(opt.Seed) + ii);
    det = sixgr.phy.srs.detectSRSFromULGrid(rx, ueCfgs(ii));
    ch = sixgr.phy.srs.estimateULChannelFromSRS(det, ueCfgs(ii));
    overlapCount = sum(overlap(ii, setdiff(1:numel(ueIds), ii)), "omitnan");
    channelAvailable = logical(sixgr.util.structGet(ch, "SRSChannelEstimateAvailable", false));
    detectionSuccess = logical(sixgr.util.structGet(det, "DetectionSuccess", false));
    nmseDb = double(sixgr.util.structGet(ch, "NMSE_dB", NaN));
    collisionDetected = collisionInjected && overlapCount > 0 && ...
        (~channelAvailable || (isfinite(nmseDb) && nmseDb > double(ueCfgs(ii).ChannelNMSEThresholddB)));
    orthogonalPass = ~collisionInjected && overlapCount == 0 && detectionSuccess && channelAvailable;

    row = localMultiUERow();
    row.RunId = string(srsCfg.RunId);
    row.TrialId = double(ii);
    row.UEId = double(ueIds(ii));
    row.CollisionGroupId = double(1);
    row.ResourceId = double(ueCfgs(ii).ResourceId);
    row.Port = 0;
    row.RBStart = double(ueCfgs(ii).ExpectedRBStart);
    row.NumRB = double(ueCfgs(ii).NumRB);
    row.CyclicShift = double(ueCfgs(ii).CyclicShift);
    row.CombOffset = double(ueCfgs(ii).CombOffset);
    row.CollisionInjected = logical(collisionInjected);
    row.CollisionDetected = logical(collisionDetected);
    row.OrthogonalityPass = logical(orthogonalPass);
    row.ChannelEstimateAvailable = logical(channelAvailable);
    row.DetectionSuccess = logical(detectionSuccess);
    row.DetectionMetric = double(sixgr.util.structGet(det, "DetectionMetric", NaN));
    row.NMSE_dB = double(nmseDb);
    row.OverlapRECount = double(overlapCount);
    if orthogonalPass
        row.Outcome = "orthogonal_resources_separable";
        row.Status = "real_lls_evidence";
        row.FailureReason = "";
    elseif collisionDetected
        row.Outcome = "intentional_collision_detected";
        row.Status = "real_lls_evidence";
        row.FailureReason = "srs_resource_collision";
    else
        row.Outcome = "multi_ue_srs_detection_or_estimation_failed";
        row.Status = "real_lls_evidence";
        row.FailureReason = "multi_ue_srs_expected_effect_not_observed";
    end
    rows(ii) = row;
end

out = struct();
out.UEBundles = bundles;
out.UEConfigs = ueCfgs;
out.NumUEs = double(numel(ueIds));
out.Mode = char(mode);
out.CompositeGridSlots = compositeSlots;
out.CompositeWaveform = compositeWaveform;
out.CompositeOFDMInfo = ofdmInfo;
out.OverlapMatrix = double(overlap);
out.TrialTable = struct2table(rows, "AsArray", true);
out.ConfigHash = string(srsCfg.ConfigHash);
out.TruthStatus = "real_lls_evidence";
end

function cfg = localConfigForUE(baseCfg, ueId, ordinal, mode)
cfg = baseCfg;
cfg.UEId = double(ueId);
if mode == "orthogonal"
    comb = max(1, round(double(baseCfg.CombNumber)));
    cfg.CombOffset = mod(double(baseCfg.CombOffset) + ordinal - 1, comb);
    cfg.CyclicShift = mod(double(baseCfg.CyclicShift) + 2 * (ordinal - 1), 12);
elseif mode == "collision"
    cfg.CombOffset = double(baseCfg.CombOffset);
    cfg.CyclicShift = double(baseCfg.CyclicShift);
end
cfg.SequenceId = mod(double(baseCfg.SequenceId) + 31 * (ordinal - 1) * double(mode == "orthogonal"), 1024);
cfg = localRefreshSRSConfig(cfg);
end

function cfg = localRefreshSRSConfig(cfg)
resourceSet = sixgr.phy.srs.buildSRSResourceSetStrict(cfg);
cfg.ToolboxCarrier = resourceSet.Carrier;
cfg.ToolboxSRS = resourceSet.SRS;
cfg.C_SRS = double(resourceSet.SRS.CSRS);
cfg.B_SRS = double(resourceSet.SRS.BSRS);
cfg.NumRB = double(resourceSet.SRS.NRBPerTransmission);
cfg.ConfigHash = sixgr.phy.srs.hashSRSConfig(cfg);
cfg.StrictValidation = sixgr.phy.srs.validateSRSConfigStrict(cfg);
cfg.ConfigExport = rmfield(cfg, intersect(fieldnames(cfg), ...
    {'ToolboxCarrier','ToolboxSRS','BaseConfig','ConfigExport','StrictValidation'}));
end

function [slots, wave, firstInfo] = localCompositeWaveform(srsCfg, bundles)
slotNumbers = double(srsCfg.ExpectedSlotSet(:).');
P = max(arrayfun(@(b) size(b.GridSlots(1).Grid, 3), bundles));
slots = repmat(struct("Slot", NaN, "Grid", [], "Indices", [], "Symbols", []), numel(slotNumbers), 1);
wave = [];
firstInfo = struct();
for ss = 1:numel(slotNumbers)
    carrier = srsCfg.ToolboxCarrier;
    carrier.NSlot = double(slotNumbers(ss));
    grid = nrResourceGrid(carrier, P);
    idxAll = [];
    symAll = [];
    for uu = 1:numel(bundles)
        gIdx = find([bundles(uu).GridSlots.Slot] == double(slotNumbers(ss)), 1, "first");
        if isempty(gIdx)
            continue;
        end
        oneGrid = bundles(uu).GridSlots(gIdx).Grid;
        if size(oneGrid, 3) < P
            oneGrid(:, :, end+1:P) = 0; %#ok<AGROW>
        end
        grid = grid + oneGrid(:, :, 1:P);
        idxAll = [idxAll; bundles(uu).GridSlots(gIdx).Indices(:)]; %#ok<AGROW>
        symAll = [symAll; bundles(uu).GridSlots(gIdx).Symbols(:)]; %#ok<AGROW>
    end
    [slotWave, info] = nrOFDMModulate(carrier, grid);
    wave = [wave; slotWave]; %#ok<AGROW>
    if ss == 1
        firstInfo = info;
    end
    slots(ss).Slot = double(slotNumbers(ss));
    slots(ss).Grid = grid;
    slots(ss).Indices = idxAll;
    slots(ss).Symbols = symAll;
end
end

function overlap = localOverlapMatrix(bundles)
n = numel(bundles);
overlap = zeros(n, n);
for ii = 1:n
    idxI = double(vertcat(bundles(ii).GridSlots.Indices));
    for jj = 1:n
        idxJ = double(vertcat(bundles(jj).GridSlots.Indices));
        overlap(ii, jj) = double(numel(intersect(idxI(:), idxJ(:))));
    end
end
end

function bundle = localEmptyUEBundle()
bundle = struct("UEId", NaN, "ConfigHash", "", "Waveform", [], "GridSlots", [], ...
    "Mapping", struct(), "CombOffset", NaN, "CyclicShift", NaN, "SequenceId", NaN);
end

function row = localMultiUERow()
row = struct("RunId", "", "TrialId", NaN, "UEId", NaN, "CollisionGroupId", NaN, ...
    "ResourceId", NaN, "Port", NaN, "RBStart", NaN, "NumRB", NaN, ...
    "CyclicShift", NaN, "CombOffset", NaN, "CollisionInjected", false, ...
    "CollisionDetected", false, "OrthogonalityPass", false, ...
    "ChannelEstimateAvailable", false, "DetectionSuccess", false, ...
    "DetectionMetric", NaN, "NMSE_dB", NaN, "OverlapRECount", NaN, ...
    "SharedSlotWaveformSuperposition", true, "WaveformSource", "actual_multi_ue_srs_composite_grid_ofdm", ...
    "Outcome", "", "Status", "", "FailureReason", "");
end
