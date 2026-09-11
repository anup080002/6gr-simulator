function ok = testRAStageContinuation()
% Actual coded self-loop waveforms qualify continuation semantics, not RF.
setup6GRSimToolkit('Verbose', false);
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
stages = ["Msg1", "Msg2", "Msg3", "Msg4", "RRCSetupComplete"];
for mode = ["TDD", "FDD"]
    cfg = raStrictAnchorConfig();
    cfg.phy.duplex.mode = mode;
    cfg.initial_access.rrc.require_setup_complete = true;
    cfg.initial_access.rrc.transaction_id = 1;
    cfg.initial_access.rrc.srb1_lcid = 1;
    cfg.random_access.timing.setup_complete_k2_slots = 2;
    if mode == "FDD"
        cfg.frequency.band_name = "n1";
        cfg.frequency.center_frequency_hz = 2.1e9;
        cfg.channel.fc_Hz = 2.1e9;
        cfg.phy.fc_Hz = 2.1e9;
        % Case A below 3 GHz has four SSB candidates.  Do not retain the
        % n78 eight-candidate fixture while changing the operating band.
        cfg.phy.ssb.Lmax = 4;
        cfg.phy.ssb.activeBitmap = "1000";
    end
    cfg.outputs.saveCSV = false;
    cfg.outputs.saveMAT = false;
    cfg.outputs.saveFigures = false;
    folder = fullfile(root, mode);
    rng(7314, 'twister');
    whole = sixgr.phy.ra.runFourStepRA(cfg, 'RunFolder', folder, ...
        'RunId', 'stage_equivalence', 'WriteArtifacts', false);
    assert(whole.StrictOk && whole.RRCConnected, ...
        'The complete-attempt coded waveform reference must pass before comparing staged execution.');
    assert(whole.RASlotTimeBase == "absolute_zero_based" && ...
        whole.Msg1ScheduledSlot == whole.RuntimeStageRows.StageSlot(1), ...
        'Both duplex modes must publish explicit coordinates tied to their actual Msg1 waveform.');
    rng(7314, 'twister');
    [partial, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
        'RunFolder', folder, 'RunId', 'stage_equivalence', ...
        'WriteArtifacts', false, 'StopAfterStage', 'Msg1');
    for index = 1:4
        assert(partial.RuntimeExecutionState == "pending_next_stage");
        assert(height(partial.RuntimeStageRows) == index && ...
            isequal(string(partial.RuntimeStageRows.StageName), stages(1:index).'));
        assert(partial.NextRuntimeStage == stages(index+1));
        assert(istable(partial.Events) && ~isempty(partial.Events));
        assert(~isempty(partial.ObservedREAllocationTable) && ...
            isequaln(partial.ObservedREAllocationTable, whole.ObservedREAllocationTable), ...
            'The measured Msg1 grid must be available before later RA stages execute.');
        assert(~partial.StrictOk && ~partial.RRCConnected, ...
            'Pending stages must not publish complete-attempt or RRC success.');
        assert(~isfield(partial, 'ArtifactTables') || isempty(fieldnames(partial.ArtifactTables)), ...
            'Do not finalize unexecuted stages into full-attempt artifact tables.');
        if index < 4, assert(~partial.RACompleted); end
        beforeRows = partial.RuntimeStageRows;
        if index == 1
            changed = cfg;
            changed.random_access.preamble_index = cfg.random_access.preamble_index + 1;
            localReject(@() localResume(changed, checkpoint, 'Msg2'), ...
                "sixgr:phy:ra:RAContinuationConfigChanged");
            localReject(@() localResume(cfg, checkpoint, 'Msg1'), ...
                "sixgr:phy:ra:RAStageAlreadyExecuted");
            bad = checkpoint;
            bad.ContractVersion = "untrusted";
            localReject(@() localResume(cfg, bad, 'Msg2'), ...
                "sixgr:phy:ra:InvalidRAContinuation");
            % A plain saved checkpoint must resume without running Msg1
            % again. Channel-object persistence is tested separately.
            checkpointFile = fullfile(root, 'ra_checkpoint.mat');
            save(checkpointFile, 'checkpoint');
            restored = load(checkpointFile, 'checkpoint');
            checkpoint = restored.checkpoint;
        end
        [partial, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
            'Continuation', checkpoint, 'StopAfterStage', stages(index+1), ...
            'RuntimeSlot', partial.NextRuntimeStageSlot+1);
        assert(isequaln(beforeRows, partial.RuntimeStageRows(1:index,:)), ...
            'Already executed stage evidence must survive resume unchanged.');
    end
    assert(isempty(fieldnames(checkpoint)) && partial.RuntimeExecutionState == "terminal");
    assert(partial.StrictOk && partial.RRCConnected && height(partial.RuntimeStageRows) == 5);
    assert(isequaln(whole.RuntimeStageRows, partial.RuntimeStageRows));
    assert(isequaln(whole.Events, partial.Events) && isequaln(whole.TimerEvents, partial.TimerEvents));
    eventNames = ["rar_pdcch_pdsch_decode", "pusch_ulsch_decode", ...
        "contention_resolution_identity_match", "pusch_ulsch_srb1_ul_dcch_decode"];
    for stage = 2:5
        row = partial.Events(partial.Events.Event == eventNames(stage-1), :);
        measuredSlot = partial.RuntimeStageRows.StageSlot(stage);
        slotsPerFrame = 10*cfg.phy.carrier.SubcarrierSpacing/15;
        assert(height(row) == 1 && row.Frame*slotsPerFrame + row.Slot == measuredSlot, ...
            'Decoded-stage events must identify their actual source waveform slot, including frame wraps.');
        assert(isnan(row.Symbol), 'A slot-level decoder event must not inherit the Msg1 symbol.');
    end
    for field = ["Msg1Tx", "Msg2Tx", "Msg3Tx", "Msg4Tx"]
        assert(isequaln(whole.(field).Waveform, partial.(field).Waveform), ...
            'Staged execution changed the transmitted %s waveform.', field);
    end
    assert(isequaln(whole.ObservedREAllocationTable, partial.ObservedREAllocationTable), ...
        'Finalization at a later caller slot must not relocate the original Msg1 grid evidence.');
    [failed, failedCheckpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
        'RunFolder', folder, 'WriteArtifacts', false, ...
        'FaultMode', 'wrong_rapid_in_rar', 'StopAfterStage', 'Msg1');
    assert(failed.RuntimeExecutionState == "pending_next_stage");
    [failed, failedCheckpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
        'Continuation', failedCheckpoint, 'StopAfterStage', 'Msg2');
    assert(failed.RuntimeExecutionState == "terminal" && ...
        isempty(fieldnames(failedCheckpoint)) && ~failed.StrictOk && ~failed.RACompleted, ...
        'A receiver-rejected RAR must terminate the attempt, not queue later stages.');
    assert(height(failed.RuntimeStageRows) == 2, ...
        'The rejected RAR must not execute Msg3 or Msg4 waveforms.');
    localPreparedChain(cfg, whole, folder, stages);
end
ok = true;
fprintf('RAStageContinuation PASS: TDD/FDD coded waveforms, decoded-stage resume, checkpoint round trip, no premature finalization.\n');
end

function localPreparedChain(cfg, whole, folder, stages)
rng(7314, 'twister');
[prepared, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
    'RunFolder', folder, 'RunId', 'stage_equivalence', 'WriteArtifacts', false, ...
    'ReceiveThroughTime_s', 0);
fields = ["Msg1Tx", "Msg2Tx", "Msg3Tx", "Msg4Tx", "SetupCompleteTx"];
for index = 1:5
    assert(prepared.RuntimeExecutionState == "pending_stage_receive");
    assert(height(prepared.RuntimeStageRows) == index-1 && ~prepared.RRCConnected);
    transmission = prepared.PreparedTransmission;
    assert(transmission.StageName == stages(index) && transmission.ExecutionStatus == "generated_not_propagated");
    assert(transmission.SampleCount == size(transmission.Waveform, 1) && ...
        transmission.PortCount == size(transmission.Waveform, 2) && transmission.SampleRate_Hz > 0 && ...
        transmission.Duration_s == transmission.SampleCount/transmission.SampleRate_Hz);
    % Compare on the physical integer-sample clock. Dividing absolute Tc
    % and multiplying a floating slot duration can differ by one double ULP
    % (e.g. slot 9 at 30 kHz); this is not a physical timing discrepancy.
    fs=transmission.SampleRate_Hz;
    if index==1
        prach=whole.Msg1Tx.PRACH;
        expectedStart=round(double(prach.NPRACHSlot)*double(prach.SubframesPerPRACHSlot)*1e-3*fs);
    else
        expectedStart=sixgr.phy.frame.slotStartSample(sixgr.phy.grid.makeCarrier(cfg), ...
            transmission.AbsoluteSlot,fs);
    end
    actualStart=transmission.StartTime_s*fs;
    assert(abs(actualStart-round(actualStart))<=8*eps(max(1,abs(actualStart))) && ...
        round(actualStart)==expectedStart && ...
        transmission.EndTimeExclusive_s == transmission.StartTime_s + transmission.Duration_s && ...
        transmission.TimeReference == "absolute_runtime_seconds", ...
        'Stage %s interval mismatch: start %.17g, slot start %.17g, end %.17g, duration %.17g.', ...
        stages(index),transmission.StartTime_s,transmission.AbsoluteSlot*sixgr.time.slotDurationSec(cfg), ...
        transmission.EndTimeExclusive_s,transmission.Duration_s);
    expected = whole.(fields(index)).Waveform;
    if any(index == [3,5])
        aligned = sixgr.phy.ra.applyMsg3TimingAdvance(expected, whole.TimingAdvanceSamples);
        expected = aligned.Waveform;
    end
    assert(isequaln(transmission.Waveform, expected), ...
        'Preparation changed the actual generated stage buffer.');
    if index == 1
        assert(isempty(prepared.Events) && ...
            (~isfield(prepared, 'ObservedREAllocationTable') || isempty(prepared.ObservedREAllocationTable)), ...
            'An unpropagated Msg1 must not produce received/transmitted-event or observed-grid rows.');
    end
    streamBefore = rng;
    [same, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, 'Continuation', checkpoint, ...
        'StageAction', 'prepare_next_stage');
    assert(isequaln(same.PreparedTransmission, transmission) && isequaln(rng, streamBefore), ...
        'Polling a prepared stage must not regenerate it or consume random samples.');
    beforeRuntime = checkpoint.Runtime;
    earlyTime = transmission.EndTimeExclusive_s - 1/transmission.SampleRate_Hz;
    [early, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, 'Continuation', checkpoint, ...
        'ReceiveThroughTime_s', earlyTime);
    assert(early.RuntimeExecutionState == "pending_stage_receive" && ...
        isequaln(early.PreparedTransmission, transmission) && ...
        isequaln(early.RuntimeStageRows, prepared.RuntimeStageRows) && ...
        isequaln(checkpoint.Runtime, beforeRuntime) && isequaln(rng, streamBefore), ...
        'One missing waveform sample must prevent propagation, decode and new stage evidence.');
    [held, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, 'Continuation', checkpoint);
    assert(held.RuntimeExecutionState == "pending_stage_receive" && ...
        isequaln(held.RuntimeStageRows, early.RuntimeStageRows) && ...
        isequaln(rng, streamBefore), ...
        'Omitting the receive clock on resume must retain its bound, not silently execute future stages.');
    localReject(@() localResumeBefore(cfg, checkpoint, max(0, earlyTime - 1/transmission.SampleRate_Hz)), ...
        "sixgr:phy:ra:RAReceiveClockMovedBackward");
    [decoded, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, 'Continuation', checkpoint, ...
        'StopAfterStage', stages(index), 'ReceiveThroughTime_s', transmission.EndTimeExclusive_s);
    assert(height(decoded.RuntimeStageRows) == index && isempty(fieldnames(decoded.PreparedTransmission)));
    if index < 5
        [prepared, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
            'Continuation', checkpoint, 'StageAction', 'prepare_next_stage');
        assert(isequaln(prepared.RuntimeStageRows, decoded.RuntimeStageRows));
    end
end
assert(decoded.StrictOk && decoded.RRCConnected && isempty(fieldnames(checkpoint)));
assert(isequaln(decoded.RuntimeStageRows, whole.RuntimeStageRows) && isequaln(decoded.Events, whole.Events), ...
    'Prepare/receive staging must preserve the complete measured decode/evidence sequence.');
end

function localResumeBefore(cfg, checkpoint, time)
[~, ~] = sixgr.phy.ra.runFourStepRA(cfg, 'Continuation', checkpoint, ...
    'ReceiveThroughTime_s', time);
end

function localResume(cfg, checkpoint, stage)
[~, ~] = sixgr.phy.ra.runFourStepRA(cfg, 'Continuation', checkpoint, 'StopAfterStage', stage);
end

function localReject(action, identifier)
try
    action();
catch ME
    assert(string(ME.identifier) == identifier, 'Unexpected continuation failure: %s', ME.message);
    return;
end
error('testRAStageContinuation:MissingError', 'Expected continuation rejection %s.', identifier);
end
