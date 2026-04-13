function artifacts = exportLLSLiveMobilityTables(cfg, runFolder, multiUser)
%EXPORTLLSLIVEMOBILITYTABLES Publish LLS mobility and large-scale telemetry tables.
%
% This helper is intentionally large-scale and geometry driven. It does not
% pretend to be a full MAC-scheduler system simulation. Instead, it reuses
% the same large-scale cache, beam selection, and RSRP-based serving-cell
% selection logic used elsewhere in the repo so the live web views can show
% truthful movement, reselection, RSRP, pathloss, and wideband-CQI context
% while a waveform LLS run is progressing.

if nargin < 3 || ~isstruct(multiUser)
    multiUser = struct();
end

artifacts = struct();
layout = sixgr.report.resultLayout(runFolder);

cfgMob = localPrepareMobilityConfig(cfg, multiUser);
cfgLargeScale = localPrepareLargeScaleSidecarConfig(cfgMob);
scenarioName = string(sixgr.util.structGet(cfgMob, "scenario.name", ...
    sixgr.util.structGet(cfgMob, "meta.lls6gScenarioID", "UMa")));

seed = double(sixgr.util.structGet(cfgMob, "run.seed", 1));
rngState = rng; %#ok<RNGR>
cleanupRng = onCleanup(@() rng(rngState)); %#ok<NASGU>
rng(seed + 701, "twister");

layoutStruct = sixgr.scenario.generateLayout(cfgMob, scenarioName);
ue = sixgr.scenario.dropUEs(cfgMob, layoutStruct, scenarioName);

numSlots = localResolveNumSlots(cfgMob);
slotDur_s = localSlotDuration(cfgMob);
isLiveDBMode = lower(string(sixgr.util.structGet(cfgMob, "outputs.storageBackend", "filesystem"))) == "mysql_web";
if isLiveDBMode
    previewSlots = double(sixgr.util.structGet(cfgMob, "lls6g.users.live_mobility_preview_slots", 40));
    if ~(isfinite(previewSlots) && previewSlots >= 1)
        previewSlots = 40;
    end
    numSlots = min(numSlots, max(8, round(previewSlots)));
end
mobilityEnable = logical(sixgr.util.structGet(cfgMob, "scenario.mobility.enable", false));
mobilityUpdateSlots = localResolveUpdateSlots(cfgMob, slotDur_s, ...
    "scenario.mobility.updatePeriod_s", "system.mobility.updatePeriod_slots");
beamUpdateSlots = max(1, round(double(sixgr.util.structGet(cfgMob, "system.beam.updatePeriod_slots", 4))));
largeScaleUpdateSlots = localResolveUpdateSlots(cfgMob, slotDur_s, ...
    "scenario.mobility.updatePeriod_s", "system.largeScaleUpdatePeriod_slots");
topCellCount = min(max(2, round(double(sixgr.util.structGet(cfgMob, "lls6g.users.live_top_cells", 4)))), ...
    max(1, size(layoutStruct.bs.pos_m, 1)));
nRB = max(1, localEstimateNRB(cfgMob));
bw_Hz = double(sixgr.util.structGet(cfgMob, "channel.bandwidth_Hz", 20e6));
noiseFig_dB = double(sixgr.util.structGet(cfgMob, "scenario.ue.noiseFigure_dB", 9));

nBeams = max(1, round(double(sixgr.util.structGet(cfgMob, "system.beam.numBeams", ...
    sixgr.util.structGet(cfgMob, "phy.ssb.nBeams", 8)))));
beamSpanDeg = max(30, min(240, double(sixgr.util.structGet(cfgMob, "system.beam.sectorSpan_deg", 120))));
beamMaxGain_dB = double(sixgr.util.structGet(cfgMob, "system.beam.maxGain_dB", 12));

beamIdx = ones(ue.K, size(layoutStruct.bs.pos_m, 1));
beamGain_dB = zeros(ue.K, size(layoutStruct.bs.pos_m, 1));
largeScaleState = struct();
mobModel = [];
plModel = sixgr.channel.TR38901Plus(cfgLargeScale, "Seed", seed + 901);

if sixgr.db.isArtifactStoreActive() && localLargeScaleConfigDiffers(cfgMob, cfgLargeScale)
    sixgr.db.appendLogLine("INFO", ...
        string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
        "Live mobility sidecar enabled physical large-scale propagation (pathloss/LOS/shadow) for RSRP, pathloss, and cell-selection telemetry.");
