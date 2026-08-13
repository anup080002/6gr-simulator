function ok=testRAN1AI10522Controlled()
%TESTRAN1AI10522CONTROLLED One actual canonical +20 dB waveform gate.
setup6GRSimToolkit("Verbose",false);
[cfg,~,scfg]=sixgr.studies.ran1ai10522.loadStudyConfig( ...
    "simulator/configs/scenarios/lls_ran1_10522_td_dmrs_single_slot.yaml");
cfg.study.execution.snr_points_db=20;
root=fullfile(tempdir,"sixgr_ran1_10522_controlled_test");
out=sixgr.studies.ran1ai10522.ControlledSuite.run(cfg,scfg,root);
assert(height(out.Trials)==1 && out.Trials.CRCPass && out.Trials.BitErrors==0);
assert(out.Trials.StrictReceiverEvidenceOk && out.Trials.PostEqSINRAvailable);
assert(string(out.Trials.ApproximationMode)=="none" && ~out.Trials.FallbackFlag);
assert(string(out.Trials.ChannelModel)=="TDL-C");
assert(out.Points.BLER==0 && out.Points.BER==0);
assert(out.Points.BLER_CI_Low<=out.Points.BLER && ...
    out.Points.BLER<=out.Points.BLER_CI_High);
assert(~out.Points.TDocReady && out.Points.ConvergenceStatus=="INCOMPLETE");
fprintf("RAN1 10.5.2.2 controlled: 1/1 canonical TDL-C PDSCH TB passes at +20 dB.\n");
ok=true;
end
