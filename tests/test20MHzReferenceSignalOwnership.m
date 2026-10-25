function ok=test20MHzReferenceSignalOwnership(configPath)
% Actual NR index generation over the selected run's whole resource calendar.
% Allocation verification only: not received performance or full-run acceptance.
setup6GRSimToolkit('Verbose',false);
if nargin==0
    configPath='simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml';
end
s=sixgr.lls6g.config.loadScenarioConfig(configPath);
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
totalSlots=double(cfg.run.totalSlots);
validateattributes(totalSlots,{'numeric'},{'scalar','integer','positive','finite'});
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
trs=sixgr.phy.trs.buildTRSConfigFromScenario(cfg);
srs=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
totals=zeros(1,5); dlChecks=0; ulChecks=0;
for slot0=0:totalSlots-1
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    carrier=sixgr.phy.grid.makeCarrier(current);
    K=12*double(carrier.NSizeGrid); plane=K*double(carrier.SymbolsPerSlot);
    partition=frame.SlotPartition(slot0);
    ssb=sixgr.phy.frame.ssbPRBSymbolReservation(current,carrier,slot0);
    csi=sixgr.phy.refsig.csirs(carrier,current,'CollectResourceEvidence',false);
    csi=base(csi,plane);
    tracking=[];
    if sixgr.truth.isActiveTRSOccasion(current,slot0+1)
        for r=1:numel(trs.ToolboxResources)
            tracking=union(tracking,base(nrCSIRSIndices(carrier,trs.ToolboxResources{r}),plane));
        end
    end
    im=sixgr.phy.refsig.csiIMResource(carrier,current);
    muted=base(im.PhysicalIndices1Based,plane);
    owners={ssb.ReservedCarrierRE0,csi,tracking,muted};
    for a=1:numel(owners)
        indices=owners{a};
        assert(all(indices>=0 & indices<plane),'Reference is outside the carrier.');
        if ~isempty(indices)
            assert(partition.AllowDL,'DL reference occupies an UL-only slot.');
            dlSymbols=partition.DLSymbolAllocation(1)+(0:partition.DLSymbolAllocation(2)-1);
            assert(all(ismember(floor(indices/K),dlSymbols)), ...
                'DL reference occupies UL or guard symbols.');
        end
        for b=1:a-1
            assert(isempty(intersect(indices,owners{b})), ...
                'Configured reference owners %d/%d collide at slot0=%d.',a,b,slot0);
        end
    end
    sounding=base(nrSRSIndices(carrier,srs.ToolboxSRS),plane);
    totals=totals+[~isempty(owners{1}),~isempty(csi),~isempty(tracking), ...
        ~isempty(muted),~isempty(sounding)];
    if ~isempty(sounding)
        assert(partition.AllowUL,'SRS occupies a DL-only slot.');
        ulSymbols=partition.ULSymbolAllocation(1)+(0:partition.ULSymbolAllocation(2)-1);
        assert(all(ismember(floor(sounding/K),ulSymbols)));
    end
    % SSB/common-SI exclusions are checked separately; do not demand a
    % full-band PDSCH through these configured common-signal resources.
    if partition.AllowDL && isempty(ssb.ReservedCarrierRE0) && ...
            ~ismember(mod(slot0,40),10:13)
        [data,info,p]=sixgr.phy.grid.allocREsPDSCH(carrier,current, ...
            'PRBSet',0:carrier.NSizeGrid-1, ...
            'SymbolAllocation',partition.DLSymbolAllocation,'NumLayers',1);
        pilots=[reshape(nrPDSCHDMRSIndices(carrier,p),[],1); ...
            reshape(nrPDSCHPTRSIndices(carrier,p),[],1)];
        used=base([data(:);pilots(:)],plane);
        assert(isempty(intersect(used,unique([csi(:);tracking(:);muted(:)]))));
        assert(info.ResourceAccounting.DisjointMasks);
        dlChecks=dlChecks+1;
    end
    if partition.AllowUL && partition.ULSymbolAllocation(2)==14
        [data,info,p]=sixgr.phy.grid.allocREsPUSCH(carrier,current);
        pilots=[reshape(nrPUSCHDMRSIndices(carrier,p),[],1); ...
            reshape(sixgr.phy.resource.puschPTRSGridIndices(carrier,p),[],1)];
        used=base([data(:);pilots(:)],plane);
        assert(isempty(intersect(used,sounding)), ...
            'PUSCH data/DM-RS/PT-RS must not occupy configured SRS REs.');
        assert(info.ResourceAccounting.DisjointMasks);
        ulChecks=ulChecks+1;
    end
end
assert(all(totals>0) && dlChecks>0 && ulChecks>0,'Audit missed an enabled reference family.');
fprintf('20MHZ_REFERENCE_OWNERSHIP_PASS slots=%d ssb=%d csi=%d trs=%d csiim=%d srs=%d dl_allocations=%d ul_allocations=%d\n', ...
    totalSlots,totals,dlChecks,ulChecks);
ok=true;
end

function re=base(indices,plane)
re=unique(mod(double(indices(:))-1,plane));
end