end

servingCap = max(1, numSlots * ue.K);
measurementCap = max(1, numSlots * ue.K * topCellCount);
servingRows = repmat(localEmptyServingRow(), servingCap, 1);
measurementRows = repmat(localEmptyMeasurementRow(), measurementCap, 1);
eventRows = repmat(localEmptyReselectionRow(), max(1, ue.K), 1);
servingCount = 0;
measurementCount = 0;
eventCount = 0;
prevServing = zeros(ue.K, 1);

artifacts.ServingTracePath = fullfile(layout.ReportCSVDir, "live_rsrp_serving_trace.csv");
artifacts.MeasurementTracePath = fullfile(layout.ReportCSVDir, "live_cell_measurement_trace.csv");
artifacts.ReselectionEventsPath = fullfile(layout.ReportCSVDir, "live_cell_reselection_events.csv");
artifacts.CoverageSnapshotPath = fullfile(layout.ReportCSVDir, "live_coverage_snapshot.csv");

flushEvery = max(1, min(5, round(numSlots / 4)));

for slotIdx = 1:numSlots
    if slotIdx > 1 && mobilityEnable && mod(slotIdx - 2, mobilityUpdateSlots) == 0
        [ue, mobModel] = sixgr.scenario.mobility.updatePositions(ue, cfgMob, slotDur_s * mobilityUpdateSlots, mobModel);
    elseif slotIdx == 1 && mobilityEnable
        [ue, mobModel] = sixgr.scenario.mobility.updatePositions(ue, cfgMob, 0, mobModel);
    end

    doBeamUpdate = slotIdx == 1 || mod(slotIdx - 2, beamUpdateSlots) == 0;
    if doBeamUpdate
        [beamIdx, beamGain_dB] = sixgr.system.selectBestBeamPerLink( ...
            ue.pos_m, layoutStruct.bs.pos_m, layoutStruct.bs.azim_deg, ...
            nBeams, beamSpanDeg, beamMaxGain_dB);
    end

    doPropagationUpdate = slotIdx == 1 || doBeamUpdate || mod(slotIdx - 2, largeScaleUpdateSlots) == 0;
    reusePropagation = ~isempty(fieldnames(largeScaleState)) && ~doPropagationUpdate;
    largeScaleState = sixgr.system.buildLargeScaleStateCache( ...
        cfgLargeScale, layoutStruct, ue, beamIdx, beamGain_dB, plModel, ...
        "NumRB", nRB, ...
        "PreviousState", largeScaleState, ...
        "ReusePropagation", reusePropagation);

    [servingIdx, servingMetric_dBm] = sixgr.system.selectServingCellsFromPower(largeScaleState.RSRP_dBm);
    time_s = (slotIdx - 1) * slotDur_s;
    [ueLat, ueLon] = localProjectXYToLatLon(ue.pos_m(:,1), ue.pos_m(:,2));

    for u = 1:ue.K
        cellIdx = max(1, min(size(layoutStruct.bs.pos_m, 1), round(servingIdx(u))));
        estimatedSINR_dB = localEstimateWidebandSINR(largeScaleState.RxPower_dBm(u,:), cellIdx, bw_Hz, noiseFig_dB);
        feedback = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", estimatedSINR_dB), cfgMob, "DL");
        cqi = double(sixgr.util.structGet(feedback, "WidebandCQI", NaN));
        [modStr, codeRate, mcsIndex] = sixgr.link.amcFromCQI(cqi, "", NaN, cfgMob, "DL");

        servingCount = servingCount + 1;
        servingRows(servingCount) = struct( ...
            "Slot", double(slotIdx), ...
            "Time_s", double(time_s), ...
            "UEID", double(localUEID(ue, u)), ...
            "Lat", double(ueLat(u)), ...
            "Lon", double(ueLon(u)), ...
            "X_m", double(ue.pos_m(u,1)), ...
            "Y_m", double(ue.pos_m(u,2)), ...
            "Z_m", double(ue.pos_m(u,3)), ...
            "Speed_kmh", double(localUEColumn(ue, "speed_kmh", u)), ...
            "Heading_deg", double(localUEColumn(ue, "heading_deg", u)), ...
            "ServingCell", double(cellIdx), ...
            "ServingSite", double(layoutStruct.bs.siteId(cellIdx)), ...
            "ServingSector", double(layoutStruct.bs.sectorId(cellIdx)), ...
            "ServingBeamIndex", double(largeScaleState.BeamIndex(u, cellIdx)), ...
            "ServingBeamGain_dB", double(largeScaleState.BeamGain_dB(u, cellIdx)), ...
            "RSRP_dBm", double(servingMetric_dBm(u)), ...
            "RxPower_dBm", double(largeScaleState.RxPower_dBm(u, cellIdx)), ...
            "Pathloss_dB", double(largeScaleState.Pathloss_dB(u, cellIdx)), ...
            "LOSFlag", logical(largeScaleState.LOS(u, cellIdx)), ...
            "ShadowFading_dB", double(largeScaleState.Shadow_dB(u, cellIdx)), ...
            "O2I_dB", double(largeScaleState.O2I_dB(u, cellIdx)), ...
            "EstimatedWidebandSINR_dB", double(estimatedSINR_dB), ...
            "WidebandCQI", double(cqi), ...
            "CQIDerivedMCS", double(mcsIndex), ...
            "CQIDerivedModulation", string(modStr), ...
            "CQIDerivedTargetCodeRate", double(codeRate), ...
            "CoverageScore", double(localCoverageScore(servingMetric_dBm(u), estimatedSINR_dB)));

        [sortedRSRP, sortIdx] = sort(double(largeScaleState.RSRP_dBm(u,:)), "descend");
        keepIdx = sortIdx(1:min(topCellCount, numel(sortIdx)));
        sortedRSRP = sortedRSRP(1:numel(keepIdx));
        for k = 1:numel(keepIdx)
            c = keepIdx(k);
            measurementCount = measurementCount + 1;
            measurementRows(measurementCount) = struct( ...
                "Slot", double(slotIdx), ...
                "Time_s", double(time_s), ...
                "UEID", double(localUEID(ue, u)), ...
                "CandidateRank", double(k), ...
                "CellID", double(c), ...
                "SiteID", double(layoutStruct.bs.siteId(c)), ...
                "SectorID", double(layoutStruct.bs.sectorId(c)), ...
                "Lat", double(ueLat(u)), ...
                "Lon", double(ueLon(u)), ...
                "RSRP_dBm", double(sortedRSRP(k)), ...
                "RxPower_dBm", double(largeScaleState.RxPower_dBm(u, c)), ...
                "Pathloss_dB", double(largeScaleState.Pathloss_dB(u, c)), ...
                "BeamIndex", double(largeScaleState.BeamIndex(u, c)), ...
                "BeamGain_dB", double(largeScaleState.BeamGain_dB(u, c)), ...
                "LOSFlag", logical(largeScaleState.LOS(u, c)), ...
                "ShadowFading_dB", double(largeScaleState.Shadow_dB(u, c)), ...
                "O2I_dB", double(largeScaleState.O2I_dB(u, c)));
        end

        if slotIdx > 1 && prevServing(u) > 0 && prevServing(u) ~= cellIdx
            eventCount = eventCount + 1;
            if eventCount > numel(eventRows)
                eventRows(end + max(1, ue.K), 1) = localEmptyReselectionRow(); %#ok<AGROW>
            end
            eventRows(eventCount) = struct( ...
                "Slot", double(slotIdx), ...
                "Time_s", double(time_s), ...
                "UEID", double(localUEID(ue, u)), ...
                "FromCell", double(prevServing(u)), ...
                "ToCell", double(cellIdx), ...
                "FromRSRP_dBm", double(largeScaleState.RSRP_dBm(u, prevServing(u))), ...
                "ToRSRP_dBm", double(largeScaleState.RSRP_dBm(u, cellIdx)), ...
                "Reason", "rsrp_best_cell");
        end
    end

    prevServing = servingIdx;
    if slotIdx == numSlots || mod(slotIdx, flushEvery) == 0
        localWriteLiveMobilityTables(layout, servingRows(1:servingCount), ...
            measurementRows(1:measurementCount), eventRows(1:eventCount));
        if sixgr.db.isArtifactStoreActive()
            timeStamp = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
            msg = sprintf("Live mobility preview flush: slot %d/%d, servingRows=%d, measurementRows=%d, reselectionEvents=%d.", ...
                double(slotIdx), double(numSlots), double(servingCount), double(measurementCount), double(eventCount));
            sixgr.db.appendLogLine("INFO", timeStamp, string(msg));
        end
    end
