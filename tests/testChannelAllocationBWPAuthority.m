function ok = testChannelAllocationBWPAuthority()
%TESTCHANNELALLOCATIONBWPAUTHORITY Native carrier/BWP index-domain regression.
% Declared native-index fixtures only, <=24 carrier RBs: no scheduled grant,
% channel, receiver, waveform execution, or general BWP-switch qualification.
% The native R2026a API is the allocation reference, not an independent PHY.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
before = rng;
groups = {@localDLDomains,@localULDomains,@localReservedREProjection, ...
    @localReservationGuards,@localPhysicalHopsAndVRBs,@localSameSymbolSharing, ...
    @localCORESETOrigins};
names = ["DL_native_domains","UL_native_domains","BWP_reserved_RE", ...
    "reservation_guards","physical_hops_and_VRBs","same_symbol_sharing", ...
    "native_CORESET_REG_origins"];
failures = strings(0,1);
for k = 1:numel(groups)
    try
        groups{k}();
        fprintf('[PASS] ChannelAllocationBWPAuthority %s\n',names(k));
    catch cause
        failures(end+1,1) = names(k)+": "+string(cause.identifier)+ ...
            " "+string(cause.message); %#ok<AGROW>
        fprintf(2,'[FAIL] ChannelAllocationBWPAuthority %s\n',failures(end));
    end
end
assert(isequal(before,rng),'Native allocation inspection must not consume RNG.');
assert(isempty(failures),'testChannelAllocationBWPAuthority:Failed', ...
    '%d/%d groups failed:\n%s',numel(failures),numel(groups),char(strjoin(failures,newline)));
ok = true;
end

function localDLDomains()
for variant = 1:5
    [carrier,channel] = localDLFixture(variant);
    originalCarrier = carrier;
    originalChannel = channel;
    [expected,data,dmrs,ptrs] = localDLNative(carrier,channel);
    actual = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(carrier,channel);
    localAssertNative(carrier,actual,expected,'D');
    localAssertIndices(actual.Data,data);
    localAssertIndices(actual.DMRS,dmrs);
    localAssertIndices(actual.PTRS,ptrs);
    assert(isequal(originalCarrier,carrier) && isequal(originalChannel,channel));
    if variant>=3
        assert(actual.Allocation.StartRB==6+min(channel.PRBSet));
        legacy = actual.Allocation;
        legacy.StartRB = min(channel.PRBSet);
        legacy.NumRB = max(channel.PRBSet)-min(channel.PRBSet)+1;
        localThrows(@() localValidate(carrier,legacy,'D'), ...
            'sixgr:phy:frame:RECoordinatesOutsideAllocation');
    end
end
end

function localULDomains()
for variant = 1:5
    for transform = [false true]
        [carrier,pusch] = localULFixture(variant,transform);
        original = pusch;
        [expected,data,dmrs,ptrs,nativePTRS] = localULNative(carrier,pusch);
        actual = sixgr.phy.frame.ChannelAllocationMaterializer.materializePUSCH(carrier,pusch);
        localAssertNative(carrier,actual,expected,'U');
        localAssertIndices(actual.Data,data);
        localAssertIndices(actual.DMRS,dmrs);
        localAssertIndices(actual.PTRS,ptrs);
        assert(isequal(actual.Data.GridIndices1Based,data) && ...
            isequal(actual.PTRS.NativeIndices1Based,nativePTRS) && ...
            isequal(actual.PTRS.GridIndices1Based,ptrs) && ...
            isequal(actual.TransformPrecoding,transform));
        if transform
            assert(all(ismember(ptrs(:),data(:))) && ...
                actual.PTRS.EmbeddedInData && ~actual.PTRS.IndependentPhysicalOccupancy);
        end
        assert(isequal(original,pusch));
    end
end
end

