function out = runReferenceQualification(runFolder, varargin)
%RUNREFERENCEQUALIFICATION Execute and persist independent FRC references.
%
% A diagnostic profile writes frc_reference_diagnostic.csv only.  The
% production qualification filename is reserved for statistically eligible
% full executions, preventing a bounded development run from satisfying the
% final production reducer.

arguments
    runFolder {mustBeTextScalar}
end
arguments (Repeating)
    varargin
end

ip = inputParser;
ip.FunctionName = "sixgr.conformance.runReferenceQualification";
ip.addParameter("Profile", "full", @(v) any(lower(string(v)) == ["full","diagnostic"]));
ip.addParameter("EntryIds", localMandatoryAWGNEntries(), @(v) isstring(v) || iscellstr(v));
ip.addParameter("EntrySampling", {}, @(v) isstruct(v) || iscell(v) || isempty(v));
ip.addParameter("Tolerance_dB", 1.0, @(v) isnumeric(v) && isscalar(v) && isfinite(v) && v > 0);
ip.addParameter("ConfidenceLevel", 0.95, ...
    @(v) isnumeric(v) && isscalar(v) && isfinite(v) && v > 0 && v < 1);
ip.addParameter("MaxConfidenceHalfWidth", [], ...
    @(v) isempty(v) || (isnumeric(v) && isscalar(v) && isfinite(v) && v > 0));
ip.addParameter("MinTransportBlocks", [], @(v) isempty(v) || (isnumeric(v) && isscalar(v) && v >= 1));
ip.addParameter("MaxTransportBlocks", [], @(v) isempty(v) || (isnumeric(v) && isscalar(v) && v >= 1));
ip.addParameter("BatchSize", [], @(v) isempty(v) || (isnumeric(v) && isscalar(v) && v >= 1));
ip.addParameter("MinimumBlockErrors", 25, @(v) isnumeric(v) && isscalar(v) && v >= 0);
ip.addParameter("RequireSymmetricRegression", false, ...
    @(v) islogical(v) || (isnumeric(v) && isscalar(v)));
ip.addParameter("ParallelWorkers", 0, ...
    @(v) isnumeric(v) && isscalar(v) && isfinite(v) && v >= 0 && v == fix(v));
ip.addParameter("Verbose", true, @(v) islogical(v) || (isnumeric(v) && isscalar(v)));
ip.parse(varargin{:});
opt = ip.Results;

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
catalog = sixgr.conformance.frcCatalog();
catalogDigest = sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(catalog), "UTF-8")));
entries = string(opt.EntryIds(:));
if isempty(entries) || numel(unique(entries)) ~= numel(entries)
    error("sixgr:conformance:InvalidQualificationEntrySet", ...
        "EntryIds must contain at least one unique FRC catalog entry id.");
end

