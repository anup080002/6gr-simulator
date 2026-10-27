function admitReceivedNewDRBComplete(capsule,actor,srb,delivery,currentSample)
% gNB authority depends on actual received Complete and issued config only.
message=sixgr.rrc.validateDRBOriginalSRBTransport(actor,srb,delivery,capsule.Connection,"complete");
assert(message.Semantic.transaction_id==capsule.OriginalMessage.Semantic.transaction_id, ...
    'sixgr:rrc:DRBOriginalAdmission','Actual Complete belongs to a different issued transaction.');
receipts=sixgr.rrc.projectDRBAdmissionPair(capsule,delivery,"complete");
capsule.admitComplete(receipts,currentSample);
end
