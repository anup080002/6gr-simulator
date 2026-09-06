function ok = testSystemSchedulerFailureStatus()
% Scheduler exceptions are execution failures, not successful empty runs.
setup6GRSimToolkit('Verbose', false);
cfg = withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
assert(isequal(string(cfg.phy.pdcch.dciFormats(:)), ["1_1";"0_1"]) && ...
    string(cfg.phy.pdcch.dciFormat) == "1_1", ...
    'The canonical bidirectional spatial default must monitor its DL/UL grant formats.');
cfg.scenario.layout.nSites = 1;
cfg.scenario.layout.nSectorsPerSite = 1;
cfg.scenario.layout.wrapAround = false;
cfg.scenario.ue.nUE = 1;
cfg.scenario.nUE = 1;
cfg.run.shortRun = false;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.outputs.saveFIG = false;
cfg.outputs.exportSLSOutputCatalog = false;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
for direction = ["DL", "UL"]
    invalid = cfg;
    % Deliberately omit the active direction from a UE search space.
    % This unit test must provoke the real scheduler contract, not a mock.
    if direction == "DL"
        invalid.phy.pdcch.dciFormats = {'0_1'};
        invalid.phy.pdcch.dciFormat = '0_1';
    else
        invalid.phy.pdcch.dciFormats = {'1_1'};
        invalid.phy.pdcch.dciFormat = '1_1';
    end
    ctx = sixgr.core.SimContext(invalid, 'RunFolder', fullfile(root, direction));
    ctx.Logger.EchoToConsole = false;
    result = sixgr.system.SystemLevelRunner.run(ctx, struct( ...
        'NumTTI', 3, 'PHYBackend', 'waveform', ...
        'OfferedBitsDL', repmat(4000 * double(direction == "DL"), 3, 1), ...
        'OfferedBitsUL', repmat(4000 * double(direction == "UL"), 3, 1)));
    expected = direction + " scheduling failed";
    assert(~result.Ok && any(contains(string(result.Errors), expected) & ...
        contains(string(result.Errors), 'sixgr:SchedulerBase:RequiredDCIFormatNotMonitored')), ...
        'An actual %s scheduler exception must fail the run and retain its identifier. Errors: %s', ...
        direction, strjoin(string(result.Errors), ' | '));
    assert(isempty(result.Details.SchedulerGrants), ...
        'A rejected DCI configuration must not produce substitute waveform grants.');
end
ok = true;
fprintf('PASS testSystemSchedulerFailureStatus: real DL/UL scheduler failures invalidate the run without substitute grants.\n');
end
