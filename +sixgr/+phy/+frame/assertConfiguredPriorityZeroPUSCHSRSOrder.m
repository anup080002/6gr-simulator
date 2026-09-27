function evidence=assertConfiguredPriorityZeroPUSCHSRSOrder(cfg)
%ASSERTCONFIGUREDPRIORITYZEROPUSCHSRSORDER Validate every installed UL TDRA.
priority=double(sixgr.util.structGet(cfg,'phy.pusch.priorityIndex',NaN));
source=string(sixgr.util.structGet(cfg,'phy.pusch.priorityIndexSource',""));
assert(isscalar(priority) && isfinite(priority) && any(priority==[0 1]) && ...
    isscalar(source) && strlength(source)>0, ...
    'sixgr:phy:frame:MissingPUSCHPriorityAuthority', ...
    'SRS/PUSCH coexistence requires an explicit installed PUSCH priority index.');
evidence=struct('Applicable',false,'PriorityIndex',priority, ...
    'PriorityIndexSource',source,'ConfiguredRowsChecked',0, ...
    'Authority',"TS38.214_6.2.1");
if priority~=0 || ~logical(sixgr.util.structGet(cfg,'phy.srs.enable',false)) || ...
        ~logical(sixgr.util.structGet(cfg,'phy.pusch.enable',true))
    return;
end
carrier=sixgr.phy.grid.makeCarrier(cfg);
strictSRS=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
srs=strictSRS.ToolboxSRS;
srsSymbols=double(srs.SymbolStart)+(0:double(srs.NumSRSSymbols)-1);
rows=double(sixgr.util.structGet(cfg,'phy.pusch.timeDomainAllocations',[]));
if isempty(rows)
    allocation=double(sixgr.util.structGet(cfg,'phy.pusch.SymbolAllocation',[]));
    assert(numel(allocation)==2, ...
        'sixgr:phy:frame:MissingPUSCHTDRAAuthority', ...
        'Priority-0 PUSCH/SRS validation requires an installed symbol allocation.');
    rows=[0 reshape(allocation,1,[]) 0];
end
assert(ismatrix(rows) && size(rows,2)==4 && ~isempty(rows), ...
    'sixgr:phy:frame:MissingPUSCHTDRAAuthority', ...
    'Priority-0 validation requires installed [index,start,length,K2] rows.');
for rowIndex=1:size(rows,1)
    puschSymbols=rows(rowIndex,2)+(0:rows(rowIndex,3)-1);
    sixgr.phy.frame.assertPriorityZeroPUSCHBeforeSRS( ...
        puschSymbols,srsSymbols,carrier.SymbolsPerSlot);
end
evidence.Applicable=true;
evidence.ConfiguredRowsChecked=size(rows,1);
evidence.PUSCHTDRARows=rows;
evidence.SRSSymbols0Based=srsSymbols;
end
