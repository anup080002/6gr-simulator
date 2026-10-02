function counts=startingPopulations(p,cases)
% Fixed per-case/per-role/per-history quotas, frozen before any CRC is seen.
roles=["reference","reference_validation","fit","validation"]; counts=cell(numel(cases),4);
for c=1:numel(cases), for r=1:4
    h=sixgr.calibration.historyGrid(p,roles(r));
    counts{c,r}=repmat(double(p.populations.(roles(r))),size(h,1),1);
end, end
if ~isfield(p,'starting_population_overrides'), return; end
entries=p.starting_population_overrides;
if iscell(entries), entries=vertcat(entries{:}); end
seen=strings(0,1);
for k=1:numel(entries)
    e=entries(k); c=find(string({cases.ID})==string(e.case_id)); r=find(roles==string(e.role));
    assert(isscalar(c) && isscalar(r),'sixgr:calibration:PopulationPlan','Unknown case_id or role in starting_population_overrides.');
    validateattributes(e.history_index,{'numeric'},{'scalar','integer','>=',1,'<=',numel(counts{c,r})});
    validateattributes(e.starting_tbs,{'numeric'},{'scalar','integer','positive','finite'});
    key=string(c)+"|"+r+"|"+e.history_index;
    assert(~any(seen==key),'sixgr:calibration:PopulationPlan','Duplicate fixed history quota.');
    seen(end+1)=key; counts{c,r}(e.history_index)=double(e.starting_tbs); %#ok<AGROW>
end
end
