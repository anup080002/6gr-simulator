function ok=testObservedResourceTrialBinding()
% Declared identity/accounting fixtures, not physical performance evidence.
setup6GRSimToolkit('Verbose',false);
cfg.phy.carrier=struct('NSizeGrid',24,'SubcarrierSpacing',30,'CyclicPrefix',"normal");
hash=string(repmat('a',1,64)); source=string(repmat('b',1,64));
T=table(46,1,1,4660,"DL",45,45,hash, ...
    'VariableNames',{'Slot','UEIndex','BaseStationID','RNTI','GrantDirection', ...
    'DecodedDCIControlAbsoluteSlot','DecodedDCIDataAbsoluteSlot','ConfigHash'});
U=T; U.GrantDirection="UL"; U.DecodedDCIDataAbsoluteSlot=49;
R=[resource("PDCCH","pdcch_DL_ue_1_rnti_4660_control_46_data_46",45,0,0:3,hash,source); ...
   resource("PDCCH","pdcch_DL_ue_1_rnti_4660_control_46_data_46",45,1,4:7,hash,source); ...
   resource("PDCCH","pdcch_UL_ue_1_rnti_4660_control_46_data_50",45,0,8:11,hash,source)];
raw=struct('PDCCH',[T;U]); original=raw;
% Reproduce the heavy-live publication path: runtime control tables do not
% yet carry CSV decoration. Identity must be bound at the active producer,
% not guessed or copied from another row by the energy consumer.
activeCfg=cfg;
activeCfg.run=struct('scenarioID',"declared_identity_fixture", ...
    'runTag',"fixture_run",'executionID',"fixture_execution");
activeCfg.meta.configHash=hash;
live=raw; live.PDCCH.ConfigHash(:)="";
reject(@()sixgr.truth.bindObservedResourcesToTrials(live,cfg,R,hash,source), ...
    'sixgr:truth:ResourceBindingScope');
producer=sixgr.truth.bindCoupledRawTrialIdentity(live,activeCfg);
[~,producerAudit,producerLeft]=sixgr.truth.bindObservedResourcesToTrials( ...
    producer,cfg,R,hash,source);
assert(isempty(producerLeft) && isequal(producerAudit.BoundIntervalCount,[2;1]));
assert(all(live.PDCCH.ConfigHash=="") && ...
    isequal(producer.PDCCH(:,live.PDCCH.Properties.VariableNames(1:end-1)), ...
    live.PDCCH(:,live.PDCCH.Properties.VariableNames(1:end-1))));
for domain=["DL","UL","PBCH","PRACH","PDCCH","PUCCH","SRS","CSIRS","TRS"]
    input=struct(); input.(domain)=live.PDCCH;
    result=sixgr.truth.bindCoupledRawTrialIdentity(input,activeCfg);
    assert(height(result.(domain))==2 && all(result.(domain).ConfigHash==hash) && ...
        all(result.(domain).EvidenceScope=="in_path"));
    input.(domain).ConfigHash(:)=source;
    reject(@()sixgr.truth.bindCoupledRawTrialIdentity(input,activeCfg), ...
        'sixgr:truth:CoupledControlIdentityMismatch');
    input.(domain).ConfigHash(:)="";
    input.(domain).SameScenarioInPathEligible=false(2,1);
    reject(@()sixgr.truth.bindCoupledRawTrialIdentity(input,activeCfg), ...
        'sixgr:truth:CoupledRuntimeEvidenceEligibilityInvalid');
end
empty=struct('DL',table(),'UL',table(),'UnrelatedEvidence',17);
assert(isequaln(sixgr.truth.bindCoupledRawTrialIdentity(empty,activeCfg),empty));
assert(isequaln(sixgr.truth.bindCoupledRawTrialIdentity(live,cfg),live), ...
    'An incomplete lifecycle must not manufacture identity.');
[bound,audit,left]=sixgr.truth.bindObservedResourcesToTrials(raw,cfg,R,hash,source);
assert(isequaln(raw,original) && isempty(left) && isequal(audit.BoundIntervalCount,[2;1]));
E=sixgr.truth.expandExecutedResourceIntervals(bound.PDCCH,cfg);
assert(height(E)==3 && isequal(E.SymbolStart,[0;1;0]) && ...
    isequal(E.EnergyAllocatedPRBSetJSON,["[0,1,2,3]";"[4,5,6,7]";"[8,9,10,11]"]));
other=R; other.CellID(:)=2;
[~,audit,left]=sixgr.truth.bindObservedResourcesToTrials(raw,cfg,other,hash,source);
assert(all(audit.BoundIntervalCount==0) && height(left)==3);
bad=R; bad.UEID(:)=2;
reject(@()sixgr.truth.bindObservedResourcesToTrials(raw,cfg,bad,hash,source), ...
    'sixgr:truth:ResourceBindingUE');
bad=R; bad.UEID(:)=NaN;
reject(@()sixgr.truth.bindObservedResourcesToTrials(raw,cfg,bad,hash,source), ...
    'sixgr:truth:ResourceBindingUE');