end

artifacts.ServingTraceTable = struct2table(servingRows(1:servingCount));
artifacts.MeasurementTraceTable = struct2table(measurementRows(1:measurementCount));
if eventCount > 0
    artifacts.ReselectionEventTable = struct2table(eventRows(1:eventCount));
else
    artifacts.ReselectionEventTable = struct2table(repmat(localEmptyReselectionRow(), 0, 1));
end
artifacts.CoverageSnapshotTable = localBuildCoverageSnapshotTable(servingRows(1:servingCount));
localWriteCoverageSnapshot(artifacts.CoverageSnapshotPath, artifacts.CoverageSnapshotTable);
end

function cfgOut = localPrepareMobilityConfig(cfg, multiUser)
cfgOut = cfg;
requestedUE = double(sixgr.util.structGet(cfg, "scenario.nUE", sixgr.util.structGet(cfg, "scenario.ue.nUE", 1)));
requestedUE = max(requestedUE, double(sixgr.util.structGet(multiUser, "NumUsers", 1)));
requestedUE = max(requestedUE, double(sixgr.util.structGet(cfg, "lls6g.resolvedConfig.deployment_topology.num_ues", 1)));
requestedUE = max(1, round(requestedUE));
cfgOut = sixgr.util.structSet(cfgOut, "scenario.nUE", requestedUE);
cfgOut = sixgr.util.structSet(cfgOut, "scenario.ue.nUE", requestedUE);
end

