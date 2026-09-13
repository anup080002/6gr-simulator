function selection=selectConfiguredTDRARow(cfg,direction,partition,slotOffset)
% Choose only a row already authored in the active YAML TDRA catalog.
% YAML row order breaks ties; this is scheduler policy, not a 3GPP constant.
% No symbol clipping, flexible-symbol reassignment or timing-offset rewrite.
direction=upper(string(direction));
assert(isscalar(direction) && any(direction==["DL","UL"]), ...
    'sixgr:truth:InvalidTDRADirection','TDRA selection requires DL or UL.');
validateattributes(partition,{'numeric'},{'real','vector','numel',2,'integer','nonnegative','finite'});
validateattributes(slotOffset,{'numeric'},{'real','scalar','integer','nonnegative','finite'});
family="pdsch"; if direction=="UL", family="pusch"; end
rows=sixgr.util.structGet(cfg,"phy."+family+".timeDomainAllocations",[]);
alias=sixgr.util.structGet(cfg,"phy."+family+".TimeDomainAllocations",[]);
if isempty(rows), rows=alias;
elseif ~isempty(alias) && ~isequal(rows,alias)
    error('sixgr:truth:ConflictingTDRACatalog','Canonical and legacy TDRA catalogs differ.');
end
selection=[];
if isempty(rows), return; end
assert(isnumeric(rows) && isreal(rows) && ismatrix(rows) && size(rows,2)==4 && ...
    all(isfinite(rows(:))) && all(rows(:)==fix(rows(:))) && all(rows(:)>=0) && ...
    all(rows(:,3)>0) && numel(unique(rows(:,1)))==size(rows,1), ...
    'sixgr:truth:InvalidTDRACatalog','TDRA requires unique integer [index,start,length,K] rows.');
eligible=rows(:,2)>=partition(1) & rows(:,2)+rows(:,3)<=sum(partition) & rows(:,4)==slotOffset;
hit=find(eligible,1,'first');
if isempty(hit), return; end
selection=struct('Index',double(rows(hit,1)), ...
    'SymbolAllocation',double(rows(hit,2:3)),'SlotOffset',double(rows(hit,4)), ...
    'Source',"yaml."+family+".time_domain_allocations_first_legal_row");
end
