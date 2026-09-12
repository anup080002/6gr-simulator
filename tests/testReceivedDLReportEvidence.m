function ok=testReceivedDLReportEvidence()
% Reporting replays real saved captures, without a second decoder or TX plan.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
root=fullfile('docs','lls','evidence_20260913','received_dl_harq');
for k=[1 2 4]
    saved=load(fullfile(root,sprintf('attempt_%d.mat',k)));
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,saved.a.ControlAbsoluteSlot+1);
    [rx,decision]=saved.before.receive(cfg,saved.a,saved.delayed, ...
        'TimingSearchWindowSamples',[0 60]);
    assert(isequaln(decision,saved.decision));
    assert(rx.ReceivedAssignmentDigest==saved.a.AssignmentDigest && ...
        rx.AssignmentValidationDigest==rx.Assignment.validateForExecution());
    assert(rx.ExecutionProfile=="connected_strict" && rx.StrictSchedulingOwnership && ...
        string(rx.SchedulingOwnership)=="received_control_and_ue_owned_harq");
    assert(isequaln(rx.RecLLR,rx.Decode.RateRecoveredLLR) && ...
        isequaln(rx.RateRecoveredLLR,rx.Decode.RateRecoveredLLR) && ...
        isequaln(rx.HARQCombinedLLR,rx.Decode.HARQCombinedLLR));
    assert(rx.RateRecoveredLLRDomain=="current_attempt_mother_code_before_harq_combining" && ...
        rx.DecoderCRCInputDomain=="harq_combined_mother_code");
    assert(rx.CurrentAttemptStandaloneCRCMeasured==~rx.Decode.HARQCombineInfo.Applied);
    if k==2
        assert(~isequaln(rx.RateRecoveredLLR,rx.HARQCombinedLLR), ...
            'The retained RV0 and received RV2 soft evidence must remain distinct.');
    end
    assert(rx.NoiseVar==rx.NoiseVarianceUsedForLLR && ...
        rx.PreEqualizationNoiseVariance==rx.EstimatedNoiseVariance);
    assert(rx.PreEqualizationNoiseVarTransformSource== ...
        "received_assignment_native_ofdm_noise_transform");
    assert(isequaln(rx.Metrics,saved.rx.Metrics) && ...
        isequaln(rx.LayerEqualizedSymbolsForEvidence,saved.rx.LayerSymbols), ...
        'Report construction must not change the canonical measurement.');
    assert(isequal(fieldnames(rx.Decode),fieldnames(saved.rx.Decode)));
    for field=string(fieldnames(rx.Decode)).'
        if any(field==["DecodeLatency_s","DecodeLatencyPerCodeword_s"])
            % toc measures this execution's wall time, not a replayable PHY
            % quantity. Keep checking the actual measured value and source.
            assert(all(isfinite(rx.Decode.(field))) && all(rx.Decode.(field)>0));
        else
            assert(isequaln(rx.Decode.(field),saved.rx.Decode.(field)), ...
                'Canonical decoder field %s changed.',field);
        end
    end
    assert(rx.DecodeLatency_s==rx.Decode.DecodeLatency_s && ...
        rx.DecodeLatencySource=="receiver_instrumented_ldpc_decode");
    assert(rx.PrecodeInfo.ReceiverOnly && ~rx.PrecodeInfo.AppliedPrecoderAvailable && ...
        isempty(rx.PrecodeInfo.MatrixPorts) && isempty(rx.PrecodeInfo.MatrixLogicalPorts));
    assert(isfield(rx,'ReceiverUsable') && isstruct(rx.CodingLayout));
    [occasion,~]=sixgr.phy.refsig.csirsOccasion(cfg,saved.a.DataAbsoluteSlot);
    assert(rx.CSIRSObservation.Scheduled==occasion);
    if ~occasion
        assert(isempty(rx.CSIRSIndices) && ~rx.CSIRSObservation.Observed && ...
            rx.CSIRSObservation.UpdateOutcome=="not_scheduled");
    end
    args={'ExecutionProfile','connected_strict','Assignment',rx.Assignment, ...
        'ResourcePlan',rx.ResourcePlan,'Carrier',rx.Carrier, ...
        'ReferenceSignalConfig',rx.ReferenceConfig,'ReceiverConfig',rx.ReceiverConfig, ...
        'CodingPlan',rx.CodingPlans,'ReceiverHARQState',saved.before, ...
        'ReceivedAssignment',saved.a,'TimingSearchWindowSamples',[0 60]};
    badArgs=args; bad=rx.ReceiverConfig; bad.NoiseVariance=123;
    badArgs{12}=bad;
    localReject(@()sixgr.phy.dl.PDSCH_Rx(saved.delayed,cfg,badArgs{:}), ...
        'sixgr:pdsch:ReceivedReportIdentityMismatch');
    noTimingArgs=args(1:end-2);
    localReject(@()sixgr.phy.dl.PDSCH_Rx(saved.delayed,cfg,noTimingArgs{:}), ...
        'sixgr:pdsch:ReceivedReportTimingRequired');
    fprintf('RECEIVED_DL_REPORT_EVIDENCE_PASS sequence=%d combined=%d csi_occasion=%d\n', ...
        k,rx.HARQSoftCombiningApplied,occasion);
end
assert(testReceivedDLDisabledCSI);
% Periodic resource eligibility follows the absolute data-slot calendar,
% including frame boundaries. It does not depend on a TX scheduled flag.
cfg.phy.csirs.enable=true; cfg.phy.csirs.period_slots=7; cfg.phy.csirs.offset_slots=3;
for slot=0:41
    [actual,periodicity]=sixgr.phy.refsig.csirsOccasion(cfg,slot);
    assert(actual==ismember(slot,[3 10 17 24 31 38]) && periodicity=="7:3");
end
cfg.phy.csirs.offset_slots=7;
localReject(@()sixgr.phy.refsig.csirsOccasion(cfg,10), ...
    'sixgr:pdsch:InvalidCSIRSOccasionConfig');
cfg.phy.csirs.enable=false;
assert(~sixgr.phy.refsig.csirsOccasion(cfg,10));
fprintf('RECEIVED_DL_REPORT_CALENDAR_PASS slots=42 guards=8\n');
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
