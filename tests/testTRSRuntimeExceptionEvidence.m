function ok = testTRSRuntimeExceptionEvidence()
% Runtime faults must not be published as measured tracking failures.
setup6GRSimToolkit("Verbose", false);
s = sixgr.lls6g.config.loadScenarioConfig(fullfile("simulator", ...
    "configs", "scenarios", "lls_causal_access_to_data_wiring_tdd.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(s, tempname);
% Exercise the production channel-state validator, not a mocked receiver.
invalidState = struct("Initialized", false);
out = sixgr.link.runTRSTracking(cfg, "SNR_dB", 12, ...
    "ChannelState", invalidState);
assert(~out.Ok && ~out.Skipped && out.Crash);
assert(out.FailureIdentifier == "sixgr:link:InvalidInitialRuntimeChannelState", ...
    "Unexpected failure: %s", out.FailureReason);
assert(contains(out.FailureReason, out.FailureIdentifier));
assert(isnan(out.TrackingFailure) && isnan(out.RuntimeStageCount));
assert(~out.DetectionAttempted && ~out.TRSRuntimeEvidenceUsable && ...
    ~out.RuntimeChannelStateUsed);
fprintf('TRS_RUNTIME_EXCEPTION_EVIDENCE_PASS\n');
ok = true;
end
