function ok=test20MHzFullSymbolDataAllocation()
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
% Use full and special DL slots without common SSB/SIB1 ownership. At mu=1
% SSB occupies slots 0/1, unlike the former mu=0 layout; it is not legal to
% require a full-band DM-RS-bearing PDSCH through those resources.
for slot0=[2 3 5 6 7 8]
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    c=sixgr.phy.grid.makeCarrier(current);
    allocation=[0 14]; if mod(slot0,5)==3, allocation=[0 10]; end
    for rank=[1 2 4]
        [data,info,p]=sixgr.phy.grid.allocREsPDSCH(c,current, ...
            'PRBSet',0:(c.NSizeGrid-1),'SymbolAllocation',allocation,'NumLayers',rank);
        assert(~isempty(data) && info.G>0 && p.NumLayers==rank);
        base=mod(double(data(:))-1,12*c.NSizeGrid*c.SymbolsPerSlot);
        sym=floor(base/(12*c.NSizeGrid)); rb=floor(mod(base,12*c.NSizeGrid)/12);
        assert(~any(sym<2 & rb<48) && any(sym==0 & rb>=48) && any(sym==1 & rb>=48));
        assert(max(sym)<sum(allocation));
        % Frozen resource accounting comes from this exact native mapping.
        assert(info.ModulationSymbolCount==numel(data));
    end
end
% Keep the collision guard and demonstrate a valid pre-coding alternative.
current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,2);
c=sixgr.phy.grid.makeCarrier(current);
try
    sixgr.phy.grid.allocREsPDSCH(c,current,'PRBSet',0:50, ...
        'SymbolAllocation',[0 14],'NumLayers',4);
    error('test20MHzFullSymbolDataAllocation:MissingSSBGuard','SSB/DM-RS collision was accepted.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:phy:grid:allocREsPDSCH:SSBDMRSCollision'),cause.message);
end
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
candidate=struct('PRBStart',0,'NumPRB',15,'SymbolStart',0,'NumSymbols',14);
assert(plan.checkConnectedPDSCH(candidate,1));
[data,info]=sixgr.phy.grid.allocREsPDSCH(c,current,'PRBSet',0:14, ...
    'SymbolAllocation',[0 14],'NumLayers',4);
assert(~isempty(data) && info.G>0);
% The eight-resource reference window must include the latest completed
% CSI occasion; source/feedback chronology stays intact at the faster rate.
assert(sixgr.truth.periodicCSIReferenceSlot(cfg,19)>=6);
assert(cfg.phy.linkAdaptation.rankIncreaseConfirmationReports==1);
assert(~cfg.run.runtimeCheckpointEnabled);
ok=true; disp('20MHZ_FULL_SYMBOL_DATA_ALLOCATION_PASS ranks=1,2,4 full_DL=0:13 special_DL=0:9');
end
