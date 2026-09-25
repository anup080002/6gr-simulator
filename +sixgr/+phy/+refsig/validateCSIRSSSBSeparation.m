function evidence=validateCSIRSSSBSeparation(cfg)
% Reject same-cell CSI-RS inside configured SS/PBCH PRB/symbol ownership.
% This validates a resource configuration, never measured SINR or reception.
evidence=struct('Applicable',false,'CycleSlots',0,'CheckedOccasions',0);
if ~logical(sixgr.util.structGet(cfg,'phy.csirs.enable',false)) || ...
        ~logical(sixgr.util.structGet(cfg,'phy.ssb.enable',false))
    return;
end
[~,~]=sixgr.phy.refsig.csirsOccasion(cfg,0); % Validate the installed calendar.
carrier=sixgr.phy.grid.makeCarrier(cfg);
timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
ssbPeriod=double(timing.PeriodicityMs)*double(carrier.SlotsPerSubframe);
validateattributes(ssbPeriod,{'numeric'},{'scalar','finite','integer','positive'});
csiPeriod=double(cfg.phy.csirs.period_slots);
cycle=lcm(ssbPeriod,csiPeriod);
plane=12*double(carrier.NSizeGrid)*double(carrier.SymbolsPerSlot);
evidence.Applicable=true; evidence.CycleSlots=cycle;
for slot0=double(cfg.phy.csirs.offset_slots):csiPeriod:cycle-1
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    c=sixgr.phy.grid.makeCarrier(current);
    reservation=sixgr.phy.frame.ssbPRBSymbolReservation(current,c,slot0);
    if isempty(reservation.ReservedCarrierRE0), continue; end
    [indices,~,info]=sixgr.phy.refsig.csirs(c,current);
    assert(info.Enabled && ~isempty(indices), ...
        'sixgr:phy:csirs:MissingScheduledResource', ...
        'The installed periodic CSI-RS must materialize at absolute slot %d.',slot0);
    overlap=intersect(unique(mod(double(indices(:))-1,plane)), ...
        reservation.ReservedCarrierRE0);
    evidence.CheckedOccasions=evidence.CheckedOccasions+1;
    assert(isempty(overlap),'sixgr:phy:csirs:SSBResourceCollision', ...
        ['CSI-RS overlaps %d SS/PBCH-reserved RE locations at absolute slot %d, ' ...
         'symbol(s) %s. Correct reference_signals.csi_rs_resource_symbol_locations ' ...
         'or its resource frequency/calendar configuration before waveform execution.'], ...
        numel(overlap),slot0,mat2str(unique(floor(overlap/(12*c.NSizeGrid))).'));
end
end
