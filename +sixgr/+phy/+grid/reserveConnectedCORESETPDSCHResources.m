function [pdsch,evidence]=reserveConnectedCORESETPDSCHResources(carrier,pdsch,cfg)
% Installed CORESET-based unavailable-resource pattern (TS 38.214 5.1.4.1).
% Identical TX/RX allocation authority; never puncture an already coded TB.
% Outside the configured monitoring calendar no resources are reserved.
evidence=struct('Enabled',false,'ReservedPRBs',zeros(1,0), ...
    'ReservedSymbols',zeros(1,0),'Source',"configured_coreset_pattern_not_measurement");
patterns=string(sixgr.util.structGet(cfg,'phy.pdsch.rateMatchingPattern',strings(0,1)));
if ~any(patterns=="connected_coreset"), return; end
core=cfg.phy.pdcch.coreset;
monitor=cfg.phy.pdcch.operatorControl.connected_monitoring;
sixgr.phy.pdcch.ConnectedPDCCHConfiguration.validatePolicy(monitor);
bitmap=double(core.frequencyResources(:).');
assert(~isempty(bitmap) && all(bitmap==0 | bitmap==1) && any(bitmap), ...
    'sixgr:pdsch:InvalidCORESETReservation','CORESET bitmap must be explicit and binary.');
validateattributes(core.rbStart,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(core.duration,{'numeric'},{'scalar','integer','>=',1,'<=',3});
validateattributes(monitor.period_slots,{'numeric'},{'scalar','integer','positive'});
validateattributes(monitor.offset_slots,{'numeric'},{'scalar','integer','nonnegative','<',monitor.period_slots});
validateattributes(monitor.duration_slots,{'numeric'},{'scalar','integer','>=',1,'<=',monitor.period_slots});
validateattributes(monitor.start_symbol,{'numeric'},{'scalar','integer','nonnegative'});
slot0=double(carrier.NFrame)*double(carrier.SlotsPerFrame)+double(carrier.NSlot);
if mod(slot0-monitor.offset_slots,monitor.period_slots)>=monitor.duration_slots, return; end
carrierPRBs=reshape(core.rbStart+6*(find(bitmap)-1)+(0:5).',1,[]);
symbols=monitor.start_symbol+(0:core.duration-1);
assert(all(carrierPRBs<carrier.NSizeGrid) && all(symbols<carrier.SymbolsPerSlot), ...
    'sixgr:pdsch:CORESETReservationOutsideGrid','Configured CORESET must fit the carrier.');
startBWP=pdsch.NStartBWP; if isempty(startBWP), startBWP=carrier.NStartGrid; end
prbs=intersect(carrierPRBs+carrier.NStartGrid-startBWP,double(pdsch.PRBSet(:).'));
symbols=intersect(symbols,pdsch.SymbolAllocation(1)+(0:pdsch.SymbolAllocation(2)-1));
evidence.Enabled=true;
evidence.ReservedPRBs=prbs; evidence.ReservedSymbols=symbols;
if isempty(prbs) || isempty(symbols), return; end
% Inspect DM-RS BEFORE adding ReservedPRB: the Toolbox can otherwise
% suppress it and mask an illegal configured pattern. PT-RS, unlike DM-RS,
% is mapped on available resources using the installed reservation mask
% (TS 38.211 7.4.1.2.2 / 38.214 5.1.4); verify its final active mapping.
dmrs=nrPDSCHDMRSIndices(carrier,pdsch,'IndexStyle','subscript', ...
    'IndexBase','0based','IndexOrientation','bwp');
assert(~any(ismember(floor(double(dmrs(:,1))/12),prbs) & ...
    ismember(double(dmrs(:,2)),symbols)), ...
    'sixgr:pdsch:CORESETPilotCollision','CORESET pattern must not remove PDSCH DM-RS.');
reserved=nrPDSCHReservedConfig('PRBSet',prbs,'SymbolSet',symbols,'Period',1);
pdsch.ReservedPRB=[pdsch.ReservedPRB,{reserved}];
ptrs=nrPDSCHPTRSIndices(carrier,pdsch,'IndexStyle','subscript', ...
    'IndexBase','0based','IndexOrientation','bwp');
assert(~any(ismember(floor(double(ptrs(:,1))/12),prbs) & ...
    ismember(double(ptrs(:,2)),symbols)), ...
    'sixgr:pdsch:CORESETPTRSCollision','Active PT-RS must not overlap the configured CORESET pattern.');
end
