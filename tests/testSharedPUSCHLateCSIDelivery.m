function ok=testSharedPUSCHLateCSIDelivery()
% Actual CSI-RS measurement, configured periodic CSI/HARQ-coded PUSCH,
% and later receiver/scheduler delivery. Not generic source+AMC-delay wiring.
% Actual shared SIB1 precedes measurement installation; initial TAG/RA
% remains a declared component boundary, not a full access qualification.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
% The component's declared connected boundary must not leak into the actual
% n40 cold-access scenario. Inspect resolved YAML without executing it.
production=sixgr.lls6g.config.loadScenarioConfig(fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml'));
assert(production.get('control_gating.prach_required') && ...
    production.get('control_gating.pbch_required'), ...
    'test:N40ColdAccessRequired','The production n40 scenario must still require received initial access.');
logsRoot=fullfile(root,'logs','tdd_shared_pusch_late_csi');
if ~isfolder(logsRoot), mkdir(logsRoot); end
outputRoot=tempname(logsRoot);
[ok,state]=testSharedPUSCHChannelArtifacts('TDD',true,true,true,false,false,false,outputRoot);
csi=state.TestCSISource.CSIRSTrialTable;
installed=state.TestActualSIB1Installation;
assert(state.DecodedSIB1RecoveryByUE{1}.StrictOk && ~installed.DecodedDedicatedRRC && ...
    state.TestActualSIB1DeliveredSlot<=csi.Slot && ...
    all(csi.DLMeasurementAuthorityEligible) && ...
    all(csi.DLMeasurementInstallationSHA256==installed.SHA256) && ...
    all(csi.ObservationStartSample>=installed.EffectiveSample));
end
