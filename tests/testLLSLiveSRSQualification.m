function [ok, result] = testLLSLiveSRSQualification()
% Declared reporting fixtures only: no waveform, channel or receiver runs.
% Exercise the real live exporter and persisted CSV, not a copied reducer.
cfg = sixgr.config.defaultConfig();
% The generic exporter also inspects configured channel metadata. Keep that
% unrelated path empty; this test supplies no executed channel/reference.
cfg.channel.type = 'AWGN';
cfg.channel.model = 'AWGN';
cfg.channel.awgnOnly = true;
cfg.channel.fading.enable = false;
root = fullfile(pwd, 'results', 'validation', 'live_srs_qualification', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS')));
assert(exist(root, 'dir') == 0, 'Refuse to overwrite prior test evidence.');
mkdir(root);

mixed = fixture([-Inf;-20;-10;30;NaN;Inf], 0);
mixed.ChannelNMSEReferenceAvailable = [1;1;1;0;1;1];
mixed.Status(3) = "FAIL";
mixed.SINR_dB = [1;2;3;1000;NaN;Inf];
zero = fixture([-Inf;-Inf;-Inf], 10);
unknownThreshold = fixture([-10;-20], 20);
unknownThreshold.ChannelNMSEThreshold_dB = [NaN;Inf];
ordered = fixture((-100:-1).', 30);
ordered.ChannelNMSEThreshold_dB(:) = 0;
nearby = fixture(-7, 30 + 1e-10);
nearby.ChannelNMSEThreshold_dB(:) = 0;
source = [mixed;zero;unknownThreshold;ordered;nearby];
expectedMean = 10*log10((0 + .01 + .1)/3);
out = publish(source, 'mixed_points');
checkMixed(out.ChannelEstimationStats, out.CSIRSStats);
checkMixed(read(out.ChannelEstimationStatsPath), read(out.CSIRSStatsPath));
audit = read(out.SRSChannelQualificationDiagnosticsPath);
assert(height(audit) == 1 && audit.SourceTrialCount == 112 && ...
    audit.MeasuredTrials == 109 && audit.QualifiedTrials == 106 && ...
    audit.FailedTrials == 1 && audit.UnreferencedNumericTrials == 1 && ...
    ~audit.CountsTowardCoverage && ~audit.StatisticalIndependenceClaimed && ...
    ~audit.ConfidenceIntervalAvailable && ...
    ~ismember('NMSE_dB', audit.Properties.VariableNames));

% Missing authority, unknown authority and explicit false cannot be rescued
% by finite NMSE, PASS, CQI, a known threshold or an operating-point label.
for mode = ["missing", "unknown", "false"]
    source = mixed;
    source.Status(:) = "PASS";
    if mode == "missing"
        source = removevars(source, 'ChannelNMSEReferenceAvailable');
    elseif mode == "unknown"
        source.ChannelNMSEReferenceAvailable(:) = NaN;
    else
        source.ChannelNMSEReferenceAvailable(:) = 0;
    end
    out = publish(source, "no_authority_" + mode);
    for persisted = [false true]
        if persisted
            C = read(out.ChannelEstimationStatsPath); F = read(out.CSIRSStatsPath);
        else
            C = out.ChannelEstimationStats; F = out.CSIRSStats;
        end
        assert(~any(string(C.Direction) == "SRS" & string(C.Metric) == "NMSE_dB"));
        F = F(string(F.TraceSource) == "srs_feedback_path", :);
        assert(height(F) == 1 && isnan(number(F.MeanNMSE_dB)) && ...
            number(F.NMSEMeasurementAvailable) == 0 && number(F.NMSESampleCount) == 0 && ...
            number(F.NMSEQualifiedTrials) == 0 && F.SampleCount == height(source));
        assert(F.MeanWidebandCQI == 11 && isnan(F.MeanPMI) && ...
            F.MeanPMIStatus=="not_applicable_discrete_identity_mean_removed", ...
            'Do not average identifiers, including a uniform-valued source population.');
        selections=out.CSISelectionObservations;
        selected=selections(selections.SourceField=="EstimatedTPMI",:);
        assert(height(selected)==height(source)&&all(selected.ValueNumeric==3)&& ...
            isequal(selected.SourceRowIndex,(1:height(source)).'), ...
            'Unavailable reference NMSE must not erase original practical selection observations.');
    end
end

% Original numeric scalar CSV text is supported; it is not ASCII data.
source = mixed;
source.NMSE_dB = cellstr(string(source.NMSE_dB));
source.ChannelNMSEReferenceAvailable = string(source.ChannelNMSEReferenceAvailable);
source.ChannelNMSEThreshold_dB = cellstr(string(source.ChannelNMSEThreshold_dB));
out = publish(source, 'scalar_text');
C = select(out.ChannelEstimationStats, 0);
assert(same(C.MeanValue, expectedMean) && C.SampleCount == 3 && C.P05Value == -Inf);

% No original axis means no invented SNR/measurement row. The complete
% source still enters the separate authority diagnostics, including FAIL.
source = removevars(mixed, {'ConfiguredSNR_dB','SNR_dB','SINR_dB'});
out = publish(source, 'no_axis');
assert(isempty(out.ChannelEstimationStats) && isempty(out.CSIRSStats));
assert(out.SRSChannelQualificationDiagnostics.MeasuredTrials == 3 && ...
    out.SRSChannelQualificationDiagnostics.FailedTrials == 1);

% Validate malformed evidence even when no grouping axis would emit a row.
bad = source; bad.ChannelNMSEReferenceAvailable(1) = 2;
reject(@() sixgr.truth.exportLLSLiveDerivedTables(cfg, fullfile(root,'invalid_authority'), ...
    struct('SRS',bad)), 'sixgr:truth:InvalidSRSReferenceAuthority');
bad = mixed; bad.NMSE_dB = [bad.NMSE_dB bad.NMSE_dB];
reject(@() sixgr.truth.exportLLSLiveDerivedTables(cfg, fullfile(root,'invalid_shape'), ...
    struct('SRS',bad)), 'sixgr:report:InvalidSRSMeasurementColumn');
out = publish(mixed([], :), 'empty');
assert(isempty(out.ChannelEstimationStats) && isempty(out.CSIRSStats) && ...
    isstring(out.ChannelEstimationStats.Metric) && ...
    isnumeric(out.ChannelEstimationStats.NMSESampleCount) && ...
    out.SRSChannelQualificationDiagnostics.SourceTrialCount == 0);
ok = true;
result = struct('Root', string(root), 'Scope', ...
    "declared_SRS_report_fixtures_no_PHY_or_statistical_qualification", ...
    'WaveformExecutions', 0);
fprintf('testLLSLiveSRSQualification PASS; declared reporting fixtures, waveform_executions=0\n');

    function out = publish(source, label)
        original = source;
        folder = fullfile(root, char(label));
        layout = sixgr.report.resultLayout(folder);
        sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
        sourceFile = fullfile(layout.AirInterfaceCSVDir, 'srs_trials.csv');
        sixgr.util.csvWriteTable(sourceFile, source, 'PreserveSchema', true, 'RoundTripNumericText', true);
        sourceHash = sixgr.util.sha256File(sourceFile);
        before = rng;
        out = sixgr.truth.exportLLSLiveDerivedTables(cfg, folder, struct('SRS',source));
        assert(isequaln(source,original) && isequaln(rng,before), ...
            'Live reporting must not mutate the source or consume PHY RNG.');
        assert(string(sourceHash) == string(sixgr.util.sha256File(sourceFile)), ...
            'Live authority gating must not rewrite original trial evidence.');
    end

    function checkMixed(C, F)
        C = C(string(C.Direction) == "SRS" & string(C.Metric) == "NMSE_dB", :);
        F = F(string(F.TraceSource) == "srs_feedback_path", :);
        assert(height(C) == 5 && height(F) == 5);
        c = C(C.SNR_dB == 0, :); f = F(F.SNR_dB == 0, :);
        assert(same(c.MeanValue,expectedMean) && c.P05Value == -Inf && ...
            c.P95Value == -10 && c.SampleCount == 3 && ...
            c.QualitySampleCount == 3 && c.QualityMean_dB == 2);
        assert(same(f.MeanNMSE_dB,expectedMean) && f.SampleCount == 6 && ...
            f.NMSESampleCount == 3 && f.NMSEQualifiedTrials == 2);
        assert(c.NMSESampleCount == 3 && c.NMSEQualifiedTrials == 2 && ...
            c.NMSEMeasurementAvailable == 1);
        c = C(C.SNR_dB == 10, :); f = F(F.SNR_dB == 10, :);
        assert(c.MeanValue == -Inf && c.P05Value == -Inf && c.P95Value == -Inf && ...
            f.MeanNMSE_dB == -Inf && c.SampleCount == 3 && f.NMSESampleCount == 3);
        c = C(C.SNR_dB == 20, :); f = F(F.SNR_dB == 20, :);
        assert(same(c.MeanValue,10*log10((.1+.01)/2)) && c.NMSEQualifiedTrials == 0 && ...
            f.NMSEMeasurementAvailable == 1 && f.NMSEQualifiedTrials == 0);
        c = C(C.SNR_dB == 30, :);
        assert(c.P05Value == -96 && c.P95Value == -6 && c.SampleCount == 100);
        c = C(C.SNR_dB == 30 + 1e-10, :);
        assert(c.MeanValue == -7 && c.SampleCount == 1, ...
            'Close distinct original points must not duplicate/populate each other.');
        assert(all(string(C.NMSEAggregation) == "equal_trial_mean_linear_normalized_error") && ...
            all(string(C.NMSEReferenceGate) == "original_ChannelNMSEReferenceAvailable_equals_one") && ...
            all(string(C.NMSEPercentileDefinition) == ...
                "empirical_inverse_CDF_of_normalized_error_power_rank_ceil_p_N") && ...
            all(C.StatisticalIndependenceClaimed == 0) && all(C.ConfidenceIntervalAvailable == 0));
        assert(all(F.StatisticalIndependenceClaimed == 0) && all(F.ConfidenceIntervalAvailable == 0));
    end
end

function T = fixture(values, point)
n = numel(values);
T = table(double(values(:)), ones(n,1), repmat(-8,n,1), repmat("PASS",n,1), ...
    repmat(double(point),n,1), repmat(double(point),n,1), ones(n,1), ...
    repmat(11,n,1), repmat(3,n,1), repmat("declared_reporting_fixture_not_PHY",n,1), ...
    'VariableNames', {'NMSE_dB','ChannelNMSEReferenceAvailable','ChannelNMSEThreshold_dB', ...
    'Status','ConfiguredSNR_dB','SNR_dB','SINR_dB','WidebandCQI','EstimatedTPMI','Source'});
end

function T = read(path)
T = sixgr.util.csvReadTable(path, 'TextType', 'string');
end

function row = select(T, point)
row = T(string(T.Direction) == "SRS" & string(T.Metric) == "NMSE_dB" & T.SNR_dB == point, :);
end

function value = number(raw)
value = sixgr.truth.numericMeasurementColumn(raw, 'test_readback');
end

function tf = same(actual, expected)
tf = isscalar(actual) && (isequaln(actual,expected) || ...
    (isfinite(actual) && isfinite(expected) && abs(actual-expected) < 1e-12));
end

function reject(fn, id)
try
    fn();
catch cause
    if ~strcmp(cause.identifier,id), rethrow(cause); end
    return;
end
error('testLLSLiveSRSQualification:ExpectedRejection', 'Expected %s.', id);
end
