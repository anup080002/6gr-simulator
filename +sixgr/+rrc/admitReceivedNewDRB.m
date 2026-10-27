function runtimes=admitReceivedNewDRB(capsule,actor,srb,delivery,currentSample)
% Return aliases to the SAME original issued owners, never reconstruct COUNT.
message=sixgr.rrc.validateDRBOriginalSRBTransport(actor,srb,delivery,capsule.Connection,"received");
assert(isequal(message.Bytes,capsule.OriginalMessage.Bytes)&& ...
    string(message.SHA256)==string(capsule.OriginalMessage.SHA256), ...
    'sixgr:rrc:DRBOriginalAdmission','Received configuration differs from original issued bytes.');
receipts=sixgr.rrc.projectDRBAdmissionPair(capsule,delivery,"received");
capsule.admitReceived(receipts,currentSample);
runtimes={capsule.directionalRuntime("DL"),capsule.directionalRuntime("UL")};
end