function localReservedREProjection()
for variant = [3 5]
    [carrier,pdsch] = localDLFixture(variant);
    pdsch.NumLayers = 2;
    pdsch.DMRS.DMRSPortSet = [0 1];
    pdsch.MappingType = 'B';
    pdsch.SymbolAllocation = [4 6];
    [~,unreservedData] = localDLNative(carrier,pdsch);
    bwpData = localBWPLinearIndices(carrier,pdsch,"PDSCH_DATA");
    bwpK = 12*double(pdsch.NSizeBWP);
    carrierK = 12*double(carrier.NSizeGrid);
    L = double(carrier.SymbolsPerSlot);
    % One input on layer 1 (zero-based) excludes this RE on BOTH layers.
    % Duplicate layers, wrapped native pages, and BWP reservations outside
    % this PDSCH must not create extra channel occupancy or fictitious ports.
    selected = bwpData(1,2)-1;
    outsidePRB = 12*11 + bwpK*5;
    outsideSymbol = 12*double(pdsch.PRBSet(1)) + bwpK*(L-1);
    pdsch.ReservedRE = [selected,selected-bwpK*L, ...
        selected+2*bwpK*L,outsidePRB,outsideSymbol];
    original = pdsch;
    [expected,data,dmrs,ptrs] = localDLNative(carrier,pdsch);
    actual = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(carrier,pdsch);
    expectedReserved = sort(unreservedData(1,:).');
    assert(isequal(sort(actual.Reserved.Indices1Based),expectedReserved), ...
        'Original BWP indices must use BWP stride, carrier offset and native all-layer union.');
    assert(~isequal(sort(unique(double(pdsch.ReservedRE(:))+1)),expectedReserved), ...
        'The fixture must distinguish the old carrier-stride interpretation.');
    assert(numel(expectedReserved)==2 && diff(expectedReserved)==carrierK*L);
    assert(~any(ismember(expectedReserved,data(:))) && ...
        ~any(ismember(expectedReserved,dmrs(:))) && ~any(ismember(expectedReserved,ptrs(:))));
    proof = actual.RateMatchProof;
    assert(isequal(proof.OriginalReservedRE0Based,double(pdsch.ReservedRE)) && ...
        proof.ReservedREIndexDomain=="bwp_resource_grid" && ...
        proof.MaterializedIndexDomain=="carrier_resource_grid" && ...
        proof.ReservationDomain.BWPSubcarrierCount==bwpK && ...
        proof.ReservationDomain.CarrierSubcarrierCount==carrierK && ...
        proof.ReservationDomain.CarrierRBOffset==6 && ...
        proof.NoOccupiedReservedRECollision && proof.ToolboxDataExcludesReservedRE && ...
        proof.ToolboxDMRSExcludesReservedRE && proof.ToolboxPTRSExcludesReservedRE);
    localAssertNative(carrier,actual,expected,'D');
    assert(isequal(pdsch,original));

    % A valid BWP reservation entirely outside this two-layer allocation
    % neither grows the allocation nor creates a zero-width layer expansion.
    pdsch.ReservedRE = [outsidePRB,outsideSymbol+bwpK*L];
    outsideOnly = pdsch;
    [expected,data,dmrs,ptrs] = localDLNative(carrier,pdsch);
    actual = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(carrier,pdsch);
    assert(isequal(size(actual.Reserved.Indices1Based),[0 1]) && ...
        isempty(actual.Reserved.Coordinates0Based) && ...
        isempty(actual.RateMatchProof.ReservedREKeys) && ...
        isequal(data,unreservedData), ...
        'All-outside BWP reservations must produce a canonical empty reservation, not alter data.');
    localAssertNative(carrier,actual,expected,'D');
    baseline = pdsch;
    baseline.ReservedRE = [];
    [~,~,baselineDMRS,baselinePTRS] = localDLNative(carrier,baseline);
    assert(isequal(dmrs,baselineDMRS) && isequal(ptrs,baselinePTRS) && ...
        isequal(pdsch,outsideOnly));
end
% Native PT-RS itself respects the same BWP reservation projection.
[carrier,pdsch] = localDLFixture(3);
ptrsBWP = double(nrPDSCHPTRSIndices(carrier,pdsch,'IndexOrientation','bwp'));
ptrsCarrier = double(nrPDSCHPTRSIndices(carrier,pdsch,'IndexOrientation','carrier'));
assert(~isempty(ptrsBWP));
pdsch.ReservedRE = ptrsBWP(1)-1;
[expected,~,~,ptrs] = localDLNative(carrier,pdsch);
actual = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(carrier,pdsch);
assert(isequal(actual.Reserved.Indices1Based,ptrsCarrier(1)) && ...
    ~ismember(ptrsCarrier(1),ptrs));
localAssertNative(carrier,actual,expected,'D');
end

function localReservationGuards()
[carrier,pdsch] = localDLFixture(3);
pdsch.NumLayers = 2;
pdsch.DMRS.DMRSPortSet = [0 1];
dmrsBWP = localBWPLinearIndices(carrier,pdsch,"PDSCH_DMRS");
% ReservedRE punctures data/PT-RS, NOT DM-RS. Preserve the existing physical
% collision guard, including a reservation authored on another input layer.
pdsch.ReservedRE = dmrsBWP(1,2)-1;
localThrows(@() sixgr.phy.frame.ChannelAllocationMaterializer. ...
    materializePDSCH(carrier,pdsch),'sixgr:phy:frame:PDSCHReservedRECollision');
pdsch.ReservedRE = [];
actual = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(carrier,pdsch);
bad = actual.Allocation;
bad.StartRB = 0;
bad.NumRB = 1;
localThrows(@() localValidate(carrier,bad,'D'),'sixgr:phy:frame:RECoordinatesOutsideAllocation');
end

function localPhysicalHopsAndVRBs()
[carrier,pdsch] = localDLFixture(3);
pdsch.PRBSet = 0:1;
pdsch.PRBSetType = 'VRB';
pdsch.VRBToPRBInterleaving = true;
pdsch.VRBBundleSize = 2;
pdsch.EnablePTRS = false;
[expected,data] = localDLNative(carrier,pdsch);
actual = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(carrier,pdsch);
localAssertNative(carrier,actual,expected,'D');
% Reserve an ORIGINAL native physical-PRB data RE after the VRB mapping.
bwpData = double(nrPDSCHIndices(carrier,pdsch,'IndexOrientation','bwp'));
pdsch.ReservedRE = bwpData(1)-1;
actual = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(carrier,pdsch);
[expected,~,~,~] = localDLNative(carrier,pdsch);
assert(isequal(actual.Reserved.Indices1Based,data(1)));
localAssertNative(carrier,actual,expected,'D');
for transform = [false true]
    [carrier,pusch] = localULFixture(3,transform);
    pusch.PRBSet = 0:3;
    pusch.FrequencyHopping = 'intraSlot';
    pusch.SecondHopStartPRB = 8;
    pusch.DMRS.DMRSAdditionalPosition = 1;
    [expected,~,~,~,~] = localULNative(carrier,pusch);
    actual = sixgr.phy.frame.ChannelAllocationMaterializer.materializePUSCH(carrier,pusch);
    assert(actual.Allocation.StartRB==6 && actual.Allocation.NumRB==12, ...
        'The envelope must cover both native hops without filling their RE gaps.');
    localAssertNative(carrier,actual,expected,'U');
end
end

function localSameSymbolSharing()
[carrier,pdsch] = localDLFixture(3);
pdsch.PRBSet = 0:1;
first = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(carrier,pdsch);
pdsch.PRBSet = 4:5;
second = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(carrier,pdsch);
state = localState(carrier,'D');
report = sixgr.phy.frame.ResourceAllocationValidator.validateSet( ...
    [first.Allocation second.Allocation],state,'GridNumRB',double(carrier.NSizeGrid));
assert(report.ActualValid && isempty(report.CollisionKeys), ...
    'Sharing symbols with disjoint physical REs must remain legal.');
report = sixgr.phy.frame.ResourceAllocationValidator.validateSet( ...
    [first.Allocation first.Allocation],state,'GridNumRB',double(carrier.NSizeGrid));
assert(~report.ActualValid && report.ReasonCode=="unreserved_re_collision");
end

function localCORESETOrigins()
carrier = nrCarrierConfig('NSizeGrid',24,'NStartGrid',5,'SubcarrierSpacing',30);
for variant = 1:3
    coreset = nrCORESETConfig('CORESETID',1,'FrequencyResources',1,'Duration',2);
    coreset.CCEREGMapping = 'interleaved';
    coreset.REGBundleSize = 2;
    coreset.InterleaverSize = 2;
    expectedOffset = 1; % next six-CRB boundary after CRB 11 is CRB 12
    if variant==2
        coreset.RBOffset = 3;
        coreset.CCEREGMapping = 'noninterleaved';
        expectedOffset = 3;
    elseif variant==3
        coreset.CORESETID = 0;
        coreset.RBOffset = 3; % native CORESET0 ignores this field
        expectedOffset = 0;
    end
    search = nrSearchSpaceConfig('CORESETID',coreset.CORESETID, ...
        'SearchSpaceID',1,'StartSymbolWithinSlot',0, ...
        'SlotPeriodAndOffset',[1 0],'Duration',1,'NumCandidates',[0 1 0 0 0]);
    pdcch = nrPDCCHConfig('NStartBWP',11,'NSizeBWP',12, ...
        'CORESET',coreset,'SearchSpace',search,'AggregationLevel',2, ...
        'AllocatedCandidate',1,'RNTI',1);
    original = pdcch;
    [data,~,dmrs] = nrPDCCHResources(carrier,pdcch,'IndexOrientation','carrier');
    expected = localCoordinates(carrier,unique(double([data(:);dmrs(:)])));
    actual = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDCCH(carrier,pdcch);
    localAssertNative(carrier,actual,expected,'D');
    monitor = actual.CORESETMonitoringOccasion;
    assert(isequal(monitor.RBSet,6+expectedOffset+(0:5)) && ...
        monitor.BitmapRBOffsetWithinBWP==expectedOffset && ...
        isequal(sortrows(monitor.Allocation.RECoordinates),sortrows(expected)) && ...
        size(expected,1)==2*6*12, ...
        'Two CCEs must occupy exactly twelve native REGs at the original bitmap anchor.');
    assert(isequal(pdcch,original));
end
end

function [carrier,pdsch] = localDLFixture(variant)
scs = [15 30 30 60 60];
carrier = nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',scs(variant));
pdsch = nrPDSCHConfig('PRBSet',[1 2 4 5],'EnablePTRS',true);
pdsch.PTRS.TimeDensity = 1;
pdsch.PTRS.FrequencyDensity = 2;
pdsch.DMRS.DMRSAdditionalPosition = 1;
if variant>=2, carrier.NStartGrid=5; end
if variant>=3
    pdsch.NStartBWP = 11;
    pdsch.NSizeBWP = 12;
end
if variant==5
    carrier.CyclicPrefix = 'extended';
    pdsch.SymbolAllocation = [0 12];
end
end

function [carrier,pusch] = localULFixture(variant,transform)
[carrier,pdsch] = localDLFixture(variant);
pusch = nrPUSCHConfig('PRBSet',0:5,'TransformPrecoding',transform,'EnablePTRS',true);
pusch.NStartBWP = pdsch.NStartBWP;
pusch.NSizeBWP = pdsch.NSizeBWP;
pusch.SymbolAllocation = pdsch.SymbolAllocation;
pusch.DMRS.DMRSAdditionalPosition = 1;
pusch.PTRS.TimeDensity = 1;
pusch.PTRS.FrequencyDensity = 2;
pusch.PTRS.NumPTRSSamples = 2;
pusch.PTRS.NumPTRSGroups = 2;
end

function [coordinates,data,dmrs,ptrs] = localDLNative(carrier,pdsch)
data = double(nrPDSCHIndices(carrier,pdsch,'IndexOrientation','carrier'));
dmrs = double(nrPDSCHDMRSIndices(carrier,pdsch,'IndexOrientation','carrier'));
ptrs = double(nrPDSCHPTRSIndices(carrier,pdsch,'IndexOrientation','carrier'));
coordinates = localCoordinates(carrier,unique([data(:);dmrs(:);ptrs(:)]));
end

function [coordinates,data,dmrs,ptrs,nativePTRS] = localULNative(carrier,pusch)
data = double(nrPUSCHIndices(carrier,pusch,'IndexOrientation','carrier'));
dmrs = double(nrPUSCHDMRSIndices(carrier,pusch,'IndexOrientation','carrier'));
nativePTRS = double(nrPUSCHPTRSIndices(carrier,pusch));
if pusch.TransformPrecoding
    ptrs = data(nativePTRS(:,1),:);
else
    ptrs = double(nrPUSCHPTRSIndices(carrier,pusch,'IndexOrientation','carrier'));
end
coordinates = localCoordinates(carrier,unique([data(:);dmrs(:);ptrs(:)]));
end

function coordinates = localCoordinates(carrier,indices)
K = 12*double(carrier.NSizeGrid);
L = double(carrier.SymbolsPerSlot);
P = max(1,ceil(max(indices(:))/(K*L)));
[k,l,p] = ind2sub([K L P],indices(:));
coordinates = [k-1,l-1,p-1];
end

function localAssertNative(carrier,actual,expected,direction)
assert(actual.Exact && ~actual.FallbackUsed && ...
    isequal(sortrows(actual.ActualCoordinates0Based),sortrows(expected)));
validated = localValidate(carrier,actual.Allocation,direction);
assert(validated.ActualValid && validated.OriginalUnchanged && ...
    isequal(sort(validated.Occupancy.REKey),sort(actual.ActualREKeys)), ...
    'Exact native occupancy must survive the canonical envelope and reservations unchanged.');
coords = actual.Allocation.RECoordinates;
assert(actual.Allocation.StartRB==floor(min(coords(:,1))/12) && ...
    actual.Allocation.StartRB+actual.Allocation.NumRB-1==floor(max(coords(:,1))/12));
end

function localAssertIndices(component,expected)
assert(isequal(sort(component.Indices1Based),sort(unique(expected(:)))));
end

function indices = localBWPLinearIndices(carrier,pdsch,kind)
% Use supported subscript APIs. R2026a appends its internal
% MultiColumnIndex=true after caller options; its generic orientation
% adapter treats a noncolumn linear matrix as subscript coordinates.
% Do not use that ambiguous matrix to manufacture this fixture's ReservedRE.
if kind=="PDSCH_DATA"
    native = @nrPDSCHIndices;
else
    assert(kind=="PDSCH_DMRS");
    native = @nrPDSCHDMRSIndices;
end
bwp = double(native(carrier,pdsch,'IndexStyle','subscript', ...
    'IndexBase','0based','IndexOrientation','bwp'));
physical = double(native(carrier,pdsch,'IndexStyle','subscript', ...
    'IndexBase','0based','IndexOrientation','carrier'));
K = 12*double(carrier.NSizeGrid);
bwpK = 12*double(pdsch.NSizeBWP);
L = double(carrier.SymbolsPerSlot);
offset = 12*(double(pdsch.NStartBWP)-double(carrier.NStartGrid));
assert(size(bwp,2)==3 && ~isempty(bwp) && ...
    isequal(physical(:,2:3),bwp(:,2:3)) && ...
    isequal(physical(:,1),bwp(:,1)+offset) && ...
    all(bwp(:,1)>=0 & bwp(:,1)<bwpK) && ...
    all(bwp(:,2)>=0 & bwp(:,2)<L) && ...
    all(bwp(:,3)>=0 & bwp(:,3)<pdsch.NumLayers), ...
    'Native BWP/carrier subscript tuples must differ only by the original BWP frequency offset.');
physicalLinear = physical(:,1)+K*physical(:,2)+K*L*physical(:,3)+1;
originalLinear = double(native(carrier,pdsch,'IndexOrientation','carrier'));
assert(isequal(physicalLinear,originalLinear(:)), ...
    'Native carrier subscripts must reconstruct the original ordered native linear indices.');
bwpLinear = bwp(:,1)+bwpK*bwp(:,2)+bwpK*L*bwp(:,3)+1;
indices = reshape(bwpLinear,[],pdsch.NumLayers);
row = find(bwp(:,3)==1,1);
assert(~isempty(row),'This regression must retain an original second-layer tuple.');
fprintf('BWP_NATIVE_DOMAIN %s carrier=%s BWP=%s carrierLinear=%g BWPLinear=%g\n', ...
    kind,mat2str(physical(row,:)),mat2str(bwp(row,:)), ...
    physicalLinear(row),bwpLinear(row));
end

function result = localValidate(carrier,allocation,direction)
result = sixgr.phy.frame.ResourceAllocationValidator.validate( ...
    allocation,localState(carrier,direction),'GridNumRB',double(carrier.NSizeGrid));
end

function state = localState(carrier,direction)
L = double(carrier.SymbolsPerSlot);
state = struct('DuplexMode',"TDD",'CommonDirection',repmat(direction,1,L), ...
    'DedicatedDirection',strings(1,L),'SymbolDirection',repmat(direction,1,L), ...
    'ResolvedDirection',repmat(string(direction),1,L), ...
    'ResolutionSource',strings(1,L),'AllocationOwner',strings(1,L));
end

function localThrows(fcn,expected)
try
    fcn();
catch cause
    assert(strcmp(cause.identifier,expected),'testChannelAllocationBWPAuthority:WrongGuard', ...
        'Expected %s, got %s: %s',expected,cause.identifier,cause.message);
    return;
end
error('testChannelAllocationBWPAuthority:MissingGuard','Expected %s.',expected);
end
