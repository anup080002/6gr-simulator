function result=applyReceivedSecurityCommand(dlRuntime,ulRuntime,observation,dlContext,ulContext,expected,transport)
% Root paired API preflights both endpoints before any COUNT/security change.
result=sixgr.rrc.validateReceivedRRCSecurity('security_mode_command', ...
    observation,dlContext,expected,transport);
tx=result.Receipt;tx.ContextID=ulContext.ContextID;tx.Direction=ulContext.Direction;tx.Endpoint="TX";
result.Completions=dlRuntime.commitReceivedSecurityCommand( ...
    result.OriginalRuntimeToken,result.Receipt,ulRuntime,ulContext.ContextID,tx);
result.PeerTransmitReceipt=tx;
result.SecurityActivated=true;
end
