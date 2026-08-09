function ok = testIntegrationAuxiliarySignalAuthority()
%TESTINTEGRATIONAUXILIARYSIGNALAUTHORITY Cross-mode reduction disables CSI-RS.

result = sixgr.integration.CommonAirInterfacePipeline.executeReduction( ...
    "DL", "AWGN", 0, 11, sixgr.integration.RunMode.FixedSNRSweep);
assert(result.ProductionBackend == "production_dl_sch_nr_waveform_chain");
assert(result.ApproximationMode == "none");
assert(~logical(sixgr.util.structGet(result.Receiver, ...
    "CSIRSRuntimeEvent.Scheduled", false)), ...
    "The signal-neutral cross-mode reduction unexpectedly scheduled CSI-RS.");
assert(isfinite(result.PostEqualizationSINR_dB), ...
    "The production receiver did not emit a finite post-equalization SINR.");

ok = true;
end
