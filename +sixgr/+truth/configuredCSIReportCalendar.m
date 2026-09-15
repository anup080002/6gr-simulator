function calendar=configuredCSIReportCalendar(cfg,ue,targetSlot)
% Payload-free nominal CSI obligations for one installed receiver occasion.
% Reporting enablement alone does not imply a report in every slot.
validateattributes(targetSlot,{'numeric'},{'scalar','real','finite','integer','positive'});
enabled=sixgr.util.structGet(cfg,'phy.csi.reportCSI',[]);
assert((islogical(enabled)||isnumeric(enabled)) && isscalar(enabled) && ...
    isreal(enabled) && isfinite(enabled) && any(enabled==[0 1]), ...
    'sixgr:truth:InvalidCSIReceiveEnablement','phy.csi.reportCSI must be explicitly binary.');
calendar=table();
if ~enabled, return; end
assert(isequal(string(sixgr.util.structGet(cfg,'phy.csi.reportTrigger',"")),"periodic"), ...
    'sixgr:truth:UnresolvedCSIReceiveActivation', ...
    'Nonperiodic CSI reception needs independent request/activation authority; do not infer it from UE reports.');
calendar=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,double(targetSlot),double(targetSlot));
end
