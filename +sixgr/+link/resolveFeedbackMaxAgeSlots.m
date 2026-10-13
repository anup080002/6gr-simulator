function maxAgeSlots = resolveFeedbackMaxAgeSlots(cfg, direction)
% One configured freshness policy for AMC and runtime feedback selection.
if upper(string(direction)) == "UL"
    paths=["phy.linkAdaptation.ulMaxCSIAgeSlots", ...
        "phy.linkAdaptation.maxCSIAgeSlots","run.controlGating.srsMaxAgeSlots"];
else
    paths=["phy.linkAdaptation.dlMaxCSIAgeSlots", ...
        "phy.linkAdaptation.maxCSIAgeSlots","run.controlGating.csirsMaxAgeSlots"];
end
maxAgeSlots=inf;
for path=paths
    value=sixgr.util.structGet(cfg,path,[]);
    if isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value)
        if value>=0, maxAgeSlots=double(value); end
        return;
    end
end
end
