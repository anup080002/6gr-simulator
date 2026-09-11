function [pdsch,reservation]=reserveSSBPDSCHResources(carrier,pdsch,cfg)
% Install the configured broadcast exclusion before rate matching, never
% puncture DM-RS or infer an SI scheduling indicator from a receiver result.
absoluteSlot0=double(sixgr.util.structGet(cfg,'lls6g.runtime.AbsoluteSlotIndex0', ...
    double(carrier.NFrame)*double(carrier.SlotsPerFrame)+double(carrier.NSlot)));
reservation=sixgr.phy.frame.ssbPRBSymbolReservation(cfg,carrier,absoluteSlot0);
if isempty(reservation.ReservedCarrierRE0), return; end
bwpStart=pdsch.NStartBWP; if isempty(bwpStart), bwpStart=carrier.NStartGrid; end
bwpSize=pdsch.NSizeBWP; if isempty(bwpSize), bwpSize=carrier.NSizeGrid; end
prbs=reservation.CarrierPRBSet+carrier.NStartGrid-bwpStart;
prbs=prbs(prbs>=0 & prbs<bwpSize);
scheduledSymbols=pdsch.SymbolAllocation(1)+(0:pdsch.SymbolAllocation(2)-1);
if isempty(intersect(prbs,pdsch.PRBSet)) || ...
        isempty(intersect(reservation.SymbolSet,scheduledSymbols)), return; end
if pdsch.RNTI==65535
    indicator=sixgr.util.structGet(cfg,'phy.pdsch.systemInformationIndicator',NaN);
    assert(isnumeric(indicator) && isscalar(indicator) && any(indicator==[0 1]), ...
        'sixgr:phy:ssb:MissingSystemInformationIndicator', ...
        'SI-RNTI PDSCH requires its actual DCI system-information indicator.');
    assert(indicator~=0,'sixgr:phy:ssb:SIB1PDSCHCollision', ...
        'SI indicator 0 requires no transmitted SS/PBCH on the scheduled PDSCH resources.');
end
dmrs=nrPDSCHDMRSIndices(carrier,pdsch,'IndexStyle','subscript', ...
    'IndexBase','0based','IndexOrientation','carrier');
dmrsBase=double(dmrs(:,1))+12*carrier.NSizeGrid*double(dmrs(:,2));
collision=intersect(dmrsBase,reservation.ReservedCarrierRE0);
assert(isempty(collision),'sixgr:phy:grid:allocREsPDSCH:SSBDMRSCollision', ...
    ['SS/PBCH excludes %d scheduled PDSCH DM-RS REs in absolute slot %g. ' ...
     'The scheduler must select a legal PRB/TDRA allocation before coding.'], ...
    numel(collision),absoluteSlot0);
reserved=nrPDSCHReservedConfig;
reserved.PRBSet=prbs;
reserved.SymbolSet=reservation.SymbolSet;
reserved.Period=1;
pdsch.ReservedPRB=[pdsch.ReservedPRB,{reserved}];
end
