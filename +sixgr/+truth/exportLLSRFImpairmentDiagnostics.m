function artifacts = exportLLSRFImpairmentDiagnostics(cfg, airInterfaceRunFolder, rawTrials)
%EXPORTLLSRFIMPAIRMENTDIAGNOSTICS Emit truthful RF IQ-imbalance diagnostics for LLS runs.

artifacts = struct("CSV", "", "TimelineCSV", "", "SummaryTable", table(), "TimelineTable", table());

if nargin < 3 || ~isstruct(rawTrials)
    rawTrials = struct();
end

rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.ensureFolder(layout.RFCSVDir);

timelineT = localBuildIQImbalanceTimeline(rawTrials);
if isempty(timelineT)
    return;
end
summaryT = localBuildIQImbalanceSummary(cfg, timelineT);
summaryT = sixgr.truth.finalizeProbeMetricTable(summaryT);

timelinePath = fullfile(layout.RFCSVDir, "iq_imbalance_timeline_trace.csv");
summaryPath = fullfile(layout.RFCSVDir, "probe_rf_iq_imbalance.csv");
sixgr.util.csvWriteTable(timelinePath, timelineT);
sixgr.util.csvWriteTable(summaryPath, summaryT);

artifacts.CSV = summaryPath;
artifacts.TimelineCSV = timelinePath;
artifacts.SummaryTable = summaryT;
artifacts.TimelineTable = timelineT;
end

