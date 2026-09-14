function id=resolveConfiguredCSIResourceID(ids)
% The current installed CSI report/BWP binding is a single resource ID.
% TS 38.213 9.2.5.2: pucch-CSI-ResourceList, not a HARQ resource-set PRI.
% Multiple reports/resources need explicit report/BWP associations, not a
% first-entry, payload-size or RNTI-modulo choice from an unbound flat list.
assert(isnumeric(ids) && isreal(ids) && isscalar(ids) && isfinite(ids) && ...
    ids>=0 && ids==fix(ids) && ids<=flintmax, ...
    'sixgr:phy:pucch:UnresolvedCSIReportingResource', ...
    'CSI resource selection needs one installed report/BWP resource ID; resolve multiple report associations explicitly.');
id=double(ids);
end