rows = repmat(localEmptyRow(), numel(entries), 1);
for index = 1:numel(entries)
    entryId = entries(index);
    rows(index).EntryId = entryId;
    rows(index).Required = true;
    rows(index).Profile = lower(string(opt.Profile));
    rows(index).CatalogSHA256 = string(catalogDigest);
    rows(index).ExecutionAttempted = true;
    try
        entry = localCatalogEntry(catalog.entries, entryId);
        rows(index).FRC = string(entry.frc_id);
        rows(index).Condition = string(entry.condition.id);
        nv = { ...
            "ExecutionProfile", localExecutionProfile(opt.Profile), ...
            "Tolerance_dB", double(opt.Tolerance_dB), ...
            "ConfidenceLevel", double(opt.ConfidenceLevel), ...
            "MinimumBlockErrors", double(opt.MinimumBlockErrors), ...
            "EvaluateSymmetricRegression", ...
                logical(opt.RequireSymmetricRegression), ...
            "ParallelWorkers", double(opt.ParallelWorkers), ...
            "RequireExactStandardExecution", ...
                lower(string(opt.Profile)) == "full", ...
            "RequireExactDataChannelExecution", true, ...
            "AssertPass", false, "PrintTable", false, ...
            "Verbose", logical(opt.Verbose)};
        nv = localOptionalNV(nv, "MinTransportBlocks", ...
            localEntrySamplingValue(opt.EntrySampling, entryId, ...
            "min_transport_blocks", opt.MinTransportBlocks));
        nv = localOptionalNV(nv, "MaxTransportBlocks", ...
            localEntrySamplingValue(opt.EntrySampling, entryId, ...
            "max_transport_blocks", opt.MaxTransportBlocks));
        nv = localOptionalNV(nv, "BatchSize", ...
            localEntrySamplingValue(opt.EntrySampling, entryId, ...
            "batch_size", opt.BatchSize));
        nv = localOptionalNV(nv, "MaxConfidenceHalfWidth", ...
            localEntrySamplingValue(opt.EntrySampling, entryId, ...
            "max_confidence_half_width", opt.MaxConfidenceHalfWidth));
        result = sixgr.conformance.runFRCPoint(entryId, string(entry.condition.id), nv{:});
        rows(index).RequiredSNR_dB = double(result.RequiredSNR_dB);
        rows(index).MeasuredSNR_dB = double(result.MeasuredSNRAtTarget_dB);
        rows(index).Delta_dB = double(result.Delta_dB);
        rows(index).DataChannelExact = logical(result.DataChannelExecution.Exact);
        rows(index).FullStandardExecutionExact = logical(result.StandardExecution.Exact);
        rows(index).StatisticallyQualified = logical( ...
            result.ReferencePointStatisticallyQualified);
        rows(index).OneSidedReferencePass = logical(result.ReferencePointPass);
        rows(index).SymmetricRegressionPass = logical(result.ProjectDiagnosticPass);
        rows(index).SymmetricRegressionRequired = logical( ...
            opt.RequireSymmetricRegression);
        rows(index).SymmetricRegressionStatisticallyQualified = logical( ...
            result.ProjectDiagnosticStatisticallyQualified);
        rows(index).TransportBlocks = sum(double(result.Sweep.TransportBlocks));
        rows(index).BlockErrors = sum(double(result.Sweep.FailedTransportBlocks));
        if rows(index).FullStandardExecutionExact
            rows(index).EvidenceClass = ...
                "ACTUAL_FRC_FULL_STANDARD_TRUTH_EXECUTION";
        else
            rows(index).EvidenceClass = ...
                "ACTUAL_FRC_SELECTED_DATA_CHANNEL_TRUTH_EXECUTION";
        end
        rows(index).Pass = lower(string(opt.Profile)) == "full" && ...
            rows(index).FullStandardExecutionExact && ...
            rows(index).DataChannelExact && rows(index).StatisticallyQualified && ...
            rows(index).OneSidedReferencePass && ...
            (~rows(index).SymmetricRegressionRequired || ...
            rows(index).SymmetricRegressionPass);
        rows(index).Status = localState(rows(index).Pass);
        if ~rows(index).Pass
            rows(index).FailureReason = localResultFailure( ...
                result, opt.Profile, logical(opt.RequireSymmetricRegression));
        end
    catch ME
        rows(index).Pass = false;
        rows(index).Status = "FAIL";
        rows(index).EvidenceClass = "ACTUAL_FRC_EXECUTION_FAILURE";
        rows(index).FailureIdentifier = string(ME.identifier);
        rows(index).FailureReason = string(ME.message);
    end
end

T = struct2table(rows);
if lower(string(opt.Profile)) == "full"
    outputPath = fullfile(layout.ReportCSVDir, "frc_reference_qualification.csv");
else
    outputPath = fullfile(layout.ReportCSVDir, "frc_reference_diagnostic.csv");
end
sixgr.util.csvWriteTable(outputPath, T, "PreserveSchema", true);
out = struct("Table", T, "OutputPath", string(outputPath), ...
    "Profile", lower(string(opt.Profile)), "AllPassed", all(T.Pass), ...
    "CatalogSHA256", string(catalogDigest));
end

function value = localExecutionProfile(profile)
if lower(string(profile)) == "full", value = "full"; else, value = "smoke"; end
end

function args = localOptionalNV(args, name, value)
if ~isempty(value), args(end+1:end+2) = {name, value}; end
end