bad=R; bad.Direction(:)="UL";
reject(@()sixgr.truth.bindObservedResourcesToTrials(raw,cfg,bad,hash,source), ...
    'sixgr:truth:ResourceBindingDirection');
bad=R; bad.PopulationScopeJSON(:)=string(jsonencode(struct('ConfigHash',"wrong")));
reject(@()sixgr.truth.bindObservedResourcesToTrials(raw,cfg,bad,hash,source), ...
    'sixgr:truth:ResourceBindingScope');
bad=R; bad.Source(:)="planned_grid";
reject(@()sixgr.truth.bindObservedResourcesToTrials(raw,cfg,bad,hash,source), ...
    'sixgr:truth:ResourceBindingAuthority');
reject(@()sixgr.truth.bindObservedResourcesToTrials(raw,cfg,[R;R(1,:)],hash,source), ...
    'sixgr:truth:DuplicateExecutedSymbolInterval');
raw.PDCCH.ExecutionID(:)="run_A";
bad=R; bad.PopulationScopeJSON(:)=string(jsonencode(struct('ConfigHash',hash,'ExecutionID',"run_B")));
reject(@()sixgr.truth.bindObservedResourcesToTrials(raw,cfg,bad,hash,source), ...
    'sixgr:truth:ResourceBindingPopulation');
% Broadcast SSB ownership is the beam and actual resource clock, not the
% common acquisition-report slot or the UE's identity.
B=table(1,1,1,hash,2,1,2,'VariableNames', ...
    {'Slot','UEIndex','BaseStationID','ConfigHash','SSBIndex', ...
    'SSBCandidateCarrierSlot0Based','SSBCandidateSymbolWithinSlot0Based'});
S=resource("SSB","ssb_cell_1_burst_0_index_2_cycle_0",1,2,0:19,hash,source);
S.UEID=NaN; S.PopulationScopeJSON=string(jsonencode(struct('ConfigHash',hash,'ssb_index0',"2")));
[bound,audit]=sixgr.truth.bindObservedResourcesToTrials(struct('PBCH',B),cfg,S,hash,source);
assert(audit.BoundIntervalCount==1);
E=sixgr.truth.expandExecutedResourceIntervals(bound.PBCH,cfg);
assert(E.Slot==2 && E.SymbolStart==2);
% Multi-slot TRS capture must not absorb the next tracking occasion.
V=table(7,1,1,hash,6*.0005*122880000,8*.0005*122880000,122880000, ...
    'VariableNames',{'Slot','UEIndex','BaseStationID','ConfigHash', ...
    'ObservationStartSample','ObservationEndSampleExclusive','ObservationSampleRateHz'});
S=[resource("TRS","trs_slot_6",6,4,0:23,hash,source); ...
   resource("TRS","trs_slot_7",7,8,0:23,hash,source); ...
   resource("TRS","trs_slot_26",26,4,0:23,hash,source)]; S.UEID(:)=NaN;
[bound,audit,left]=sixgr.truth.bindObservedResourcesToTrials(struct('TRS',V),cfg,S,hash,source);
assert(audit.BoundIntervalCount==2 && height(left)==1 && left.AbsoluteSlotIndex0==26);
E=sixgr.truth.expandExecutedResourceIntervals(bound.TRS,cfg);
assert(isequal(E.Slot,[7;8]));
% Two PUCCH identities in one slot must not be guessed.
P=table(45,1,1,hash,'VariableNames',{'Slot','UEIndex','BaseStationID','ConfigHash'});
S=[resource("PUCCH","pucch_slot_44_ue_1",44,12,0,hash,source); ...
   resource("PUCCH","pucch_csi_slot_44_ue_1",44,12,1,hash,source)];
[~,audit,left]=sixgr.truth.bindObservedResourcesToTrials(struct('PUCCH',P),cfg,S,hash,source);
assert(audit.Status=="ambiguous_executed_resource_identity" && height(left)==2);
P.ExecutedAllocationID="pucch_slot_44_ue_1";
[~,audit,left]=sixgr.truth.bindObservedResourcesToTrials(struct('PUCCH',P),cfg,S,hash,source);
assert(audit.BoundIntervalCount==1 && height(left)==1);
ok=true;
end

function T=resource(channel,id,slot,symbol,prbs,hash,source)
direction="DL"; if any(channel==["PUCCH","PUSCH","SRS"]), direction="UL"; end
T=table(direction,channel,1,1,id,slot,symbol,24,14,string(jsonencode(prbs)), ...
    string(jsonencode(struct('ConfigHash',hash))),source, ...
    "retained_executed_TX_RE_occupancy_not_RF_activity", ...
    'VariableNames',{'Direction','Channel','CellID','UEID','AllocationID', ...
    'AbsoluteSlotIndex0','SymbolIndex0','ResourceGridPRBCount','ResourceSymbolsPerSlot', ...
    'PRBSet0BasedJSON','PopulationScopeJSON','SourceSHA256','Source'});
end

function reject(action,id)
try
    action(); error('test:ExpectedRejection','Missing expected rejection.');
catch ex
    assert(string(ex.identifier)==id,'%s: %s',ex.identifier,ex.message);
end
end
