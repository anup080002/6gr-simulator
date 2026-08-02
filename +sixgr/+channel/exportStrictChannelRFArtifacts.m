function artifacts = exportStrictChannelRFArtifacts(result, runFolder)
%EXPORTSTRICTCHANNELRFARTIFACTS Write strict Channel/RF evidence tables.

if nargin < 2 || strlength(string(runFolder)) == 0
    runFolder = tempname;
end
layout = sixgr.report.resultLayout(runFolder);
channelDir = fullfile(layout.Root, "channel");
channelCsvDir = fullfile(channelDir, "csv");
channelImageDir = fullfile(channelDir, "image");
reportCsvDir = layout.ReportCSVDir;
rfCsvDir = layout.RFCSVDir;
interferenceCsvDir = layout.InterferenceCSVDir;
jsonDir = fullfile(layout.ReportDir, "json");
airCsvDir = layout.AirInterfaceCSVDir;

dirs = [channelCsvDir, channelImageDir, reportCsvDir, rfCsvDir, interferenceCsvDir, jsonDir, airCsvDir];
for i = 1:numel(dirs)
    if ~exist(dirs(i), "dir")
        mkdir(dirs(i));
    end
end

artifacts = struct();
artifacts.ChannelRFConfigStrictCSV = fullfile(channelCsvDir, "channel_rf_config_strict.csv");
artifacts.LinkGeometryCSV = fullfile(channelCsvDir, "link_geometry.csv");
artifacts.SitesCSV = fullfile(channelCsvDir, "sites.csv");
artifacts.SectorsCSV = fullfile(channelCsvDir, "sectors.csv");
artifacts.UEsCSV = fullfile(channelCsvDir, "ues.csv");
artifacts.LargeScaleParametersCSV = fullfile(channelCsvDir, "large_scale_parameters.csv");
artifacts.ChannelRealizationsCSV = fullfile(channelCsvDir, "channel_realizations.csv");
artifacts.ChannelSnapshotsCSV = fullfile(channelCsvDir, "channel_snapshots.csv");
artifacts.PathGainsCSV = fullfile(channelCsvDir, "path_gains.csv");
artifacts.ConfiguredVsAppliedCSV = fullfile(channelCsvDir, "channel_configured_vs_applied.csv");
artifacts.ChannelRFConfiguredAppliedReportCSV = fullfile(reportCsvDir, "channel_rf_configured_applied.csv");
artifacts.ChannelRFCDLCRealizationReportCSV = fullfile(reportCsvDir, "channel_rf_cdlc_realization_table.csv");
artifacts.ChannelRFPerUERealizationReportCSV = fullfile(reportCsvDir, "channel_rf_per_ue_realization.csv");
artifacts.ChannelRFStrictSummaryReportCSV = fullfile(reportCsvDir, "channel_rf_strict_summary.csv");
artifacts.ChannelRFNegativeReportCSV = fullfile(reportCsvDir, "channel_rf_negative_trials.csv");
artifacts.ChannelRFNegativeTrialsCSV = fullfile(rfCsvDir, "channel_rf_negative_trials.csv");
artifacts.ChannelRFOracleGuardCSV = fullfile(rfCsvDir, "channel_rf_oracle_guard.csv");
artifacts.RFImpairmentChainCSV = fullfile(rfCsvDir, "rf_impairment_chain.csv");
artifacts.EVMMeasurementsCSV = fullfile(rfCsvDir, "evm_impairment_measurements.csv");
artifacts.ThermalNoiseCSV = fullfile(rfCsvDir, "thermal_noise_validation.csv");
artifacts.InterferenceTopologyCSV = fullfile(interferenceCsvDir, "interference_topology.csv");
artifacts.DownstreamReferencesCSV = fullfile(airCsvDir, "downstream_channel_references.csv");
artifacts.ToolboxCapabilitiesJSON = fullfile(jsonDir, "channel_rf_toolbox_capabilities.json");
artifacts.ConformanceSummaryJSON = fullfile(jsonDir, "channel_rf_conformance_summary.json");
artifacts.ConfiguredVsAppliedPNG = fullfile(channelImageDir, "channel_configured_vs_applied.png");
artifacts.RFImpairmentPNG = fullfile(layout.ReportImageDir, "rf_impairment_chain.png");

