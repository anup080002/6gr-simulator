function ok=testProductionPDSCHProcessingBudget()
% Actual DM-RS must select the 38.214 5.3 N1 column at the grant boundary.
setup6GRSimToolkit('Verbose',false);
cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
cfg.phy.pdsch.numLayers=1; cfg.phy.pdsch.nLayers=1;
cfg.phy.pdsch.numPorts=1; cfg.phy.pdsch.nPorts=1;
cfg.phy.pdsch.dmrs.portSet=0; cfg.phy.pdsch.dmrs.DMRSPortSet=0;
cfg.phy.pdsch.dmrs.additionalPositions=0;
grant=struct('Direction',"DL",'ControlAbsoluteSlot',0, ...
    'ControlSymbolAllocation',[0 2],'SymbolAllocation',[0 14], ...
    'PRBSet',0:23,'NumLayers',1,'Modulation',"QPSK", ...
    'HARQFeedbackSymbolAllocation',[0 2],'TimingAdvanceTicks',int64(0), ...
    'HARQProcessID',3);
tick30=int64((2048+144)*64/2);
before=rng;
base=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(base.Valid, '%s: %s',base.ReasonCode,base.Diagnostic);
assert(base.HARQACKDecision.MinimumProcessingTicks==10*tick30);
cfg.phy.pdsch.dmrs.additionalPositions=2;
extra=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(extra.Valid, '%s: %s',extra.ReasonCode,extra.Diagnostic);
fprintf('HARQ_N1_POS2_ACTUAL_TICKS=%d EXPECTED_TICKS=%d\n', ...
    extra.HARQACKDecision.MinimumProcessingTicks,13*tick30);
assert(extra.HARQACKDecision.MinimumProcessingTicks==13*tick30, ...
    'Additional DM-RS at 30 kHz requires N1=13, not the pos0 N1=10 allowance.');
assert(extra.HARQACKDecision.ProcessingBudget.DMRSAdditionalPosition==2 && ...
    numel(extra.HARQACKDecision.ProcessingBudget.PDSCHDMRSSymbols)>1);
% This deadline was wrongly admitted by the old pos0-only adapter.
grant.TimingAdvanceTicks=extra.HARQACKDecision.ProcessingGapTicks-11*tick30;
early=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(~early.Valid && early.ReasonCode== ...
    "harq_ack_timing_rejected:insufficient_n1_processing_time");
% Exact boundary remains admitted; one Tc tick earlier remains rejected.
grant.TimingAdvanceTicks=extra.HARQACKDecision.ProcessingGapTicks-13*tick30;
edge=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(edge.Valid);
grant.TimingAdvanceTicks=grant.TimingAdvanceTicks+int64(1);
early=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(~early.Valid && early.ReasonCode== ...
    "harq_ack_timing_rejected:insufficient_n1_processing_time");
% Short Type-A grants require the allocation-dependent d1,1 as well.
cfg.phy.pdsch.dmrs.additionalPositions=0;
grant.TimingAdvanceTicks=int64(0); grant.SymbolAllocation=[2 4];
short=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(short.Valid, '%s: %s',short.ReasonCode,short.Diagnostic);
assert(short.HARQACKDecision.MinimumProcessingTicks==12*tick30 && ...
    short.HARQACKDecision.ProcessingBudget.D11Symbols==2);
% Before a per-UE grant is frozen, the scheduler probe uses installed rank.
% Both supported configuration spellings must resolve the same native map.
legacy=cfg; legacy.phy.pdsch=rmfield(legacy.phy.pdsch,'numLayers');
probe=rmfield(grant,'NumLayers');
alias=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(legacy,probe);
assert(alias.Valid && isequal(alias.HARQACKDecision.ProcessingBudget, ...
    short.HARQACKDecision.ProcessingBudget));
missing=legacy; missing.phy.pdsch=rmfield(missing.phy.pdsch,'nLayers');
invalid=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(missing,probe);
assert(~invalid.Valid && invalid.ReasonCode=="pdsch_processing_allocation_invalid");
assert(isequal(before,rng),'Timing resolution must not advance receiver RNG state.');
ok=true; disp('PRODUCTION_PDSCH_PROCESSING_BUDGET_PASS');
end
