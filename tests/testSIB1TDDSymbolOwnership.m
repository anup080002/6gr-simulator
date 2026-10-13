function ok=testSIB1TDDSymbolOwnership()
% Validate complete common-channel allocations, not a slot-level DL flag.
% These are configured-resource checks, not measured acquisition outcomes.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
    'simulator','configs','scenarios', ...
    'lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
carrier=sixgr.phy.grid.makeCarrier(cfg);
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
[control,siCfg,siCarrier,~,slot0]= ...
    sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,cfg);
data=sixgr.phy.broadcast.configuredSIB1Allocation(siCarrier,siCfg);
assert(slot0==2 && frame.IsDLAllocation(slot0,data.SymbolAllocation));
assert(frame.IsDLAllocation(slot0,[control.SearchSpace.StartSymbolWithinSlot ...
    control.CORESET.Duration]));

% The same installed MIB table maps candidate one to mixed slot three.
% PDCCH fits but SIB1 symbols 2:13 cross flexible and UL ownership.
mixed=cfg; mixed.phy.ssb.runtimeSSBIndex=1;
assert(frame.SlotPartition(3).AllowDL && ...
    frame.IsDLAllocation(3,[0 2]) && ~frame.IsDLAllocation(3,[2 12]));
localReject(@()sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,mixed), ...
    'sixgr:phy:broadcast:SIB1SymbolsNotDLCapable');

% One DL symbol is not enough for this two-symbol CORESET either.
shortControl=mixed;
shortControl.phy.duplex.tddCommon=struct('ReferenceSubcarrierSpacingKHz',15, ...
    'Pattern1',struct('PeriodicityMilliseconds',5,'NumDownlinkSlots',3, ...
        'NumDownlinkSymbols',1,'NumUplinkSlots',1,'NumUplinkSymbols',2));
shortFrame=sixgr.phy.FrameStructureEngine(shortControl,'FrameCoreOnly',true);
assert(shortFrame.SlotPartition(3).AllowDL && ~shortFrame.IsDLAllocation(3,[0 2]));
localReject(@()sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,shortControl), ...
    'sixgr:phy:broadcast:Type0ControlSymbolsNotDLCapable');

% A fully UL occasion retains its original, distinct rejection.
uplink=cfg; uplink.phy.ssb.runtimeSSBIndex=2;
localReject(@()sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,uplink), ...
    'sixgr:phy:broadcast:Type0OccasionNotDLCapable');

% Only an explicitly configured legal second monitoring occasion may move
% this candidate's SI to slot five. The resolver must never silently search.
later=uplink;
later.initial_access.type0.monitoring_occasion_ordinal=2;
[~,laterCfg,laterCarrier,~,laterSlot]= ...
    sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,later);
laterData=sixgr.phy.broadcast.configuredSIB1Allocation(laterCarrier,laterCfg);
assert(laterSlot==5 && frame.IsDLAllocation(laterSlot,laterData.SymbolAllocation));
assert(cfg.phy.ssb.runtimeSSBIndex==0 && ...
    cfg.initial_access.type0.monitoring_occasion_ordinal==1);
fprintf('SIB1_TDD_SYMBOL_OWNERSHIP_PASS full_DL, mixed, UL, explicit_second_occasion; waveform_qualification=0\n');
ok=true;
end

function localReject(action,identifier)
try
    action();
catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s', ...
        identifier,cause.identifier,cause.message);
    return;
end
error('testSIB1TDDSymbolOwnership:MissingRejection', ...
    'Configured common-channel symbols outside fixed DL must be rejected (%s).',identifier);
end
