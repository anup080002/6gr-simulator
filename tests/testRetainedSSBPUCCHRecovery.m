function ok=testRetainedSSBPUCCHRecovery(which)
% Shared physical SSB/SIB1 -> retained measured power -> combined UCI.
% RA/TAG is declared; no full access, n40 or statistical qualification.
% Each arm has a separate retained output/terminal receipt. The withheld
% arm uses actual receiver-only reception, never a test-authored DTX result.
if nargin<1, which="positive"; end
which=string(which);
assert(isscalar(which) && any(which==["both","positive","withheld"]));
root=fileparts(fileparts(mfilename('fullpath')));
parent=fullfile(root,'results','validation','retained_ssb_pucch');
if ~isfolder(parent), mkdir(parent); end
ok=true;
if any(which==["both","positive"])
fixture=fullfile(root,'simulator','configs','validation','lls_retained_ssb_pucch_recovery.yaml');
output=tempname(parent);
[passed,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
    output,fixture,false,true,false,false,true);
assert(passed);
life=state.SSBPowerReferenceLifecycleByUE{1};
assert(~life.AgeExpiryApplied && life.ReferencePower_dBm== ...
    state.UECommonCellConfigurationByUE{1}.SSPBCHBlockPower_dBm);
assert(state.TestActualSIB1DeliveredSlot==6);
decision=state.TestActualPUCCHPowerDecision;
assert(decision.MeasuredPowerReferenceRequired && decision.PreparationAdmitted && ...
    decision.PowerReferenceProducerSlot==1 && decision.PowerReferenceAvailableSlot==6 && ...
    strlength(decision.PowerReferenceMeasurementID)>0 && ...
    isinf(decision.MaximumPowerReferenceAgeSlots));
T=state.ControlTrials.PUCCH;
trial=T(T.Slot==10,:);
assert(height(trial)==1 && trial.PUCCHDecodeOk && trial.SignalPresent==1);
fprintf('RETAINED_SSB_PUCCH_RECOVERY_PASS actual_SIB1=1 actual_combined_UCI=1 full_access=0 root=%s\n',output);
end
if any(which==["both","withheld"])
fixture=fullfile(root,'simulator','configs','validation','lls_missing_selected_ssb_pucch_recovery.yaml');
output=tempname(parent);
[passed,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
    output,fixture,false,true,false,false,true,2,false,false,false,false,false,false,true);
assert(passed && state.TestActualSIB1DeliveredSlot==6 && state.TestWithheldPUCCH.ReceiverCompleted && ...
    state.TestWithheldRecoveryTerminal.RecoveredSlot==15 && ...
    ~state.TestWithheldRecoveryTerminal.OldObligationReplayed && ...
    ~state.TestWithheldRecoveryTerminal.NewCSIObservationClaimed);
fprintf('RETAINED_SSB_PUCCH_WITHHELD_RECOVERY_PASS actual_missing_selected_reference=1 actual_receive_only=1 actual_fresh_SSB=1 actual_recovered_UCI=1 full_access=0 root=%s\n',output);
end
end