function timelineT = localBuildIQImbalanceTimeline(rawTrials)
rows = repmat(localEmptyTimelineRow(), 0, 1);
rows = [rows; localBuildTimelineRows(localResolveTrialTable(sixgr.util.structGet(rawTrials, "DL", table())), "DL", "air_interface/csv/dl_pdsch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildTimelineRows(localResolveTrialTable(sixgr.util.structGet(rawTrials, "UL", table())), "UL", "air_interface/csv/ul_pusch_trials.csv")]; %#ok<AGROW>

if isempty(rows)
    timelineT = table();
else
    timelineT = struct2table(rows);
end
end

function rows = localBuildTimelineRows(T, direction, sourceArtifact)
rows = repmat(localEmptyTimelineRow(), 0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end
iqFields = [ ...
    "IQImbalanceConfigured","IQImbalanceApplied","IQImbalanceModel", ...
    "ConfiguredIQGainImbalance_dB","ConfiguredIQPhaseImbalance_deg", ...
    "IQImbalanceMirrorPowerRatio_dB","IQImbalanceImageRejection_dB", ...
    "IQImbalanceIQPowerRatio_dB","IQImbalanceIQCorrelation", ...
    "IQImbalanceEstimatedAlphaAbs","IQImbalanceEstimatedBetaAbs", ...
    "IQImbalanceMeasurementSource","IQImbalanceMeasurementStatus"];
if ~any(ismember(iqFields, string(T.Properties.VariableNames)))
    return;
end

for i = 1:height(T)
    row = localEmptyTimelineRow();
    row.Direction = upper(string(direction));
    row.TrialIndex = double(i);
    row.Frame = localNumericField(T, i, ["Frame"], NaN);
    row.Slot = localNumericField(T, i, ["Slot"], NaN);
    row.UEID = localNumericField(T, i, ["UEID"], NaN);
    row.UEIndex = localNumericField(T, i, ["UEIndex"], NaN);
    row.RNTI = localNumericField(T, i, ["RNTI"], NaN);
    row.BaseStationID = localNumericField(T, i, ["BaseStationID","CellID","ServingCell"], NaN);
    row.ChannelModel = string(localTableValue(T, i, "ChannelModel", ""));
    row.Modulation = string(localTableValue(T, i, "Modulation", ""));
    row.MCSIndex = localNumericField(T, i, ["MCSIndex","MCS"], NaN);
    row.AllocatedPRBCount = localNumericField(T, i, ["AllocatedPRBCount","PRBCount"], NaN);
    row.Status = string(localTableValue(T, i, "Status", ""));
    row.IQImbalanceConfigured = logical(localTableValue(T, i, "IQImbalanceConfigured", false));
    row.IQImbalanceApplied = logical(localTableValue(T, i, "IQImbalanceApplied", false));
    row.IQImbalanceModel = string(localTableValue(T, i, "IQImbalanceModel", ""));
    row.ConfiguredIQGainImbalance_dB = localNumericField(T, i, ["ConfiguredIQGainImbalance_dB"], NaN);
    row.ConfiguredIQPhaseImbalance_deg = localNumericField(T, i, ["ConfiguredIQPhaseImbalance_deg"], NaN);
    row.IQImbalanceMirrorPowerRatio_dB = localNumericField(T, i, ["IQImbalanceMirrorPowerRatio_dB"], NaN);
    row.IQImbalanceImageRejection_dB = localNumericField(T, i, ["IQImbalanceImageRejection_dB"], NaN);
    row.IQImbalanceIQPowerRatio_dB = localNumericField(T, i, ["IQImbalanceIQPowerRatio_dB"], NaN);
    row.IQImbalanceIQCorrelation = localNumericField(T, i, ["IQImbalanceIQCorrelation"], NaN);
    row.IQImbalanceEstimatedAlphaAbs = localNumericField(T, i, ["IQImbalanceEstimatedAlphaAbs"], NaN);
    row.IQImbalanceEstimatedBetaAbs = localNumericField(T, i, ["IQImbalanceEstimatedBetaAbs"], NaN);
    row.IQImbalanceMeasurementSource = string(localTableValue(T, i, "IQImbalanceMeasurementSource", ""));
    row.IQImbalanceMeasurementStatus = string(localTableValue(T, i, "IQImbalanceMeasurementStatus", ""));
    row.MeasurementAvailable = localHasFiniteMetric(row);
    row.SourceArtifact = string(sourceArtifact);
    rows(end+1, 1) = row; %#ok<AGROW>
end
end

function summaryT = localBuildIQImbalanceSummary(~, timelineT)
summaryRows = repmat(localEmptySummaryRow(), 0, 1);
if ~(istable(timelineT) && ~isempty(timelineT))
    summaryT = table();
    return;
end

sourceSet = unique(string(timelineT.SourceArtifact));
sourceSet = sourceSet(strlength(sourceSet) > 0);
for direction = ["DL","UL","ALL"]
    if direction == "ALL"
        slice = timelineT;
    else
        slice = timelineT(upper(string(timelineT.Direction)) == direction, :);
    end
    if isempty(slice)
        continue;
    end
    summaryRows(end+1, 1) = localSummarizeDirection(direction, slice, sourceSet); %#ok<AGROW>
end

if isempty(summaryRows)
    summaryT = table();
else
    summaryT = struct2table(summaryRows);
end
end

function row = localSummarizeDirection(direction, T, sourceSet)
row = localEmptySummaryRow();
row.Direction = string(direction);
row.RowCount = double(height(T));
row.ConfiguredRowCount = double(sum(logical(T.IQImbalanceConfigured)));
row.AppliedRowCount = double(sum(logical(T.IQImbalanceApplied)));
row.MeasuredRowCount = double(sum(logical(T.MeasurementAvailable)));
row.MeanConfiguredIQGainImbalance_dB = localMeanColumn(T.ConfiguredIQGainImbalance_dB);
row.MeanConfiguredIQPhaseImbalance_deg = localMeanColumn(T.ConfiguredIQPhaseImbalance_deg);
row.MeanMirrorPowerRatio_dB = localMeanColumn(T.IQImbalanceMirrorPowerRatio_dB);
row.P05MirrorPowerRatio_dB = localPercentile(T.IQImbalanceMirrorPowerRatio_dB, 5);
row.P95MirrorPowerRatio_dB = localPercentile(T.IQImbalanceMirrorPowerRatio_dB, 95);
row.MeanImageRejection_dB = localMeanColumn(T.IQImbalanceImageRejection_dB);
row.MinImageRejection_dB = localMinColumn(T.IQImbalanceImageRejection_dB);
row.P05ImageRejection_dB = localPercentile(T.IQImbalanceImageRejection_dB, 5);
row.P95ImageRejection_dB = localPercentile(T.IQImbalanceImageRejection_dB, 95);
row.MaxImageRejection_dB = localMaxColumn(T.IQImbalanceImageRejection_dB);
row.MeanIQPowerRatio_dB = localMeanColumn(T.IQImbalanceIQPowerRatio_dB);
row.MeanAbsIQCorrelation = localMeanColumn(abs(double(T.IQImbalanceIQCorrelation)));
row.MeanEstimatedAlphaAbs = localMeanColumn(T.IQImbalanceEstimatedAlphaAbs);
row.MeanEstimatedBetaAbs = localMeanColumn(T.IQImbalanceEstimatedBetaAbs);
row.ModelSet = localStringSet(T.IQImbalanceModel);
row.MeasurementSourceSet = localStringSet(T.IQImbalanceMeasurementSource);
row.MeasurementStatusSet = localStringSet(T.IQImbalanceMeasurementStatus);
if direction == "ALL"
    row.SourceArtifact = strjoin(sourceSet(:).', "|");
else
    row.SourceArtifact = localStringSet(string(T.SourceArtifact));
end
if row.MeasuredRowCount > 0
    row.Availability = "measured_runtime_iq_imbalance";
    row.Note = "Summary aggregates sample-domain IQ-imbalance measurements emitted by the active waveform TX/RX impairment chain.";
elseif row.AppliedRowCount > 0
    row.Availability = "applied_without_finite_measurement";
    row.Note = "The waveform chain marked IQ imbalance as applied, but no finite measurement rows survived into the persisted trial table.";
elseif row.ConfiguredRowCount > 0
    row.Availability = "configured_not_applied";
    row.Note = "IQ imbalance was configured for these trial rows, but execution did not reach a measured impairment stage.";
else
    row.Availability = "iq_imbalance_disabled";
    row.Note = "IQ imbalance was disabled in the persisted waveform trial rows for this direction.";
end
end

function tf = localHasFiniteMetric(row)
values = [ ...
    row.IQImbalanceMirrorPowerRatio_dB
    row.IQImbalanceImageRejection_dB
    row.IQImbalanceIQPowerRatio_dB
    row.IQImbalanceIQCorrelation
    row.IQImbalanceEstimatedAlphaAbs
    row.IQImbalanceEstimatedBetaAbs];
tf = any(isfinite(double(values)));
end

function value = localMeanColumn(values)
vals = double(values(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = mean(vals, "omitnan");
end
end

function value = localMinColumn(values)
vals = double(values(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = min(vals);
end
end

function value = localMaxColumn(values)
vals = double(values(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = max(vals);
end
end

function value = localPercentile(values, pct)
vals = sort(double(values(:)));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
    return;
end
if numel(vals) == 1
    value = vals(1);
    return;
end
pos = 1 + (numel(vals) - 1) * max(0, min(100, double(pct))) / 100;
idx0 = floor(pos);
idx1 = ceil(pos);
if idx0 == idx1
    value = vals(idx0);
else
    frac = pos - idx0;
    value = vals(idx0) + frac * (vals(idx1) - vals(idx0));
end
end

function value = localStringSet(values)
tokens = string(values(:));
tokens = strtrim(tokens);
tokens = tokens(strlength(tokens) > 0);
tokens = unique(tokens, "stable");
if isempty(tokens)
    value = "";
else
    value = strjoin(tokens(:).', "|");
end
end

function T = localResolveTrialTable(v)
if istable(v)
    T = v;
else
    T = table();
end
end

function value = localNumericField(T, idx, names, defaultValue)
names = string(names(:));
for i = 1:numel(names)
    if ismember(names(i), string(T.Properties.VariableNames))
        raw = T.(char(names(i)))(idx);
        if iscell(raw)
            raw = raw{1};
        end
        value = double(raw);
        if isscalar(value) && isfinite(value)
            return;
        end
    end
end
value = defaultValue;
end

function value = localTableValue(T, idx, name, defaultValue)
if ~(istable(T) && idx >= 1 && idx <= height(T) && ismember(name, string(T.Properties.VariableNames)))
    value = defaultValue;
    return;
end
value = T.(char(name))(idx);
if iscell(value)
    value = value{1};
end
if isempty(value)
    value = defaultValue;
end
end

function row = localEmptyTimelineRow()
row = struct( ...
    "Direction", "", ...
    "TrialIndex", NaN, ...
    "Frame", NaN, ...
    "Slot", NaN, ...
    "UEID", NaN, ...
    "UEIndex", NaN, ...
    "RNTI", NaN, ...
    "BaseStationID", NaN, ...
    "ChannelModel", "", ...
    "Modulation", "", ...
    "MCSIndex", NaN, ...
    "AllocatedPRBCount", NaN, ...
    "Status", "", ...
    "IQImbalanceConfigured", false, ...
    "IQImbalanceApplied", false, ...
    "IQImbalanceModel", "", ...
    "ConfiguredIQGainImbalance_dB", NaN, ...
    "ConfiguredIQPhaseImbalance_deg", NaN, ...
    "IQImbalanceMirrorPowerRatio_dB", NaN, ...
    "IQImbalanceImageRejection_dB", NaN, ...
    "IQImbalanceIQPowerRatio_dB", NaN, ...
    "IQImbalanceIQCorrelation", NaN, ...
    "IQImbalanceEstimatedAlphaAbs", NaN, ...
    "IQImbalanceEstimatedBetaAbs", NaN, ...
    "MeasurementAvailable", false, ...
    "IQImbalanceMeasurementSource", "", ...
    "IQImbalanceMeasurementStatus", "", ...
    "SourceArtifact", "");
end

function row = localEmptySummaryRow()
row = struct( ...
    "Direction", "", ...
    "Availability", "", ...
    "RowCount", NaN, ...
    "ConfiguredRowCount", NaN, ...
    "AppliedRowCount", NaN, ...
    "MeasuredRowCount", NaN, ...
    "MeanConfiguredIQGainImbalance_dB", NaN, ...
    "MeanConfiguredIQPhaseImbalance_deg", NaN, ...
    "MeanMirrorPowerRatio_dB", NaN, ...
    "P05MirrorPowerRatio_dB", NaN, ...
    "P95MirrorPowerRatio_dB", NaN, ...
    "MeanImageRejection_dB", NaN, ...
    "MinImageRejection_dB", NaN, ...
    "P05ImageRejection_dB", NaN, ...
    "P95ImageRejection_dB", NaN, ...
    "MaxImageRejection_dB", NaN, ...
    "MeanIQPowerRatio_dB", NaN, ...
    "MeanAbsIQCorrelation", NaN, ...
    "MeanEstimatedAlphaAbs", NaN, ...
    "MeanEstimatedBetaAbs", NaN, ...
    "ModelSet", "", ...
    "MeasurementSourceSet", "", ...
    "MeasurementStatusSet", "", ...
    "SourceArtifact", "", ...
    "Note", "");
end
