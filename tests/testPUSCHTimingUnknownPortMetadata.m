function ok=testPUSCHTimingUnknownPortMetadata()
% Unknown replay metadata must not override installed UL codebook ports.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
cfg.phy.pusch.numLayers=1; cfg.phy.pusch.nLayers=1;
cfg.phy.pusch.numAntennaPorts=2; cfg.phy.pusch.NumAntennaPorts=2;
cfg.phy.pusch.transmissionScheme='codebook';
cfg.phy.pusch.transformPrecoding=false;
cfg.phy.pusch.dmrs.portSet=0; cfg.phy.pusch.dmrs.DMRSPortSet=0;
grant=struct('Direction','UL','ControlAbsoluteSlot',0,'RNTI',1, ...
    'NumLayers',1,'PRBSet',0:5,'SymbolAllocation',[0 14], ...
    'ControlSymbolAllocation',[0 2],'TPMI',2,'TimingAdvanceTicks',int64(0));
baseline=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(baseline.Valid,'Baseline two-port timing rejected: %s %s', ...
    baseline.ReasonCode,baseline.Diagnostic);
grant.NumLogicalPorts=NaN;
replay=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(replay.Valid,'Unknown replay port metadata overrides installed two-port capability: %s %s', ...
    replay.ReasonCode,replay.Diagnostic);
assert(replay.K2==baseline.K2 && ...
    replay.DataDecision.MinimumProcessingTicks==baseline.DataDecision.MinimumProcessingTicks);
% A genuinely supplied incompatible allocation must still be rejected.
grant.NumAntennaPorts=1;
bad=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(~bad.Valid && bad.ReasonCode=="pusch_processing_allocation_invalid" && ...
    contains(bad.Diagnostic,'InvalidTPMI'));
grant.NumAntennaPorts=2;
explicit=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(explicit.Valid);
grant.NumAntennaPorts=NaN; grant.PortCount=2;
alias=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(alias.Valid,'Unknown aliases must not conceal a known grant port count.');
grant.NumAntennaPorts=Inf;
invalid=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
assert(~invalid.Valid && invalid.ReasonCode=="pusch_processing_allocation_invalid", ...
    'Invalid supplied port counts must not fall back to a valid installed allocation.');
fprintf('PUSCH_TIMING_UNKNOWN_PORT_METADATA_PASS installed_ports=2 rank=1 tpmi=2\n');
ok=true;
end
