function ok=testPortableReceivedCSIRSCompletion()
% Actual bounded shared TX/channel/RF/RX -> original CSI completion and export.
% Uses the four-port authored physical fixture and explicit n40 CQI policy.
% This does not qualify R2024a execution, CSI reliability or a full n40 run.
ok=testSharedIndependentCSIRSCompletion(0,0,false,true);
end
