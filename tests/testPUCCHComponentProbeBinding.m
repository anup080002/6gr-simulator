function ok = testPUCCHComponentProbeBinding()
% Isolated probes retain configured identity, TDD resource and coding budget.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator','configs', ...
    'scenarios','lls_100mhz_tdlc_bidirectional_truth.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,fullfile(tempdir,'sixgr_pucch_component_binding'));
before=rng;
[probe,carrier,evidence]=sixgr.link.preparePUCCHComponentProbe(cfg,1);
assert(isequal(before,rng),'Probe payload generation must not reseed the global stream.');
assert(evidence.SlotOneBased==4 && carrier.NSlot==3 && evidence.ExpectedBitCount==20);
assert(probe.Assignment.Data.RNTI==cfg.validation.pucch_resources.component_probe.rnti);
assert(probe.Assignment.Data.ComponentCarrier==cfg.phy.frame.DefaultIdentity.ScheduledCCID && ...
    probe.Assignment.Data.ActiveULBWP==cfg.phy.frame.DefaultIdentity.ULBWPID);
assert(~probe.Assignment.Data.ConnectedModeEvidenceEligible && ...
    probe.Assignment.Data.AssignmentSource=="calibration");
budget=probe.Assignment.Data.AllocationBudget;
assert(budget.InformationBits==20 && budget.TotalCRCBits==11 && ...
    budget.CapacityBits==96 && budget.SelectedNumPRBs==3 && budget.RateConstraintSatisfied);
[same,~,again]=sixgr.link.preparePUCCHComponentProbe(cfg,1);
assert(probe.Report.Digest==same.Report.Digest && isequal(evidence,again));
[next,~,later]=sixgr.link.preparePUCCHComponentProbe(cfg,2);
assert(later.SlotOneBased==9 && later.Seed==evidence.Seed+1 && ...
    next.Assignment.DueSlot==9);
poison=cfg; poison.phy.rnti=NaN;
[unchanged,~,~]=sixgr.link.preparePUCCHComponentProbe(poison,1);
assert(unchanged.Assignment.Digest==probe.Assignment.Digest, ...
    'An unused legacy identity field must not override explicit probe identity.');
wrong=cfg; wrong.validation.pucch_resources=rmfield(wrong.validation.pucch_resources,'component_probe');
localReject(@()sixgr.link.preparePUCCHComponentProbe(wrong,1),'sixgr:link:MissingPUCCHComponentProbe');
wrong=cfg; wrong.validation.pucch_resources.component_probe.enabled=false;
localReject(@()sixgr.link.preparePUCCHComponentProbe(wrong,1),'sixgr:link:DisabledPUCCHComponentProbe');
wrong=cfg; wrong.validation.pucch_resources.component_probe.rnti=NaN;
localReject(@()sixgr.link.preparePUCCHComponentProbe(wrong,1),'sixgr:link:InvalidPUCCHComponentProbe');
wrong=cfg; wrong.validation.pucch_resources.component_probe.first_slot_zero_based=0;
localReject(@()sixgr.link.preparePUCCHComponentProbe(wrong,1),'sixgr:phy:pucch:IllegalTDDResource');
wrong=cfg; wrong.validation.pucch_resources.format2=rmfield(wrong.validation.pucch_resources.format2,'max_code_rate');
localReject(@()sixgr.link.preparePUCCHComponentProbe(wrong,1),'sixgr:phy:pucch:MissingMaxCodeRate');
% Execute the exact configured fading branch. This proves execution and
% receiver evidence, not a statistical success rate at one operating point.
trial=sixgr.link.runPUCCHWaveformTrial(probe.RuntimeConfig,'Carrier',carrier, ...
    'Assignment',probe.Assignment,'Report',probe.Report,'ReceiverContext',probe.ReceiverContext, ...
    'SNR_dB',cfg.channel.snr_dB,'ChannelProfile',sixgr.channel.resolveConcreteProfile(cfg), ...
    'Seed',evidence.Seed);
assert(trial.PUCCHTransmissionPrepared && trial.DetectionAttempted && ...
    isfield(trial,'Receiver') && isfield(trial.Receiver,'DecodedSequence1'), ...
    'Configured PUCCH probe must reach the physical receiver: %s',trial.FailureReason);
assert(trial.ExpectedBitCount==20 && trial.UCICRCBitCount==11 && ...
    trial.ChannelEstimateAttempted && trial.ChannelEstimateAvailable);
assert(isnan(double(sixgr.util.structGet(trial,'ProcedureDelay_ms',NaN))), ...
    'An isolated waveform must not claim a measured control-procedure delay.');
% The actual receiver has no protocol delay; guard the production collector
% against turning this absent field into a fabricated zero during export.
source=fileread(which('sixgr.truth.runWaveformLinkBundle'));
collector=regexp(source, ...
    '(?s)function T = localCollectPUCCHTrials\(.*?(?=\r?\nfunction )', ...
    'match','once');
assert(~isempty(collector) && contains(collector, ...
    'r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", NaN));'), ...
    'The PUCCH collector must preserve an unavailable procedure delay.');
row=table("PASS",1,"isolated_component_waveform", ...
    'VariableNames',{'Status','CRCPass','SourceClassification'});
canonical=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable('PUCCH',row);
assert(canonical.SourceClassification=="isolated_component_waveform" && ...
    canonical.RuntimeConsumer=="none_isolated_component" && ...
    canonical.ValueRole=="isolated_control_reference_receiver_evidence" && ...
    ~contains(canonical.ValueDefinition,"active LLS coupled runtime"), ...
    'Canonical export must not promote a component into connected-runtime evidence.');
ok=true;
end

function localReject(action,identifier)
try
    action();
catch err
    assert(strcmp(err.identifier,identifier),'Expected %s, got %s: %s',identifier,err.identifier,err.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected %s.',identifier);
end
