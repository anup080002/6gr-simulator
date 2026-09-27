function tf = isNormalizedFixedSNRPowerReference(cfg)
%ISNORMALIZEDFIXEDSNRPOWERREFERENCE Unit-Es samples, not absolute power.
tf = sixgr.rf.isFixedSNRLinkAuthority(cfg) && ...
    sixgr.rf.fixedSNRPowerReferenceMode(cfg) == "normalized_unit_es";
tf = logical(tf);
end