function cfgOut = localPrepareLargeScaleSidecarConfig(cfg)
cfgOut = cfg;

cfgOut = sixgr.util.structSet(cfgOut, "channel.pathlossEnabled", true);
cfgOut = sixgr.util.structSet(cfgOut, "channel.losEnabled", true);

pathlossModel = string(sixgr.util.structGet(cfgOut, "channel.pathlossModel", "nrPathLoss"));
if strlength(strtrim(pathlossModel)) == 0 || any(lower(strtrim(pathlossModel)) == ["none","off","disabled"])
    cfgOut = sixgr.util.structSet(cfgOut, "channel.pathlossModel", "nrPathLoss");
end

shadowSigma = localScalarNumeric(sixgr.util.structGet(cfgOut, "channel.shadowSigma_dB", NaN));
if ~(isfinite(shadowSigma) && shadowSigma > 0)
    shadowSigma = localScalarNumeric(sixgr.util.structGet(cfgOut, "channel.shadowFadingStd_dB", NaN));
end
if ~(isfinite(shadowSigma) && shadowSigma > 0)
    shadowSigma = 6;
end
cfgOut = sixgr.util.structSet(cfgOut, "channel.shadowSigma_dB", shadowSigma);
cfgOut = sixgr.util.structSet(cfgOut, "channel.shadowFadingStd_dB", shadowSigma);
cfgOut = sixgr.util.structSet(cfgOut, "channel.shadowFadingEnabled", true);
end

function tf = localLargeScaleConfigDiffers(cfgA, cfgB)
tf = logical(sixgr.util.structGet(cfgA, "channel.pathlossEnabled", false)) ~= logical(sixgr.util.structGet(cfgB, "channel.pathlossEnabled", false)) ...
    || logical(sixgr.util.structGet(cfgA, "channel.losEnabled", false)) ~= logical(sixgr.util.structGet(cfgB, "channel.losEnabled", false)) ...
    || logical(sixgr.util.structGet(cfgA, "channel.shadowFadingEnabled", false)) ~= logical(sixgr.util.structGet(cfgB, "channel.shadowFadingEnabled", false)) ...
    || ~strcmpi(char(string(sixgr.util.structGet(cfgA, "channel.pathlossModel", ""))), char(string(sixgr.util.structGet(cfgB, "channel.pathlossModel", ""))));
end

function numSlots = localResolveNumSlots(cfg)
numFrames = max(1, round(double(sixgr.util.structGet(cfg, "run.numFrames", 20))));
scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
mu = log2(max(scs, 15) / 15);
if ~(isfinite(mu) && mu >= 0)
    mu = 0;
end
slotsPerFrame = 10 * (2 ^ round(mu));
numSlots = max(8, round(numFrames * slotsPerFrame));
if ~isfinite(numSlots) || numSlots < 1
    numSlots = 20;
end
end