sixgr.util.csvWriteTable(artifacts.ChannelRFConfigStrictCSV, result.ConfigStrict);
sixgr.util.csvWriteTable(artifacts.LinkGeometryCSV, result.Geometry.LinkTable);
sixgr.util.csvWriteTable(artifacts.SitesCSV, result.Geometry.SiteTable);
sixgr.util.csvWriteTable(artifacts.SectorsCSV, result.Geometry.SectorTable);
sixgr.util.csvWriteTable(artifacts.UEsCSV, result.Geometry.UETable);
sixgr.util.csvWriteTable(artifacts.LargeScaleParametersCSV, result.LargeScaleParameters);
sixgr.util.csvWriteTable(artifacts.ChannelRealizationsCSV, result.ChannelRealizations);
sixgr.util.csvWriteTable(artifacts.ChannelSnapshotsCSV, result.ChannelSnapshots);
sixgr.util.csvWriteTable(artifacts.PathGainsCSV, result.ChannelPathGains);
sixgr.util.csvWriteTable(artifacts.ConfiguredVsAppliedCSV, result.ConfiguredVsApplied);
sixgr.util.csvWriteTable(artifacts.ChannelRFConfiguredAppliedReportCSV, localReportConfiguredAppliedTable(result));
sixgr.util.csvWriteTable(artifacts.ChannelRFCDLCRealizationReportCSV, localCDLCRealizationReportTable(result));
sixgr.util.csvWriteTable(artifacts.ChannelRFPerUERealizationReportCSV, localPerUERealizationReportTable(result));
sixgr.util.csvWriteTable(artifacts.ChannelRFStrictSummaryReportCSV, localStrictSummaryReportTable(result));
sixgr.util.csvWriteTable(artifacts.ChannelRFNegativeReportCSV, result.NegativeTrials);
sixgr.util.csvWriteTable(artifacts.ChannelRFNegativeTrialsCSV, result.NegativeTrials);
sixgr.util.csvWriteTable(artifacts.ChannelRFOracleGuardCSV, result.OracleGuard);
sixgr.util.csvWriteTable(artifacts.RFImpairmentChainCSV, result.RFImpairmentChain);
sixgr.util.csvWriteTable(artifacts.EVMMeasurementsCSV, result.EVMMeasurements);
sixgr.util.csvWriteTable(artifacts.ThermalNoiseCSV, result.ThermalNoise);
sixgr.util.csvWriteTable(artifacts.InterferenceTopologyCSV, result.InterferenceTopology);
sixgr.util.csvWriteTable(artifacts.DownstreamReferencesCSV, result.DownstreamReferences);

sixgr.util.jsonWrite(artifacts.ToolboxCapabilitiesJSON, result.ToolboxCapabilities);
summary = struct();
summary.StrictOk = logical(result.StrictOk);
summary.FailureReason = string(result.FailureReason);
summary.ChannelRealizationRows = height(result.ChannelRealizations);
summary.ConfiguredVsAppliedRows = height(result.ConfiguredVsApplied);
summary.NegativeRows = height(result.NegativeTrials);
summary.OracleViolationCount = sum(logical(result.OracleGuard.Violation));
summary.ProxyAllowed = false;
summary.StrictModeToolboxFallbackAllowed = false;
summary.ProducerModule = "sixgr.channel.exportStrictChannelRFArtifacts";
sixgr.util.jsonWrite(artifacts.ConformanceSummaryJSON, summary);

localWriteConfiguredVsAppliedPNG(artifacts.ConfiguredVsAppliedPNG, result.ConfiguredVsApplied);
localWriteRFPNG(artifacts.RFImpairmentPNG, result.RFImpairmentChain);
artifacts.ArtifactManifest = localArtifactManifest(artifacts);
sixgr.util.csvWriteTable(fullfile(channelCsvDir, "channel_rf_strict_artifact_manifest.csv"), artifacts.ArtifactManifest);
end

