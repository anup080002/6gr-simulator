function ok=testPUSCHPreparationAllocationTiming()
% Allocation-derived TS 38.214 6.4 timing; no waveform/field-quality claim.
setup6GRSimToolkit('Verbose',false);
cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
grant=struct('Direction','UL','ControlAbsoluteSlot',0, ...
    'ControlSymbolAllocation',[0 2],'SymbolAllocation',[0 14], ...
    'TimingAdvanceTicks',int64(0),'K2',1);
tooEarly=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(~tooEarly.Valid && tooEarly.ReasonCode== ...
    "data_timing_rejected:insufficient_n2_processing_time", ...
    'A first-symbol data allocation needs N2+d2,1, not base N2 alone.');
later=grant; later.K2=2;
before=rng;
legal=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,later);
assert(isequal(before,rng),'Resource-derived timing must not consume waveform randomness.');
assert(legal.Valid && legal.DataDecision.ProcessingBudget.D21Symbols==1);
slack=legal.DataDecision.ProcessingGapTicks-legal.DataDecision.MinimumProcessingTicks;
later.TimingAdvanceTicks=slack;
atDeadline=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,later);
assert(atDeadline.Valid,'Exactly sufficient N2+d2,1 time must be accepted.');
later.TimingAdvanceTicks=slack+int64(1);
early=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,later);
assert(~early.Valid && early.ReasonCode=="data_timing_rejected:insufficient_n2_processing_time");
scheduled=sixgr.link.resolveWaveformGrant(cfg,'UL',0);
scheduled.SymbolAllocation=[2 12];
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','UL');
changed=scheduler.finalizeExactPHYFeasibility(scheduled);
assert(~changed.ExactPHYFeasible && contains(string(changed.ExactPHYInfeasibilityReason), ...
    'grant_timing_identity_mismatch:SymbolAllocation'), ...
    'A changed first-symbol mapping must not retain the earlier timing decision.');

for scs=[15 30 60]
    mu=log2(scs/15);
    for cp=["normal","extended"]
        if cp=="extended" && scs~=60, continue; end
        carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',scs,'CyclicPrefix',cp);
        for configType=[1 2]
            maxCDM=configType+1;
            for cdm=[1 maxCDM]
                p=nrPUSCHConfig('PRBSet',3:10,'SymbolAllocation',[2 8],'MappingType','A');
                p.DMRS.DMRSTypeAPosition=2;
                p.DMRS.DMRSConfigurationType=configType;
                p.DMRS.NumCDMGroupsWithoutData=cdm;
                b=sixgr.phy.frame.puschPreparationProcessingTime(carrier,p,[mu 0]);
                expectedD21=double(cdm~=maxCDM);
                counts=[10 12 23];
                expected=max((counts([mu+1 1])+expectedD21)*((2048+144)*64)./(2.^[mu 0]));
                assert(b.D21Symbols==expectedD21 && b.Ticks==int64(expected));
                assert(b.FirstSymbolDMRSRE>0 && b.FirstSymbolDMRSOnly==(expectedD21==0));
                assert((b.FirstSymbolDataRE>0)==(expectedD21==1));
            end
        end
    end
end
% No data at symbol zero is insufficient to claim DM-RS-only: this full
% allocation actually starts before its type-A DM-RS at symbol two.
carrier=nrCarrierConfig('NSizeGrid',24);
p=nrPUSCHConfig('PRBSet',0:7,'SymbolAllocation',[0 14]);
b=sixgr.phy.frame.puschPreparationProcessingTime(carrier,p,[1 0]);
assert(b.D21Symbols==1 && ~b.FirstSymbolDMRSOnly && b.FirstSymbolDMRSRE==0);
p.TransformPrecoding=true; p.MappingType='B'; p.SymbolAllocation=[0 8];
b=sixgr.phy.frame.puschPreparationProcessingTime(carrier,p,[1 0]);
assert(b.D21Symbols==0 && b.FirstSymbolDMRSOnly && b.FirstSymbolDataRE==0, ...
    'DFT-s-OFDM first-symbol DM-RS occupancy must use the actual resource map.');
ok=true; disp('PUSCH_PREPARATION_ALLOCATION_TIMING_PASS');
end
