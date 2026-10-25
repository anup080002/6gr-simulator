function [pdsch, receipt] = reservePDSCHReferenceRE(carrier,pdsch,referenceZero,varargin)
%RESERVEPDSCHREFERENCERE Reserve exact carrier-oriented reference REs.
% Native data/pilot allocation supplies active physical PRB/symbol support,
% including VRB mapping and ReservedPRB holes. Collisions stay in the carrier
% domain; only the final append uses nrPDSCHConfig.ReservedRE's BWP stride.
% No signal generation, grant change, whole-PRB puncturing, or waveform edit.
p = inputParser;
addParameter(p,'SignalName',"reference");
addParameter(p,'DMRSCollisionIdentifier',"sixgr:phy:grid:ReferenceDMRSCollision");
addParameter(p,'RejectExistingReservations',false,@(x) islogical(x) && isscalar(x));
addParameter(p,'ExistingCollisionIdentifier',"sixgr:phy:grid:ReferenceReservationCollision");
addParameter(p,'RejectPTRS',false,@(x) islogical(x) && isscalar(x));
addParameter(p,'PTRSCollisionIdentifier',"sixgr:phy:grid:ReferencePTRSCollision");
parse(p,varargin{:});
o = p.Results;
assert(isa(carrier,'nrCarrierConfig') && isscalar(carrier) && ...
    isa(pdsch,'nrPDSCHConfig') && isscalar(pdsch), ...
    'sixgr:phy:grid:ReferenceReservationObjects','Original native carrier/PDSCH objects are required.');
validateattributes(referenceZero,{'numeric'}, ...
    {'real','finite','integer','nonnegative'},mfilename,'referenceZero');
K = 12*double(carrier.NSizeGrid);
L = double(carrier.SymbolsPerSlot);
startBWP = pdsch.NStartBWP;
if isempty(startBWP), startBWP = carrier.NStartGrid; end
sizeBWP = pdsch.NSizeBWP;
if isempty(sizeBWP), sizeBWP = carrier.NSizeGrid; end
offset = 12*(double(startBWP)-double(carrier.NStartGrid));
bwpK = 12*double(sizeBWP);
referenceBase = unique(mod(double(referenceZero(:)),K*L),'sorted');
receipt = struct('IndexDomain',"carrier_grid_zero_based", ...
    'ReservedREIndexDomain',"bwp_grid_zero_based_union_across_layers", ...
    'CarrierIndices0Based',zeros(0,1),'BWPIndices0Based',zeros(0,1), ...
    'CarrierSubcarrierCount',K,'BWPSubcarrierCount',bwpK, ...
    'BWPSubcarrierOffset',offset,'SymbolsPerSlot',L);
if isempty(referenceBase), return; end

% Clear only RE-level exclusions on this value copy: a subsequent reference
% must still see an earlier reservation when checking conflicting ownership.
% Retain whole-PRB exclusions, native VRB mapping, layers and all pilot policy.
unreserved = pdsch;
unreserved.ReservedRE = [];
data = nrPDSCHIndices(carrier,unreserved,'IndexBase','0based','IndexOrientation','carrier');
dmrs = nrPDSCHDMRSIndices(carrier,unreserved,'IndexBase','0based','IndexOrientation','carrier');
ptrs = nrPDSCHPTRSIndices(carrier,unreserved,'IndexBase','0based','IndexOrientation','carrier');
nativeBase = unique(mod(double([data(:);dmrs(:);ptrs(:)]),K*L));
% The footprint includes CDM no-data holes within an active PRB/symbol, but
% never revives a native ReservedPRB hole or a virtual/unmapped PRB.
activeRBSymbols = unique(floor(nativeBase/12));
support = reshape(12*activeRBSymbols(:).'+(0:11).',[],1);
selected = intersect(referenceBase,support,'sorted');
if isempty(selected), return; end
existing = unique(mod(double(pdsch.ReservedRE(:)),bwpK*L));
existingCarrier = mod(existing,bwpK)+offset+K*floor(existing/bwpK);
if o.RejectExistingReservations && ~isempty(intersect(selected,existingCarrier))
    error(char(o.ExistingCollisionIdentifier), ...
        '%s overlaps an existing serving reference reservation.',char(o.SignalName));
end
dmrsBase = unique(mod(double(dmrs(:)),K*L));
collision = intersect(selected,dmrsBase);
if ~isempty(collision)
    error(char(o.DMRSCollisionIdentifier), ...
        ['Configured %s overlaps %d active PDSCH DM-RS RE(s) in slot %d. ' ...
         'DM-RS puncturing is not permitted.'], ...
        char(o.SignalName),numel(collision),double(carrier.NSlot));
end
% Preserve the existing CSI-IM rule against the CURRENT active PT-RS map,
% including earlier reference reservations in the declared reservation order.
if o.RejectPTRS
    currentPTRS = nrPDSCHPTRSIndices(carrier,pdsch,'IndexBase','0based', ...
        'IndexOrientation','carrier');
    if ~isempty(intersect(selected,mod(double(currentPTRS(:)),K*L)))
        error(char(o.PTRSCollisionIdentifier),'%s cannot puncture PDSCH PT-RS.',char(o.SignalName));
    end
end
sc = mod(selected,K)-offset;
assert(all(sc>=0 & sc<bwpK),'sixgr:phy:grid:ReferenceReservationOutsideBWP', ...
    'Native PDSCH reference support must remain inside its original BWP.');
reservedBWP = sc+bwpK*floor(selected/K);
pdsch.ReservedRE = unique([double(pdsch.ReservedRE(:));reservedBWP(:)],'sorted');
receipt.CarrierIndices0Based = selected;
receipt.BWPIndices0Based = reservedBWP;
end
