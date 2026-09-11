function reservation=ssbPRBSymbolReservation(cfg,carrier,absoluteSlot0)
% Configured same-cell SS/PBCH PRB-symbol exclusions, TS 38.214 5.1.4.
% This is allocation authority, not a measured waveform or beam-power row.
validateattributes(absoluteSlot0,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
reservation=struct('Source',"configured_ssb_positions_in_burst", ...
    'Standard',"TS 38.214 V18.6.0 clause 5.1.4", ...
    'AbsoluteSlot0',double(absoluteSlot0),'CarrierPRBSet',[], ...
    'SymbolSet',[],'SSBIndices0',[],'ReservedCarrierRE0',[], ...
    'SSBLowOffsetFromPointAHz',NaN,'SSBHighOffsetFromPointAHz',NaN);
if ~logical(sixgr.util.structGet(cfg,'phy.ssb.enable',false)), return; end
assert(mod(absoluteSlot0,carrier.SlotsPerFrame)==mod(carrier.NSlot,carrier.SlotsPerFrame), ...
    'sixgr:phy:ssb:ReservationClockMismatch','SSB exclusion and data must share one slot clock.');
timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
plan=sixgr.phy.ia.SSBBurstPlan.fromConfig(cfg,timing);
assert(timing.CarrierSubcarrierSpacingKHz==carrier.SubcarrierSpacing && ...
    timing.GridRelationship.NStartGrid==carrier.NStartGrid && ...
    timing.GridRelationship.NSizeGrid==carrier.NSizeGrid, ...
    'sixgr:phy:ssb:ReservationCarrierMismatch','SSB and data carrier grids must agree.');
grid=timing.GridRelationship;
low=double(grid.SSBLowOffsetFromPointAHz); high=double(grid.SSBHighOffsetFromPointAHz);
rbLow=((0:carrier.NSizeGrid-1)+carrier.NStartGrid)*12*carrier.SubcarrierSpacing*1e3;
prbs=find(rbLow<high & rbLow+12*carrier.SubcarrierSpacing*1e3>low)-1;
spec=struct('SCSKHz',double(carrier.SubcarrierSpacing),'CyclicPrefix',string(carrier.CyclicPrefix));
count=double(carrier.SymbolsPerSlot);
edges=zeros(1,count+1,'int64');
for k=0:count
    instant=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol( ...
        absoluteSlot0+floor(k/count),mod(k,count),spec);
    edges(k+1)=instant.Ticks;
end
period=double(timing.PeriodicityMs)*double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/1000;
validateattributes(period,{'numeric'},{'scalar','integer','positive','finite'});
period=int64(period);
epoch=idivide(edges(1),period,'floor')*period;
active=false(1,count); observed=[];
for index=double(plan.ActiveSSBIndices0Based(:).')
    symbol=double(timing.CandidateStartSymbols(index+1));
    start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(floor(symbol/14),mod(symbol,14),timing.Mu);
    stop=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(floor((symbol+4)/14),mod(symbol+4,14),timing.Mu);
    phase=rem(start.Ticks,period); duration=stop.Ticks-start.Ticks;
    for delta=[-1 0]
        first=epoch+int64(delta)*period+phase;
        if first<0, continue; end
        hit=edges(1:end-1)<first+duration & edges(2:end)>first;
        if any(hit), observed(end+1)=index; end %#ok<AGROW>
        active=active|hit;
    end
end
symbols=find(active)-1;
if isempty(symbols), prbs=[]; end
indices=zeros(0,1);
if ~isempty(prbs) && ~isempty(symbols)
    [k,l]=ndgrid(reshape(12*prbs+(0:11).',1,[]),symbols);
    indices=double(k(:)+12*carrier.NSizeGrid*l(:));
end
reservation.CarrierPRBSet=double(prbs);
reservation.SymbolSet=double(symbols);
reservation.SSBIndices0=unique(observed,'stable');
reservation.ReservedCarrierRE0=indices;
reservation.SSBLowOffsetFromPointAHz=low;
reservation.SSBHighOffsetFromPointAHz=high;
end