function slots = localResolveUpdateSlots(cfg, slotDur_s, periodField, slotField)
slots = localScalarNumeric(sixgr.util.structGet(cfg, slotField, NaN));
if ~(isfinite(slots) && slots >= 1)
    period_s = localScalarNumeric(sixgr.util.structGet(cfg, periodField, slotDur_s));
    if ~(isfinite(period_s) && period_s > 0)
        period_s = slotDur_s;
    end
    slots = period_s / max(slotDur_s, eps);
end
slots = max(1, round(double(slots)));
end

function slotDur_s = localSlotDuration(cfg)
scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
mu = log2(max(scs, 15) / 15);
if ~(isfinite(mu) && mu >= 0)
    mu = 0;
end
slotDur_s = 1e-3 / (2^mu);
end

function nRB = localEstimateNRB(cfg)
carrierNRB = localScalarNumeric(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN));
if isfinite(carrierNRB) && carrierNRB >= 1
    nRB = round(carrierNRB);
else
    bw_Hz = double(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", 20e6));
    scs_kHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
    rbBw_Hz = max(12 * scs_kHz * 1e3, eps);
    nRB = round(bw_Hz / rbBw_Hz);
end
nRB = max(1, nRB);
end

function sinr_dB = localEstimateWidebandSINR(rxPowerRow_dBm, servingCell, bw_Hz, noiseFig_dB)
desired_mW = 10 .^ (double(rxPowerRow_dBm(servingCell)) / 10);
mask = true(size(rxPowerRow_dBm));
mask(servingCell) = false;
interference_mW = sum(10 .^ (double(rxPowerRow_dBm(mask)) / 10), "omitnan");
noise_dBm = -174 + 10 * log10(max(double(bw_Hz), eps)) + double(noiseFig_dB);
noise_mW = 10 .^ (noise_dBm / 10);
sinr_dB = 10 * log10(max(desired_mW, eps) / max(interference_mW + noise_mW, eps));
end

function score = localCoverageScore(rsrp_dBm, sinr_dB)
rsrpTerm = 1 ./ (1 + exp(-(double(rsrp_dBm) + 100) / 6));
sinrTerm = 1 ./ (1 + exp(-(double(sinr_dB) - 1) / 4));
score = max(0, min(1, 0.55 * rsrpTerm + 0.45 * sinrTerm));
end

function ueid = localUEID(ue, idx)
ids = sixgr.util.structGet(ue, "id", []);
if isempty(ids)
    ueid = idx;
else
    ueid = double(ids(idx));
end
end

function value = localUEColumn(ue, fieldName, idx)
value = sixgr.util.structGet(ue, fieldName, []);
if isempty(value)
    value = NaN;
    return;
end
value = double(value(idx));
end

function localWriteLiveMobilityTables(layout, servingRows, measurementRows, eventRows)
servingT = struct2table(servingRows);
measurementT = struct2table(measurementRows);
if isempty(eventRows)
    eventT = struct2table(repmat(localEmptyReselectionRow(), 0, 1));
else
    eventT = struct2table(eventRows);
end
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_rsrp_serving_trace.csv"), servingT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_cell_measurement_trace.csv"), measurementT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_cell_reselection_events.csv"), eventT);
end

function T = localBuildCoverageSnapshotTable(servingRows)
if isempty(servingRows)
    T = struct2table(repmat(localEmptyCoverageRow(), 0, 1));
    return;
end
servingT = struct2table(servingRows);
ueList = unique(double(servingT.UEID), "stable");
rows = repmat(localEmptyCoverageRow(), numel(ueList), 1);
for i = 1:numel(ueList)
    mask = double(servingT.UEID) == ueList(i);
    lastIdx = find(mask, 1, "last");
    row = localEmptyCoverageRow();
    row.UEID = double(servingT.UEID(lastIdx));
    row.Slot = double(servingT.Slot(lastIdx));
    row.Time_s = double(servingT.Time_s(lastIdx));
    row.Lat = double(servingT.Lat(lastIdx));
    row.Lon = double(servingT.Lon(lastIdx));
    row.ServingCell = double(servingT.ServingCell(lastIdx));
    row.ServingSite = double(servingT.ServingSite(lastIdx));
    row.ServingSector = double(servingT.ServingSector(lastIdx));
    row.RSRP_dBm = double(servingT.RSRP_dBm(lastIdx));
    row.EstimatedWidebandSINR_dB = double(servingT.EstimatedWidebandSINR_dB(lastIdx));
    row.CQIDerivedMCS = double(servingT.CQIDerivedMCS(lastIdx));
    row.CQIDerivedModulation = string(servingT.CQIDerivedModulation(lastIdx));
    row.CQIDerivedTargetCodeRate = double(servingT.CQIDerivedTargetCodeRate(lastIdx));
    row.WidebandCQI = double(servingT.WidebandCQI(lastIdx));
    row.Pathloss_dB = double(servingT.Pathloss_dB(lastIdx));
    row.CoverageScore = double(servingT.CoverageScore(lastIdx));
    rows(i) = row;
