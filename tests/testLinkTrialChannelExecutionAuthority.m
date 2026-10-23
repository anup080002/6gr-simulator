function [ok, checks] = testLinkTrialChannelExecutionAuthority()
%TESTLINKTRIALCHANNELEXECUTIONAUTHORITY Declared publication-boundary cases.
% No channel object, waveform, decoder, or physical receipt is executed here.
% Object-class/source strings describe constructed state, not executed PHY.
% This reproducer is expected to fail while the canonical finalizer infers
% ChannelModelApplied/ChannelFadingApplied from configured/object metadata.

setup6GRSimToolkit('Verbose', false);
cfg = struct('channel', struct('model', "TDL-C", 'awgnOnly', false));
prototype = struct('Case', "", 'Direction', "", 'Passed', false, ...
    'FailureID', "", 'FailureDetail', "", ...
    'EvidenceScope', "declared_row_publication_boundary_no_channel_execution");
rows = repmat(prototype, 0, 1);
for direction = ["DL", "UL"]
    for model = ["TDL-C", "CDL-C"]
        declared = localRow(model, "", false, false, "not_requested");
        record("constructed_object_is_not_channel_execution_" + model, ...
            direction, @() localCheck(declared, cfg, direction));
        declared.Crash = true;
        declared.ChannelFadingExecutionStatus = "attempted_failed";
        record("crash_cannot_acquire_applied_model_" + model, ...
            direction, @() localCheck(declared, cfg, direction));
    end

    % An actual execution result takes precedence over a separately retained
    % configuration/model-object description. Never OR explicit false to true.
    declared = localRow("TDL-C", "AWGN", false, false, "not_requested");
    record("explicit_nonfading_result_survives_constructed_TDL_metadata", ...
        direction, @() localCheck(declared, cfg, direction));
    declared = localRow("TDL-C", "CDL-C", true, false, "applied_runtime_channel_object");
    record("explicit_applied_model_and_true_preserved", ...
        direction, @() localCheck(declared, cfg, direction));
    awgnCfg = struct('channel', struct('model', "AWGN", 'awgnOnly', true));
    record("callback_configuration_cannot_erase_original_execution", ...
        direction, @() localCheck(declared, awgnCfg, direction));
    record("missing_execution_columns_remain_missing", ...
        direction, @() localMissingExecutionColumns(cfg, direction));
end

empty = table('Size', [0 3], 'VariableTypes', {'string','logical','string'}, ...
    'VariableNames', {'ChannelModelApplied','ChannelFadingApplied','ChannelFadingExecutionStatus'});
assert(isequaln(empty, sixgr.truth.SharedDataCompletionRuntime.repairLinkTrialEvidenceColumns( ...
    empty, "DL", cfg)), 'sixgr:test:ChannelExecutionAuthority:EmptyMutation', ...
    'Empty evidence must remain empty without an invented execution row.');

checks = struct2table(rows);
failures = checks(~checks.Passed, :);
for k = 1:height(failures)
    fprintf(2, '%s | %s | %s | %s\n', char(failures.Direction(k)), ...
        char(failures.Case(k)), char(failures.FailureID(k)), char(failures.FailureDetail(k)));
end
assert(isempty(failures), 'sixgr:test:ChannelExecutionAuthority:Promotion', ...
    '%d of %d declared channel-publication checks failed; no channel execution was performed.', ...
    height(failures), height(checks));
ok = true;

    function record(name, direction, operation)
        row = prototype; row.Case = name; row.Direction = direction;
        try
            operation(); row.Passed = true;
        catch ME
            row.FailureID = string(ME.identifier);
            row.FailureDetail = string(ME.message);
        end
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end

function row = localRow(configured, applied, fading, crash, status)
className = "nrTDLChannel";
if startsWith(configured, "CDL"), className = "nrCDLChannel"; end
row = table(configured, applied, logical(fading), string(status), logical(crash), ...
    className, "declared_constructed_object_metadata_not_execution", ...
    "runtime_array_shape_spacing_orientation_coupled", ...
    'VariableNames', {'ChannelModel','ChannelModelApplied','ChannelFadingApplied', ...
    'ChannelFadingExecutionStatus','Crash','ChannelObjectClass','ChannelObjectSource', ...
    'ChannelArrayHandlingStatus'});
end

function localCheck(input, cfg, direction)
output = sixgr.truth.SharedDataCompletionRuntime.repairLinkTrialEvidenceColumns( ...
    input, direction, cfg);
assert(height(output) == height(input), ...
    'sixgr:test:ChannelExecutionAuthority:RowMutation', 'Publication must preserve source row count.');
for name = ["ChannelModelApplied", "ChannelFadingApplied", "ChannelFadingExecutionStatus", ...
        "ChannelModel", "ChannelObjectClass", "ChannelObjectSource", "ChannelArrayHandlingStatus", "Crash"]
    assert(isequaln(output.(name), input.(name)), ...
        'sixgr:test:ChannelExecutionAuthority:EvidenceMutation', ...
        'Publication changed original %s using configured/constructed channel metadata.', char(name));
end
end

function localMissingExecutionColumns(cfg, direction)
input = table("TDL-C", "nrTDLChannel", false, ...
    'VariableNames', {'ChannelModel','ChannelObjectClass','Crash'});
output = sixgr.truth.SharedDataCompletionRuntime.repairLinkTrialEvidenceColumns(input, direction, cfg);
assert(~any(ismember(["ChannelModelApplied", "ChannelFadingApplied", "ChannelFadingExecutionStatus"], ...
    string(output.Properties.VariableNames))), ...
    'sixgr:test:ChannelExecutionAuthority:MissingExecutionInvented', ...
    'Absent historical execution operands must not become an applied-channel claim.');
end