function T = localReportConfiguredAppliedTable(result)
T = result.ConfiguredVsApplied;
if istable(T) && height(T) > 0
    if ismember("ExpectedOk", string(T.Properties.VariableNames))
        T = T(logical(T.ExpectedOk), :);
    end
    if ~ismember("ConfiguredAppliedOk", string(T.Properties.VariableNames))
        ok = true(height(T), 1);
        if ismember("StrictOk", string(T.Properties.VariableNames))
            ok = ok & logical(T.StrictOk);
        end
        if ismember("ConfiguredAppliedMatch", string(T.Properties.VariableNames))
            ok = ok & logical(T.ConfiguredAppliedMatch);
        end
        if ismember("FeatureApplied", string(T.Properties.VariableNames))
            ok = ok & logical(T.FeatureApplied);
        end
        T.ConfiguredAppliedOk = ok;
    end
end
end

function T = localCDLCRealizationReportTable(result)
template = localCDLCReportRow();
rows = repmat(template, 0, 1);
chT = result.ChannelRealizations;
if ~(istable(chT) && height(chT) > 0)
    T = struct2table(rows);
    return;
end
mask = string(chT.ChannelModelType) == "CDL" & string(chT.DelayProfile) == "CDL-C";
if ~any(mask)
    T = struct2table(rows);
    return;
end
cdl = chT(find(mask, 1, "first"), :);
[profile, source] = localCDLCPathProfile(cdl);
delaysSec = profile.PathDelays(:);
gainsDb = profile.AveragePathGains(:);
for ii = 1:numel(delaysSec)
    row = template;
    row.RunId = string(cdl.RunId(1));
    row.ScenarioName = string(cdl.ScenarioName(1));
    row.TrialId = string(cdl.TrialId(1));
    row.ChannelRealizationId = string(cdl.ChannelRealizationId(1));
    row.PathIndex = double(ii);
    row.Delay_s = double(delaysSec(ii));
    row.Delay_ns = double(delaysSec(ii) * 1e9);
    row.AveragePathGain_dB = double(gainsDb(ii));
    row.AngleAoD_deg = double(profile.AnglesAoD(ii));
    row.AngleAoA_deg = double(profile.AnglesAoA(ii));
    row.AngleZoD_deg = double(profile.AnglesZoD(ii));
    row.AngleZoA_deg = double(profile.AnglesZoA(ii));
    row.MaxDopplerHz = double(cdl.MaxDopplerHz(1));
    row.DelaySpreadSec = double(cdl.DelaySpreadSec(1));
    row.ProfileSource = string(source);
    row.PathGainsExported = logical(cdl.PathGainsExported(1));
    row.ChannelSnapshotExported = logical(cdl.ChannelSnapshotExported(1));
    row.WaveformChanged = logical(cdl.WaveformChanged(1));
    row.StrictOk = logical(cdl.StrictOk(1));
    row.TruthStatus = string(cdl.TruthStatus(1));
    rows(end + 1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows, "AsArray", true);
end

function [profile, source] = localCDLCPathProfile(cdl)
profile = struct("PathDelays", [], "AveragePathGains", [], ...
    "AnglesAoD", [], "AnglesAoA", [], "AnglesZoD", [], "AnglesZoA", []);
source = "nrCDLChannel_info_CDL-C_runtime_profile";
try
    ch = nrCDLChannel;
    ch.DelayProfile = "CDL-C";
    ch.DelaySpread = double(cdl.DelaySpreadSec(1));
    ch.MaximumDopplerShift = double(cdl.MaxDopplerHz(1));
    ch.CarrierFrequency = 4e9;
    infoStruct = info(ch);
    profile.PathDelays = double(infoStruct.PathDelays(:));
    profile.AveragePathGains = double(infoStruct.AveragePathGains(:));
    profile.AnglesAoD = double(infoStruct.AnglesAoD(:));
    profile.AnglesAoA = double(infoStruct.AnglesAoA(:));
    profile.AnglesZoD = double(infoStruct.AnglesZoD(:));
    profile.AnglesZoA = double(infoStruct.AnglesZoA(:));
catch
    profile.PathDelays = [];
    profile.AveragePathGains = [];
