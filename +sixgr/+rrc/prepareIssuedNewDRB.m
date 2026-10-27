function [capsule,record]=prepareIssuedNewDRB(installed,actor,srb,transmission,connection,coreContext,currentSample)
% Build once from original gNB-issued UPER, before any UE receive admission.
message=sixgr.rrc.validateDRBOriginalSRBTransport(actor,srb,transmission,connection,"issued");
capsule=sixgr.rrc.PendingDRBEndpoints(message,connection,coreContext,installed);
receipts=sixgr.rrc.projectDRBAdmissionPair(capsule,transmission,"issued");
capsule.admitIssued(receipts,currentSample);
s=message.Semantic;
record=connection;record.DRBID=s.drb_id;record.LCID=s.lcid;record.PduSessionID=s.sdap.pdu_session;
record.QFI=s.sdap.qfi;record.DefaultDRB=s.sdap.default_drb;record.LogicalChannel=s.logical_channel;
record.OriginalMessage=message;record.PreparedEndpoints=capsule;
record.EndpointBindingStatus="original_issued_gNB_UL_RX_only";
end
