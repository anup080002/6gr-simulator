function ok=testTRSResourceMappingVectorization()
% Exact table/reference equivalence; not receiver or statistical evidence.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
strict=sixgr.phy.trs.buildTRSConfigFromScenario(cfg);
initial=rng;
for withIDs=[false true]
    if withIDs
        strict.NZPCSIRSResourceIDs=0:(numel(strict.SlotNumbers)*numel(strict.ToolboxResources)-1);
    else
        strict.NZPCSIRSResourceIDs=[];
    end
    actual=sixgr.phy.trs.generateTRSSymbolsAndIndices(strict);
    reference=actual.ResourceMappingTable([],:);
    for j=1:numel(actual.SlotResources)
        resource=actual.SlotResources(j);
        cursor=0;
        for r=1:numel(actual.ResourceSet.Resources)
            ind=nrCSIRSIndices(resource.Carrier,actual.ResourceSet.Resources{r});
            symbols=nrCSIRS(resource.Carrier,actual.ResourceSet.Resources{r});
            assert(isequal(resource.Indices(cursor+(1:numel(ind))),ind(:)) && ...
                isequal(resource.Symbols(cursor+(1:numel(ind))),symbols(:)));
            for k=1:numel(ind)
                [sc,sy,port]=ind2sub([resource.K resource.L resource.Ports],double(ind(k)));
                id=NaN;
                if withIDs
                    id=strict.NZPCSIRSResourceIDs((j-1)*numel(actual.ResourceSet.Resources)+r);
                end
                reference(end+1,:)={string(strict.RunId),string(strict.ConfigHash), ...
                    double(resource.Slot),double(cursor+k),double(r-1),double(id), ...
                    double(ind(k)),double(sc-1),double(sy-1),double(port-1), ...
                    "TRS_NZP_CSI_RS",double(actual.ResourceSet.CSIRS.RowNumber), ...
                    double(actual.ResourceSet.CSIRS.NumCSIRSPorts), ...
                    string(actual.ResourceSet.CSIRS.CDMType), ...
                    string(actual.ResourceSet.CSIRS.Density),"real_lls_evidence"}; %#ok<AGROW>
            end
            cursor=cursor+numel(ind);
        end
    end
    assert(isequaln(actual.ResourceMappingTable,reference), ...
        'test:TRSMappingChanged','Vectorization must preserve every mapping column and row.');
end
assert(isequaln(initial,rng),'test:TRSMappingRNGChanged');
ok=true;
end
