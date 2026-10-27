function result=applySubmittedSecurityComplete(ulRuntime,dlRuntime,submission,ulContext,dlContext,expected)
ulRuntime.validateOriginalLowerLayerSubmission(submission);
result=sixgr.rrc.validateSubmittedSecurityComplete(submission,ulContext,dlContext,expected);
% Submission came from the private original PDCP-to-RLC owner, not a PHY
% completion, prepared waveform or local RRC response intention.
ulRuntime.activateSubmittedSecurityComplete(ulContext.ContextID,result.TXReceipt, ...
    dlRuntime,dlContext.ContextID,result.RXReceipt);
result.SecurityActivated=true;
end