end
T = struct2table(rows);
end

function localWriteCoverageSnapshot(pathOut, coverageT)
if nargin < 2 || ~istable(coverageT)
    coverageT = struct2table(repmat(localEmptyCoverageRow(), 0, 1));
end
sixgr.util.csvWriteTable(pathOut, coverageT);
end

function [lat, lon] = localProjectXYToLatLon(x_m, y_m)
anchorLat = 19.122164;
anchorLon = 72.999217;
[lat, lon] = sixgr.util.projectLocalXYToGeo(x_m, y_m, anchorLat, anchorLon);
end

function value = localScalarNumeric(raw)
vals = double(raw);
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = vals(1);
end
end

function row = localEmptyServingRow()
row = struct( ...
    "Slot", NaN, ...
    "Time_s", NaN, ...
    "UEID", NaN, ...
    "Lat", NaN, ...
    "Lon", NaN, ...
    "X_m", NaN, ...
    "Y_m", NaN, ...
    "Z_m", NaN, ...
    "Speed_kmh", NaN, ...
    "Heading_deg", NaN, ...
    "ServingCell", NaN, ...
    "ServingSite", NaN, ...
    "ServingSector", NaN, ...
    "ServingBeamIndex", NaN, ...
    "ServingBeamGain_dB", NaN, ...
    "RSRP_dBm", NaN, ...
    "RxPower_dBm", NaN, ...
    "Pathloss_dB", NaN, ...
    "LOSFlag", false, ...
    "ShadowFading_dB", NaN, ...
    "O2I_dB", NaN, ...
    "EstimatedWidebandSINR_dB", NaN, ...
    "WidebandCQI", NaN, ...
    "CQIDerivedMCS", NaN, ...
    "CQIDerivedModulation", "", ...
    "CQIDerivedTargetCodeRate", NaN, ...
    "CoverageScore", NaN);
end

function row = localEmptyMeasurementRow()
row = struct( ...
    "Slot", NaN, ...
    "Time_s", NaN, ...
    "UEID", NaN, ...
    "CandidateRank", NaN, ...
    "CellID", NaN, ...
    "SiteID", NaN, ...
    "SectorID", NaN, ...
    "Lat", NaN, ...
    "Lon", NaN, ...
    "RSRP_dBm", NaN, ...
    "RxPower_dBm", NaN, ...
    "Pathloss_dB", NaN, ...
    "BeamIndex", NaN, ...
    "BeamGain_dB", NaN, ...
    "LOSFlag", false, ...
    "ShadowFading_dB", NaN, ...
    "O2I_dB", NaN);
end

function row = localEmptyReselectionRow()
row = struct( ...
    "Slot", NaN, ...
    "Time_s", NaN, ...
    "UEID", NaN, ...
    "FromCell", NaN, ...
    "ToCell", NaN, ...
    "FromRSRP_dBm", NaN, ...
    "ToRSRP_dBm", NaN, ...
    "Reason", "");
end

function row = localEmptyCoverageRow()
row = struct( ...
    "UEID", NaN, ...
    "Slot", NaN, ...
    "Time_s", NaN, ...
    "Lat", NaN, ...
    "Lon", NaN, ...
    "ServingCell", NaN, ...
    "ServingSite", NaN, ...
    "ServingSector", NaN, ...
    "RSRP_dBm", NaN, ...
    "EstimatedWidebandSINR_dB", NaN, ...
    "WidebandCQI", NaN, ...
    "CQIDerivedMCS", NaN, ...
    "CQIDerivedModulation", "", ...
    "CQIDerivedTargetCodeRate", NaN, ...
    "Pathloss_dB", NaN, ...
    "CoverageScore", NaN);
end