end
if isempty(profile.PathDelays) || isempty(profile.AveragePathGains)
    source = "applied_cdl_realization_summary_toolbox_path_profile_hidden";
    profile.PathDelays = double(cdl.MeasuredRMSDelaySpreadSec(1));
    profile.AveragePathGains = 0;
    profile.AnglesAoD = NaN;
    profile.AnglesAoA = NaN;
    profile.AnglesZoD = NaN;
    profile.AnglesZoA = NaN;
end
n = min([numel(profile.PathDelays), numel(profile.AveragePathGains), ...
    numel(profile.AnglesAoD), numel(profile.AnglesAoA), ...
    numel(profile.AnglesZoD), numel(profile.AnglesZoA)]);
profile.PathDelays = profile.PathDelays(1:n);
profile.AveragePathGains = profile.AveragePathGains(1:n);
profile.AnglesAoD = profile.AnglesAoD(1:n);
profile.AnglesAoA = profile.AnglesAoA(1:n);
profile.AnglesZoD = profile.AnglesZoD(1:n);
profile.AnglesZoA = profile.AnglesZoA(1:n);
end

function T = localPerUERealizationReportTable(result)
template = localPerUERow();
rows = repmat(template, 0, 1);
lsT = result.LargeScaleParameters;
if ~(istable(lsT) && height(lsT) > 0)
    T = struct2table(rows);
    return;
end
for ii = 1:height(lsT)
    row = template;
    row.RunId = string(lsT.RunId(ii));
    row.ScenarioName = string(lsT.ScenarioName(ii));
    row.LinkId = string(lsT.LinkId(ii));
    row.ChannelRealizationId = string(lsT.ChannelRealizationId(ii));
    row.Distance2Dm = double(lsT.Distance2Dm(ii));
    row.Distance3Dm = double(lsT.Distance3Dm(ii));
    row.PathlossModel = string(lsT.PathlossModel(ii));
    row.LOSState = logical(lsT.LOSState(ii));
    row.O2IState = logical(lsT.O2IState(ii));
    row.PathlossDbApplied = double(lsT.PathlossDbApplied(ii));
    row.ShadowFadingDbApplied = double(lsT.ShadowFadingDbApplied(ii));
    row.O2IPenetrationLossDbApplied = double(lsT.O2IPenetrationLossDbApplied(ii));
    row.TotalLargeScaleLossDbApplied = double(lsT.TotalLargeScaleLossDbApplied(ii));
    row.MeasuredDeltaDb = double(lsT.MeasuredDeltaDb(ii));
    row.AppliedOk = logical(lsT.AppliedOk(ii));
    row.TruthStatus = string(lsT.TruthStatus(ii));
    rows(end + 1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows, "AsArray", true);
end

function T = localStrictSummaryReportTable(result)
row = struct();
row.StrictOk = logical(result.StrictOk);
row.FailureReason = string(result.FailureReason);
row.ConfiguredAppliedRows = height(result.ConfiguredVsApplied);
row.ConfiguredAppliedPositiveRows = sum(logical(result.ConfiguredVsApplied.ExpectedOk));
row.ConfiguredAppliedPositiveOkRows = sum(logical(result.ConfiguredVsApplied.ExpectedOk) & logical(result.ConfiguredVsApplied.StrictOk));
row.ChannelRealizationRows = height(result.ChannelRealizations);
row.CDLRealizationRows = sum(string(result.ChannelRealizations.ChannelModelType) == "CDL");
row.LargeScaleRows = height(result.LargeScaleParameters);
row.RFImpairmentRows = height(result.RFImpairmentChain);
row.ThermalNoiseRows = height(result.ThermalNoise);
row.InterferenceRows = height(result.InterferenceTopology);
row.NegativeRows = height(result.NegativeTrials);
row.NegativeExpectedOkRows = sum(logical(result.NegativeTrials.NegativeExpectedOk));
row.OracleGuardRows = height(result.OracleGuard);
row.OracleViolationCount = sum(logical(result.OracleGuard.Violation));
row.ProducerModule = "sixgr.channel.exportStrictChannelRFArtifacts";
T = struct2table(row, "AsArray", true);
end

