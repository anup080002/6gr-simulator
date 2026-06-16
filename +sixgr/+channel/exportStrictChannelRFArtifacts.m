function artifacts = exportStrictChannelRFArtifacts(result, runFolder)
%EXPORTSTRICTCHANNELRFARTIFACTS Write strict Channel/RF evidence tables.

if nargin < 2 || strlength(string(runFolder)) == 0
    runFolder = tempname;
end
layout = sixgr.report.resultLayout(runFolder);
channelDir = fullfile(layout.Root, "channel");
channelCsvDir = fullfile(channelDir, "csv");
channelImageDir = fullfile(channelDir, "image");
rfCsvDir = layout.RFCSVDir;
interferenceCsvDir = layout.InterferenceCSVDir;
jsonDir = fullfile(layout.ReportDir, "json");
airCsvDir = layout.AirInterfaceCSVDir;

dirs = [channelCsvDir, channelImageDir, rfCsvDir, interferenceCsvDir, jsonDir, airCsvDir];
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
artifacts.ChannelRFNegativeTrialsCSV = fullfile(rfCsvDir, "channel_rf_negative_trials.csv");
artifacts.ChannelRFOracleGuardCSV = fullfile(rfCsvDir, "channel_rf_oracle_guard.csv");
artifacts.RFImpairmentChainCSV = fullfile(rfCsvDir, "rf_impairment_chain.csv");
artifacts.EVMMeasurementsCSV = fullfile(rfCsvDir, "evm_impairment_measurements.csv");
artifacts.ThermalNoiseCSV = fullfile(rfCsvDir, "thermal_noise_validation.csv");
artifacts.InterferenceTopologyCSV = fullfile(interferenceCsvDir, "interference_topology.csv");
artifacts.DownstreamReferencesCSV = fullfile(airCsvDir, "downstream_channel_references.csv");
artifacts.ToolboxCapabilitiesJSON = fullfile(jsonDir, "channel_rf_toolbox_capabilities.json");
artifacts.ConformanceSummaryJSON = fullfile(jsonDir, "channel_rf_conformance_summary.json");
artifacts.ConfiguredVsAppliedSVG = fullfile(channelImageDir, "channel_configured_vs_applied.svg");
artifacts.RFImpairmentSVG = fullfile(layout.ReportImageDir, "rf_impairment_chain.svg");

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

localWriteConfiguredVsAppliedSVG(artifacts.ConfiguredVsAppliedSVG, result.ConfiguredVsApplied);
localWriteRFSVG(artifacts.RFImpairmentSVG, result.RFImpairmentChain);
artifacts.ArtifactManifest = localArtifactManifest(artifacts);
sixgr.util.csvWriteTable(fullfile(channelCsvDir, "channel_rf_strict_artifact_manifest.csv"), artifacts.ArtifactManifest);
end

function localWriteConfiguredVsAppliedSVG(path, T)
ok = double(logical(T.StrictOk));
x = 30 + (0:height(T)-1) * 34;
h = 120;
w = max(360, 60 + max(x));
fid = fopen(path, "w");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">\n', w, h);
fprintf(fid, '<rect width="100%%" height="100%%" fill="#f8fbf7"/>\n');
fprintf(fid, '<text x="20" y="24" font-family="Arial" font-size="14" font-weight="700">Channel/RF configured-vs-applied strict evidence</text>\n');
for i = 1:height(T)
    color = "#2d7a35";
    if ~ok(i)
        color = "#a33a2d";
    end
    fprintf(fid, '<rect x="%g" y="%g" width="22" height="%g" fill="%s"/>\n', x(i), 88 - 44 * ok(i), 20 + 44 * ok(i), color);
end
fprintf(fid, '<text x="20" y="110" font-family="Arial" font-size="11">green=positive applied, red=negative rejected</text>\n');
fprintf(fid, '</svg>\n');
end

function localWriteRFSVG(path, T)
if ~exist(fileparts(path), "dir")
    mkdir(fileparts(path));
end
fid = fopen(path, "w");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
evm = double(T.EVMMeasuredPercent(1));
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" width="420" height="140">\n');
fprintf(fid, '<rect width="100%%" height="100%%" fill="#fbfaf4"/>\n');
fprintf(fid, '<text x="20" y="28" font-family="Arial" font-size="14" font-weight="700">RF impairment chain applied to samples</text>\n');
fprintf(fid, '<text x="20" y="58" font-family="Arial" font-size="12">CFO %.3f Hz, IQ %s, PA %s, timing %.0f samples</text>\n', ...
    double(T.CFOHzApplied(1)), char(string(T.IQImbalanceEnabled(1))), char(string(T.PAEnabled(1))), double(T.TimingOffsetSamplesApplied(1)));
fprintf(fid, '<rect x="20" y="82" width="%g" height="18" fill="#416f7b"/>\n', min(360, max(4, evm * 20)));
fprintf(fid, '<text x="20" y="118" font-family="Arial" font-size="11">Measured EVM %.3f %% from before/after waveform samples</text>\n', evm);
fprintf(fid, '</svg>\n');
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
