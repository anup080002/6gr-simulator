function [available,excluded]=pdschPRBsWithoutReservedDMRS(carrier,pdsch,reservedCarrierRE0)
% Exclude whole BWP-relative PRBs whose actual DM-RS hit reserved carrier REs.
% This is resource-pool geometry, not a grant, TBS estimate or waveform.
available=double(pdsch.PRBSet(:).');
excluded=zeros(1,0);
validateattributes(reservedCarrierRE0,{'numeric'}, ...
    {'real','finite','integer','nonnegative'});
assert(all(reservedCarrierRE0(:)<12*carrier.NSizeGrid*carrier.SymbolsPerSlot), ...
    'sixgr:phy:grid:ReservedREOutsideCarrier','Reserved REs must address this carrier slot.');
if isempty(reservedCarrierRE0) || isempty(available), return; end
dmrs=nrPDSCHDMRSIndices(carrier,pdsch,'IndexStyle','subscript', ...
    'IndexBase','0based','IndexOrientation','carrier');
base=double(dmrs(:,1))+12*carrier.NSizeGrid*double(dmrs(:,2));
hits=ismember(base,reservedCarrierRE0);
excluded=unique(floor(double(dmrs(hits,1))/12)).';
bwpStart=pdsch.NStartBWP;
if isempty(bwpStart), bwpStart=carrier.NStartGrid; end
excluded=excluded+carrier.NStartGrid-bwpStart;
available=setdiff(available,excluded,'stable');
end
