function matched=matchesScheduledGrant(scheduled,ctx)
%MATCHESSCHEDULEDGRANT Preserve the full issued allocation and control state.
% SystemTransportBlockState binds the runtime payload ID AFTER scheduling.
% It is not a change to the issued PHYGrant. Permit only that checked added
% field; an existing scheduled payload ID must still match exactly.
actual=ctx.Grant;
if isfield(actual,'TransportBlockIdentity') && ~isfield(scheduled,'TransportBlockIdentity')
    if ~isfield(ctx,'TransportBlockIdentity') || ...
            ~isequal(actual.TransportBlockIdentity,ctx.TransportBlockIdentity) || ...
            ~isscalar(string(ctx.TransportBlockIdentity)) || strlength(string(ctx.TransportBlockIdentity))==0
        matched=false; return;
    end
    actual=rmfield(actual,'TransportBlockIdentity');
end
matched=isequaln(scheduled,actual);
end