function value = localEntrySamplingValue(raw, entryId, fieldName, defaultValue)
value = defaultValue;
if isempty(raw)
    return;
end
if iscell(raw)
    items = raw(:);
else
    items = num2cell(raw(:));
end
matches = false(numel(items),1);
for index = 1:numel(items)
    item = items{index};
    if ~isstruct(item) || ~isscalar(item) || ~isfield(item,"entry_id")
        error("sixgr:conformance:InvalidEntrySampling", ...
            "Each EntrySampling row must be a scalar struct with entry_id.");
    end
    matches(index) = string(item.entry_id) == string(entryId);
end
if nnz(matches) > 1
    error("sixgr:conformance:DuplicateEntrySampling", ...
        "EntrySampling contains duplicate rows for '%s'.", entryId);
end
if ~any(matches)
    return;
end
item = items{find(matches,1)};
if isfield(item, char(fieldName)) && ~isempty(item.(char(fieldName)))
    value = item.(char(fieldName));
end
end

function entry = localCatalogEntry(entries, id)
matches = false(numel(entries), 1);
for index = 1:numel(entries)
    candidate = localSequenceItem(entries, index);
    matches(index) = string(candidate.id) == string(id);
end
if nnz(matches) ~= 1
    error("sixgr:conformance:QualificationEntryNotFound", ...
        "Expected one catalog entry with id '%s'; found %d.", id, nnz(matches));
end
entry = localSequenceItem(entries, find(matches, 1));
end

function value = localSequenceItem(sequence, index)
if iscell(sequence), value = sequence{index}; else, value = sequence(index); end
end

function ids = localMandatoryAWGNEntries()
ids = ["dl_r_pdsch_1_1_4_fdd_awgn"; ...
    "dl_r_pdsch_1_3_6_fdd_atg_awgn"; ...
    "dl_r_pdsch_1_4_1_fdd_atg_awgn"; ...
    "ul_g_fr1_a3a_1_awgn"; ...
    "ul_g_fr1_a13_1_atg_awgn"];
end

function reason = localResultFailure(result, profile, requireSymmetricRegression)
parts = strings(0, 1);
if lower(string(profile)) ~= "full", parts(end+1,1) = "diagnostic_profile_not_qualification"; end %#ok<AGROW>
if ~logical(result.StandardExecution.Exact), parts(end+1,1) = "full_standard_execution_not_exact"; end %#ok<AGROW>
if ~logical(result.DataChannelExecution.Exact), parts(end+1,1) = "data_channel_not_exact"; end %#ok<AGROW>
if ~logical(result.StatisticallyQualified), parts(end+1,1) = "statistical_qualification_not_met"; end %#ok<AGROW>
if ~logical(result.ReferencePointPass), parts(end+1,1) = "one_sided_reference_point_failed"; end %#ok<AGROW>
if logical(requireSymmetricRegression) && ...
        ~logical(result.ProjectDiagnosticPass)
    parts(end+1,1) = "required_symmetric_reference_regression_failed"; %#ok<AGROW>
end
reason = strjoin(unique(parts, "stable"), ";");
end

function state = localState(pass)
if pass, state = "PASS"; else, state = "FAIL"; end
end

function row = localEmptyRow()
row = struct("EntryId","", "FRC","", "Condition","", "Required",true, ...
    "Profile","", "ExecutionAttempted",false, "DataChannelExact",false, ...
    "FullStandardExecutionExact",false, ...
    "StatisticallyQualified",false, "OneSidedReferencePass",false, ...
    "SymmetricRegressionRequired",false, ...
    "SymmetricRegressionStatisticallyQualified",false, ...
    "SymmetricRegressionPass",false, "RequiredSNR_dB",NaN, ...
    "MeasuredSNR_dB",NaN, "Delta_dB",NaN, "TransportBlocks",0, ...
    "BlockErrors",0, "Pass",false, "Status","NOT_EVALUATED", ...
    "EvidenceClass","", "CatalogSHA256","", "FailureIdentifier","", ...
    "FailureReason","");
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:conformance:InvalidQualificationOutputRoot", ...
        "runFolder must be a character vector or string scalar.");
end
end
