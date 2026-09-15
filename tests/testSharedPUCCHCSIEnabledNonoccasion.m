function ok=testSharedPUCCHCSIEnabledNonoccasion()
% Actual shared SRS + absent-PUCCH reception, CSI enabled but not due here.
% This does not claim that combined CSI/HARQ occasions are qualified.
setup6GRSimToolkit('Verbose',false);
config='simulator/configs/scenarios/lls_pucch_csi_enabled_nonoccasion_fixture.yaml';
s=sixgr.lls6g.config.loadScenarioConfig(config);
logsRoot=fullfile(pwd,'logs');
if ~isfolder(logsRoot), mkdir(logsRoot); end
folder=tempname(logsRoot);
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.csi.reportCSI && cfg.phy.csi.reportPeriodicitySlots==5 && ...
    cfg.phy.csi.reportOffsetSlots==4);
[ok,state]=testSharedPUCCHReceiveOnlyClock(folder,config);
assert(ok && state.CfgMobility.phy.csi.reportCSI && ...
    height(state.SharedGNBUCIHARQTable)==2 && height(state.ControlTrials.PUCCH)==1);
assert(all(state.ControlTrials.PUCCH.ReceiverOnlyAssignment) && ...
    all(~state.ControlTrials.PUCCH.OraclePayloadBitsUsed));
fprintf('SHARED_CSI_ENABLED_NONOCCASION_PASS reporting_enabled=1 independent_receiver=1 combined_qualification=0 logs=%s\n',folder);
end
