function ok=testPreparedCSIReacquisitionCompletion()
% Actual SSB/SI/CSI/DL/UL/UCI execution around an injected UE-private loss.
% No second acquisition or full n40 statistical qualification is claimed.
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_pusch_independent_harq_csi_fixture.yaml');
parent=fullfile(root,'logs','prepared_csi_reacquisition');
if ~isfolder(parent), mkdir(parent); end
output=tempname(parent);
[ok,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
    output,fixture,false,true,false,false,false,2,false,false,false,false,false,true);
proof=state.TestPreparedCSITransition;
% TestPUSCHRows belongs to separate-PUCCH / retransmission variants. This
% independent shared completion writes the original receiver row instead.
trials=sixgr.util.csvReadTable(fullfile(output,'received_pusch.csv'),'TextType','string');
assert(state.CellAcquisitionState(1)=="searching" && state.TestPUSCHReceived && ...
    height(trials)==1 && trials.CRCPass==1 && ...
    string(trials.ChannelObservationID)==state.TestPUSCHObservationID);
reports=state.SharedGNBCSIReportTable;
assert(height(reports)==1 && reports.CSIUCIDecodeOk && state.LatestDLFeedback(1).Valid);
allPending=state.PendingCSITable;
sixgr.util.csvWriteTable(fullfile(output,'completion_pending_reports.csv'),allPending, ...
    'PreserveSchema',true,'RoundTripNumericText',true);
% Actual UL completion also enqueues gNB-local UL quality. Select the
% original DL report by identity; do not demand a single row globally.
pending=allPending(string(allPending.ReportIdentity)==proof.ReportIdentity,:);
assert(height(pending)==1 && string(pending.ReportIdentity)==proof.ReportIdentity && ...
    pending.Processed && ~pending.UECSIPayloadRetired && ...
    proof.DeclaredPriorPowerDeferralSchema && pending.UEProducerDisposition=="");
assert(~ismember('UEProducerDisposition',reports.Properties.VariableNames), ...
    'Private UE disposition must not become independently received CSI authority.');
original=jsondecode(reports.UEReferenceRecordJSON);
assert(string(pending.Direction)=="DL" && ...
    string(pending.UECSIMeasurementInstallationSHA256)==string(original.UECSIMeasurementInstallationSHA256) && ...
    string(pending.UECSIMeasurementConfigurationSHA256)==string(original.UECSIMeasurementConfigurationSHA256) && ...
    pending.CSIUCIDecodeOk && string(pending.ObservationID)==string(reports.ObservationID));
ulQuality=allPending(string(allPending.Direction)=="UL",:);
assert(height(ulQuality)==1 && ulQuality.SourceSlot==trials.Slot && ...
    string(ulQuality.ReportIdentity)~=proof.ReportIdentity);
proof.ActualPUSCHCRC=logical(trials.CRCPass);
proof.ActualPUSCHObservationID=string(trials.ChannelObservationID);
proof.ActualCSIReceptionSucceeded=logical(reports.CSIUCIDecodeOk);
proof.OriginalPayloadRetired=logical(pending.UECSIPayloadRetired);
sixgr.util.jsonWrite(fullfile(output,'prepared_csi_transition_receipt.json'),proof);
fprintf('PREPARED_CSI_REACQUISITION_COMPLETION_PASS folder=%s\n',output);
end
