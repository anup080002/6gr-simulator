function ok = testRARuntimeOccasionBinding()
% New-attempt clock binding; preparation is not reception or qualification.
setup6GRSimToolkit('Verbose', false);
cfg = raStrictAnchorConfig();
cfg.phy.duplex.mode = 'TDD';
base = sixgr.mac.ra.RAConfig(cfg);
assert(isequaln(base, sixgr.mac.ra.RAConfig(cfg, 'RuntimeSlot', NaN)), ...
    'Offline callers must retain the configured occasion without rebinding.');
period = base.PRACHOccasionResolution.PeriodCarrierSlots;
first = base.PRACHAbsoluteSlot;
for runtimeSlot = [1 first+1 first+2 first+period+1 first+3*period+2]
    actual = sixgr.mac.ra.RAConfig(cfg, 'RuntimeSlot', runtimeSlot);
    expected = first + max(0, ceil((runtimeSlot-1-first)/period))*period;
    assert(actual.PRACHAbsoluteSlot == expected && expected >= runtimeSlot-1);
    assert(actual.RACHConfigHash == base.RACHConfigHash && actual.RARNTI == base.RARNTI, ...
        'Repeating a selected resource must not change broadcast config or the within-frame RA-RNTI.');
    assert(actual.PRACHOccasionSymbol == base.PRACHOccasionSymbol && ...
        actual.PRACHFrequencyIndex == base.PRACHFrequencyIndex);
    assert(actual.Msg2Slot > expected && actual.Msg3Slot > actual.Msg2Slot && ...
        actual.Msg4Slot >= actual.Msg3Slot);
end
for invalid = [-1 0 0.5 Inf]
    caught = false;
    try
        sixgr.mac.ra.RAConfig(cfg, 'RuntimeSlot', invalid);
    catch cause
        caught = strcmp(cause.identifier, 'sixgr:mac:ra:InvalidRuntimeSlot');
    end
    assert(caught, 'Invalid runtime coordinates must not be rounded or clamped.');
end
bad = base;
bad.PRACHAbsoluteSlot = bad.PRACHAbsoluteSlot+1;
caught = false;
try
    sixgr.phy.ra.generateMsg1PRACHWaveform(cfg, bad);
catch cause
    caught = strcmp(cause.identifier, 'sixgr:phy:ra:PRACHOccasionTimeMismatch');
end
assert(caught, 'A mismatched waveform occasion must not be published under a different slot.');
badCfg = cfg;
badCfg.phy.prach.timing = base.PRACHOccasionResolution;
badCfg.phy.prach.timing.PeriodCarrierSlots = NaN;
caught = false;
try
    sixgr.mac.ra.RAConfig(badCfg, 'RuntimeSlot', first+period+1);
catch cause
    caught = strcmp(cause.identifier, 'sixgr:mac:ra:InvalidPRACHRepetitionPeriod');
end
assert(caught, 'Missing period authority must fail instead of assuming one frame.');

% Exercise the real producer, not a rewritten row. The previous code put
% this second-period attempt in the already elapsed first period.
runtimeSlot = first + period + 1;
[prepared, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
    'RuntimeSlot', runtimeSlot, 'StageAction', 'prepare_next_stage', ...
    'WriteArtifacts', false);
expectedSlot = runtimeSlot-1;
assert(prepared.PreparedTransmission.AbsoluteSlot == expectedSlot && ...
    prepared.Msg1ScheduledSlot == expectedSlot);
assert(prepared.PreparedTransmission.StartTime_s == ...
    expectedSlot*sixgr.time.slotDurationSec(cfg));
assert(checkpoint.PreparedContext.Occasion.SlotIndex0 == expectedSlot && ...
    checkpoint.RAConfig.PRACHAbsoluteSlot == expectedSlot);
assert(~isempty(prepared.PreparedTransmission.Waveform) && ...
    all(isfinite(prepared.PreparedTransmission.Waveform), 'all'));
assert(isempty(prepared.RuntimeStageRows) && ~prepared.RACompleted && ~prepared.RRCConnected);

% A resumed attempt is not a new attempt. A later caller clock must leave
% its prepared transmission and RA-RNTI unchanged, without propagating it.
[resumed, retained] = sixgr.phy.ra.runFourStepRA(cfg, ...
    'Continuation', checkpoint, 'RuntimeSlot', runtimeSlot+period, ...
    'StageAction', 'prepare_next_stage');
assert(isequaln(resumed.PreparedTransmission, prepared.PreparedTransmission) && ...
    isequaln(retained.RAConfig, checkpoint.RAConfig));

% Authored production profiles: configuration-only checks in both modes.
% No FDD waveform or scenario is executed by this test.
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
for name = ["lls_causal_access_to_data_wiring_tdd", "lls_causal_access_to_data_wiring"]
    scfg = sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
        'simulator', 'configs', 'scenarios', name + '.yaml'));
    profile = sixgr.config.normalizeConfig(sixgr.lls6g.buildInternalConfig(scfg, root));
    anchor = sixgr.mac.ra.RAConfig(profile);
    current = anchor.PRACHAbsoluteSlot + anchor.PRACHOccasionResolution.PeriodCarrierSlots + 1;
    bound = sixgr.mac.ra.RAConfig(profile, 'RuntimeSlot', current);
    assert(bound.PRACHAbsoluteSlot == current-1);
    if endsWith(name, '_tdd')
        bound = sixgr.mac.ra.RAConfig(profile, 'RuntimeSlot', 15);
        assert(bound.PRACHAbsoluteSlot == 14 && bound.PRACHOccasionFrame == 1 && ...
            bound.PRACHOccasionSlot == 4, 'The failed run must bind slot 15 to 14 ms, not 4 ms.');
        [tx, occasion] = sixgr.phy.ra.generateMsg1PRACHWaveform(profile, bound);
        assert(~isempty(tx.Waveform) && occasion.SlotIndex0 == 14 && ...
            occasion.Carrier.NFrame == 1 && occasion.Carrier.NSlot == 4);
    end
end
ok = true;
disp('RARuntimeOccasionBinding PASS: absolute repetition, actual TDD Msg1 preparation, retained continuation, TDD/FDD config.');
end
