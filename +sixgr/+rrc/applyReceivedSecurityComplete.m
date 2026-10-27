function result=applyReceivedSecurityComplete(ulRuntime,dlRuntime,observation,ulContext,dlContext,expected,transport)
result=sixgr.rrc.validateReceivedRRCSecurity('security_mode_complete', ...
    observation,ulContext,expected,transport);
tx=result.Receipt;tx.ContextID=dlContext.ContextID;tx.Direction=dlContext.Direction;tx.Endpoint="TX";
result.Completions=ulRuntime.commitReceivedSecurityComplete( ...
    result.OriginalRuntimeToken,result.Receipt,dlRuntime,dlContext.ContextID,tx);
result.PeerTransmitReceipt=tx;
result.SecurityActivated=true;
end