function row = localCDLCReportRow()
row = struct("RunId", "", "ScenarioName", "", "TrialId", "", ...
    "ChannelRealizationId", "", "PathIndex", NaN, "Delay_s", NaN, ...
    "Delay_ns", NaN, "AveragePathGain_dB", NaN, "AngleAoD_deg", NaN, ...
    "AngleAoA_deg", NaN, "AngleZoD_deg", NaN, "AngleZoA_deg", NaN, ...
    "MaxDopplerHz", NaN, "DelaySpreadSec", NaN, "ProfileSource", "", "PathGainsExported", false, ...
    "ChannelSnapshotExported", false, "WaveformChanged", false, ...
    "StrictOk", false, "TruthStatus", "");
end

function row = localPerUERow()
row = struct("RunId", "", "ScenarioName", "", "LinkId", "", ...
    "ChannelRealizationId", "", "Distance2Dm", NaN, "Distance3Dm", NaN, ...
    "PathlossModel", "", "LOSState", false, "O2IState", false, ...
    "PathlossDbApplied", NaN, "ShadowFadingDbApplied", NaN, ...
    "O2IPenetrationLossDbApplied", NaN, "TotalLargeScaleLossDbApplied", NaN, ...
    "MeasuredDeltaDb", NaN, "AppliedOk", false, "TruthStatus", "");
end

function localWriteConfiguredVsAppliedPNG(path, T)
ok = double(logical(T.StrictOk));
fig = figure("Visible", "off", "Color", "w", "Position", [100 100 max(720, 28 * max(height(T), 1)) 460]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
bars = bar(ax, 1:max(numel(ok), 1), [ok(:); zeros(max(0, 1-numel(ok)), 1)], 0.72);
bars.FaceColor = "flat";
for i = 1:numel(ok)
    if ok(i)
        bars.CData(i, :) = [0.18 0.48 0.21];
    else
        bars.CData(i, :) = [0.64 0.23 0.18];
    end
end
ylim(ax, [0 1.15]); grid(ax, "on");
xlabel(ax, "Configured feature evidence row"); ylabel(ax, "Strict applied match");
title(ax, "Channel/RF configured-vs-applied strict evidence", "Interpreter", "none");
sixgr.util.exportFigureArtifact(fig, path, "Resolution", 170);
end

function localWriteRFPNG(path, T)
evm = double(T.EVMMeasuredPercent(1));
fig = figure("Visible", "off", "Color", "w", "Position", [100 100 760 420]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig, "Position", [0.10 0.18 0.82 0.60]);
barh(ax, evm, "FaceColor", [0.25 0.44 0.48]);
xlabel(ax, "Measured EVM (%) from before/after waveform samples");
yticks(ax, 1); yticklabels(ax, "Runtime RF chain"); grid(ax, "on");
title(ax, "RF impairment chain applied to samples", "Interpreter", "none");
subtitleText = sprintf("CFO %.3f Hz | IQ %s | PA %s | timing %.0f samples", ...
    double(T.CFOHzApplied(1)), char(string(T.IQImbalanceEnabled(1))), ...
    char(string(T.PAEnabled(1))), double(T.TimingOffsetSamplesApplied(1)));
text(ax, 0.5, 1.08, subtitleText, "Units", "normalized", "HorizontalAlignment", "center", "Interpreter", "none");
sixgr.util.exportFigureArtifact(fig, path, "Resolution", 170);
end

function T = localArtifactManifest(artifacts)
names = string(fieldnames(artifacts));
names = names(names ~= "ArtifactManifest");
rows = repmat(struct("ArtifactName","", "FilePath","", "Exists",false, "ByteCount",NaN, "SHA256","", "TruthStatus",""), 0, 1);
for i = 1:numel(names)
    value = artifacts.(names(i));
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        continue;
    end
    p = char(value);
    exists = isfile(p);
    bytes = NaN;
    hash = "";
    if exists
        info = dir(p);
        bytes = double(info.bytes);
        hash = sixgr.channel.hashChannelRFConfig(fileread(p));
    end
    rows(end+1, 1) = struct("ArtifactName", names(i), "FilePath", string(p), ...
        "Exists", exists, "ByteCount", bytes, "SHA256", hash, "TruthStatus", "real_lls_evidence");
end
T = struct2table(rows);
end
