function ok = testPUSCHPTRSPhysicalAllocation()
%TESTPUSCHPTRSPHYSICALALLOCATION Native PT-RS domains and physical RE union.
% Declared component fixtures only: <=24 carrier PRBs, no channel, receiver,
% received grant, or campaign. DFT PT-RS is inserted BEFORE the transform;
% its projected carrier addresses are not independent frequency pilots.
% TS 38.211 V18.8.0 6.3.1.4 and 6.4.1.2.2.2; R2026a nrPUSCH exposes
% PTRS = transformedPUSCH(relativePTRSPositions(:,1),:).

setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
savedRNG = rng;
cleanup = onCleanup(@() rng(savedRNG)); %#ok<NASGU>
rng(241924,'twister');
groups = {@() localNativeMaps(false), @() localNativeMaps(true), ...
    @localNativeTransformedSymbols, @() localExecutedOccupancy(false), ...
    @() localExecutedOccupancy(true), @localPlannedOccupancy, ...
    @localCollisionGeometry};
names = ["native_CP_maps","native_DFT_maps","native_transformed_symbols", ...
    "executed_CP_occupancy","executed_DFT_occupancy", ...
    "planned_physical_union","SRS_collision_geometry"];
failures = strings(0,1);
for k = 1:numel(groups)
    try
        groups{k}();
        fprintf('[PASS] PUSCHPTRSPhysicalAllocation %s\n',names(k));
    catch cause
        failures(end+1,1) = names(k)+": "+string(cause.identifier)+ ...
            " "+string(cause.message); %#ok<AGROW>
        fprintf(2,'[FAIL] PUSCHPTRSPhysicalAllocation %s\n',failures(end));
    end
end
assert(isempty(failures),'testPUSCHPTRSPhysicalAllocation:Failed', ...
    '%d/%d groups failed:\n%s',numel(failures),numel(groups), ...
    char(strjoin(failures,newline)));
ok = true;
end

function localNativeMaps(transform)
for variant = 1:4
    [carrier,pusch] = localNativeFixture(transform,variant);
    originalCarrier = carrier;
    originalPUSCH = pusch;
    [data,~,expectedPTRS,relativePTRS] = localNativeIndices(carrier,pusch);
    materialized = sixgr.phy.frame.ChannelAllocationMaterializer. ...
        materializePUSCH(carrier,pusch,'AbsoluteSlot',double(carrier.NSlot));
    assert(isequal(sort(materialized.PTRS.Indices1Based(:)), ...
        sort(expectedPTRS(:))), ...
        'testPUSCHPTRSPhysicalAllocation:PTRSCarrierDomain', ...
        'transform=%d variant=%d: PT-RS must match carrier addresses, not allocation-relative rows.', ...
        transform,variant);
    assert(islogical(materialized.TransformPrecoding) && ...
        isequal(materialized.TransformPrecoding,transform) && ...
        isequal(materialized.Data.GridIndices1Based,data) && ...
        isequal(materialized.PTRS.GridIndices1Based,expectedPTRS) && ...
        isequal(materialized.PTRS.EmbeddedInData,transform) && ...
        isequal(materialized.PTRS.IndependentPhysicalOccupancy,~transform));
    if transform
        assert(isequal(materialized.PTRS.NativeIndices1Based,relativePTRS) && ...
            materialized.PTRS.NativeIndexDomain=="pre_transform_pusch_allocation_relative" && ...
            materialized.PTRS.IndexDomain=="carrier_grid_projected_allocation_rows" && ...
            materialized.Data.Label=="PUSCH_TRANSFORMED_DATA_AND_PTRS");
        localThrows(@() sixgr.phy.frame.ChannelAllocationMaterializer. ...
            materializeReferenceSignal(carrier,'PUSCH_PTRS',pusch), ...
            'sixgr:phy:frame:EmbeddedPUSCHPTRSRequiresCombinedAllocation');
    else
        assert(isequal(materialized.PTRS.NativeIndices1Based,expectedPTRS) && ...
            materialized.PTRS.NativeIndexDomain=="carrier_resource_grid" && ...
            materialized.PTRS.IndexDomain=="carrier_resource_grid" && ...
            materialized.Data.Label=="PUSCH_DATA");
        isolated=sixgr.phy.frame.ChannelAllocationMaterializer. ...
            materializeReferenceSignal(carrier,'PUSCH_PTRS',pusch);
        assert(isequal(sort(isolated.Resources.Indices1Based),sort(expectedPTRS(:))));
    end
    adapter = sixgr.phy.resource.puschPTRSGridIndices(carrier,pusch);
    assert(isequal(double(adapter),expectedPTRS), ...
        'testPUSCHPTRSPhysicalAllocation:AdapterOrder', ...
        'The existing adapter must preserve native row and physical-port order.');
    zeroBased = sixgr.phy.resource.puschPTRSGridIndices(carrier,pusch,'IndexBase','0based');
    assert(isequal(double(zeroBased),expectedPTRS-1));
    localAssertNativeUnion(carrier,pusch,materialized,data,expectedPTRS);
    assert(isequal(carrier,originalCarrier) && isequal(pusch,originalPUSCH), ...
        'Materialization must not alter the original native objects.');
end
% Explicitly disabled PT-RS is not a new pilot allocation in either mode.
pusch.EnablePTRS=false;
materialized=sixgr.phy.frame.ChannelAllocationMaterializer.materializePUSCH(carrier,pusch);
data=double(nrPUSCHIndices(carrier,pusch,'IndexOrientation','carrier'));
dmrs=double(nrPUSCHDMRSIndices(carrier,pusch,'IndexOrientation','carrier'));
assert(isequal(materialized.TransformPrecoding,transform) && ...
    isempty(materialized.PTRS.NativeIndices1Based) && ...
    isempty(materialized.PTRS.GridIndices1Based) && ...
    ~materialized.PTRS.EmbeddedInData && materialized.Data.Label=="PUSCH_DATA" && ...
    isequal(sortrows(materialized.ActualCoordinates0Based), ...
        sortrows(localCoordinates(carrier,unique([data(:);dmrs(:)])))));
end

function localNativeTransformedSymbols()
[carrier,pusch] = localNativeFixture(true,2);
[data,info,projected,relative] = localNativeIndices(carrier,pusch);
% Alternating actual codeword bits avoid a random test oracle.
cw = int8(mod((0:double(info.G)-1).',2));
[symbols,extraPTRS] = nrPUSCH(carrier,pusch,cw);
assert(isequal(extraPTRS,symbols(double(relative(:,1)),:)), ...
    'testPUSCHPTRSPhysicalAllocation:NativeSymbolDomain', ...
    'Native additional PT-RS output must be selected transformed symbols.');
grid = nrResourceGrid(carrier,size(symbols,2));
grid(data) = symbols;
before = grid;
grid(projected) = extraPTRS;
assert(isequal(grid,before), ...
    'testPUSCHPTRSPhysicalAllocation:DuplicatePhysicalMapping', ...
    'Rewriting the selected transformed values must add no physical RE or energy.');
assert(numel(unique([data(:);projected(:)]))==numel(data), ...
    'Projected DFT PT-RS positions are a subset of the transformed allocation.');
assert(~isequal(sort(double(relative(:))),sort(projected(:))), ...
    'The offset fixture must distinguish raw relative positions from carrier addresses.');
materialized = sixgr.phy.frame.ChannelAllocationMaterializer.materializePUSCH(carrier,pusch);
localAssertNativeUnion(carrier,pusch,materialized,data,projected);
end

function localExecutedOccupancy(transform)
cfg = localTXConfig(transform);
[tx,~] = sixgr.phy.ul.PUSCH_Tx(cfg,'CompactOutput',false);
assert(tx.PUSCH.EnablePTRS && logical(tx.PUSCH.TransformPrecoding)==transform && ...
    ~isempty(tx.PTRSNativeIndices), ...
    'The actual transmitter must execute the explicitly enabled PT-RS branch.');
original = tx;
observed = sixgr.truth.buildObservedREAllocation(tx, ...
    'Direction','UL','AbsoluteSlot',0,'AllocationID','declared_ptrs_component');
coordinates = localExpandRows(observed);
assert(islogical(observed.transform_precoded) && all(observed.transform_precoded==transform));
[k,l,p] = ind2sub(size(tx.Grid),find(tx.Grid~=0));
expected = sortrows([k-1,l-1,p-1]);
assert(isequal(sortrows(coordinates),expected) && ...
    size(coordinates,1)==size(unique(coordinates,'rows'),1) && ...
    sum(observed.re_count)==nnz(tx.Grid), ...
    'testPUSCHPTRSPhysicalAllocation:ObservedPhysicalUnion', ...
    'Each nonzero executed physical grid cell must be published exactly once.');
if transform
    assert(~any(string(observed.component)=="PUSCH_PTRS"), ...
        'testPUSCHPTRSPhysicalAllocation:FalseIsolatedPTRS', ...
        'DFT-spread PT-RS must not be exported as isolated frequency-domain pilot REs.');
    assert(any(string(observed.component)=="PUSCH_TRANSFORMED_DATA_AND_PTRS"));
else
    assert(any(string(observed.component)=="PUSCH_PTRS"));
end
compact = sixgr.truth.resourceIntervalsFromObservedRE(observed,tx.Carrier);
nativeCompact = sixgr.truth.executedResourceIntervals(tx.Grid,0);
assert(compact.ExecutedResourceIntervalsJSON==nativeCompact.ExecutedResourceIntervalsJSON);
assert(isequaln(tx,original),'Occupancy auditing must not alter actual TX evidence.');

bad = tx;
bad.PTRSNativeIndices(1) = bad.PTRSNativeIndices(1)+1;
localThrows(@() sixgr.truth.buildObservedREAllocation(bad,'AbsoluteSlot',0), ...
    'sixgr:truth:ExecutedREIndexMismatch');
bad = tx;
bad.PTRSNativeIndices([1 2],:) = bad.PTRSNativeIndices([2 1],:);
localThrows(@() sixgr.truth.buildObservedREAllocation(bad,'AbsoluteSlot',0), ...
    'sixgr:truth:ExecutedREIndexMismatch');
bad = tx;
bad.PTRSWaveformIndices([1 2],:) = bad.PTRSWaveformIndices([2 1],:);
localThrows(@() sixgr.truth.buildObservedREAllocation(bad,'AbsoluteSlot',0), ...
    'sixgr:truth:ExecutedREIndexMismatch');
bad = tx;
bad.PTRSWaveformSymbols(1) = bad.PTRSWaveformSymbols(1)+0.125;
localThrows(@() sixgr.truth.buildObservedREAllocation(bad,'AbsoluteSlot',0), ...
    'sixgr:truth:ExecutedREGridMismatch');
end

function localPlannedOccupancy()
for transform = [false true]
    base = localTXConfig(transform);
    % Small explicit FDD component resource pool, not a scheduler grant.
    % The carrier is the standard 10-MHz/30-kHz 24-RB grid. No inherited
    % SSB/PRACH or alternate bandwidth authority is imported into this test.
    cfg = struct('frequency',struct('center_frequency_hz',2.14e9, ...
        'bandwidth_hz',10e6,'range_name','FR1','duplex_mode','FDD', ...
        'n_size_grid',24,'n_start_grid',0), ...
        'frame',struct('scs_khz',30,'cp_type','normal'), ...
        'run',struct('totalSlots',1), ...
        'outputs',struct('plannedAllocationEncoding','expanded_per_slot'));
    cfg.phy.carrier = base.phy.carrier;
    cfg.phy.pusch = base.phy.pusch;
    cfg.phy.duplex = struct('mode','FDD');
    carrier = sixgr.phy.grid.makeCarrier(cfg);
    [~,~,pusch] = sixgr.phy.grid.allocPUSCHTransport(carrier,cfg);
    [data,~,ptrs] = localNativeIndices(carrier,pusch);
    dmrs = double(nrPUSCHDMRSIndices(carrier,pusch));
    expected = localCoordinates(carrier,unique([data(:);dmrs(:);ptrs(:)]));
    [planned,checks] = sixgr.truth.buildPlannedREAllocation(cfg, ...
        'TargetChannels','PUSCH','ReusePeriodicCoordinateTemplates',false);
    check = checks(checks.feature=="PUSCH",:);
    assert(height(check)==1 && check.resolved && check.status=="PASS", ...
        'testPUSCHPTRSPhysicalAllocation:PlannedResolution', ...
        'PUSCH planning failed: %s',char(strjoin(string(check.detail),'; ')));
    rows = planned(planned.channel=="PUSCH",:);
    assert(islogical(rows.transform_precoded) && all(rows.transform_precoded==transform));
    actual = localExpandRows(rows);
    assert(isequal(sortrows(actual),sortrows(expected)) && ...
        size(actual,1)==size(unique(actual,'rows'),1) && ...
        sum(rows.re_count)==size(expected,1), ...
        'testPUSCHPTRSPhysicalAllocation:PlannedPhysicalUnion', ...
        'Planned occupancy must count the carrier-grid union, not duplicate embedded PT-RS.');
    if transform
        assert(~any(rows.component=="PUSCH_PTRS") && ...
            any(rows.component=="PUSCH_TRANSFORMED_DATA_AND_PTRS"));
    else
        assert(any(rows.component=="PUSCH_PTRS") && any(rows.component=="PUSCH_DATA"));
    end
end
end

function localCollisionGeometry()
carrier = nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
pusch = nrPUSCHConfig('TransformPrecoding',true,'EnablePTRS',true);
pusch.PRBSet = 6:23;
pusch.DMRS.DMRSPortSet = 0;
pusch.PTRS.NumPTRSSamples = 2;
pusch.PTRS.NumPTRSGroups = 2;
srs = nrSRSConfig('CSRS',0,'BSRS',0,'BHop',0, ...
    'NumSRSPorts',1,'NumSRSSymbols',1,'SymbolStart',9, ...
    'KTC',2,'KBarTC',0,'FrequencyStart',1,'NRRC',0,'SRSPeriod','on');
nativeSRS = localCoordinates(carrier,double(nrSRSIndices(carrier,srs)));
materializedSRS = sixgr.phy.frame.ChannelAllocationMaterializer. ...
    materializeReferenceSignal(carrier,'SRS',srs);
assert(isequal(sortrows(nativeSRS),sortrows(materializedSRS.ActualCoordinates0Based)));
for overlap = [false true]
    if overlap, pusch.PRBSet=0:17; end
    [data,~,ptrs,relative] = localNativeIndices(carrier,pusch);
    dmrs = double(nrPUSCHDMRSIndices(carrier,pusch));
    native = localCoordinates(carrier,unique([data(:);dmrs(:);ptrs(:)]));
    expected = intersect(native(:,1:2),nativeSRS(:,1:2),'rows');
    assert((~isempty(expected))==overlap,'Declared SRS clear/overlap fixture is invalid.');
    if ~overlap
        wrong = localCoordinates(carrier,double(relative(:)));
        assert(~isempty(intersect(wrong(:,1:2),nativeSRS(:,1:2),'rows')), ...
            'The regression must expose a phantom overlap from misread relative positions.');
    end
    materialized = sixgr.phy.frame.ChannelAllocationMaterializer.materializePUSCH(carrier,pusch);
    actual = intersect(materialized.ActualCoordinates0Based(:,1:2), ...
        materializedSRS.ActualCoordinates0Based(:,1:2),'rows');
    assert(isequal(actual,expected), ...
        'testPUSCHPTRSPhysicalAllocation:PhantomSRSCollision', ...
        'Materialized shared time/frequency overlap must equal the independent native union.');
end
end

function [carrier,pusch] = localNativeFixture(transform,variant)
carrier = nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
pusch = nrPUSCHConfig('TransformPrecoding',transform,'EnablePTRS',true);
pusch.PRBSet = 6:11;
pusch.DMRS.DMRSPortSet = 0;
pusch.PTRS.TimeDensity = 1;
pusch.PTRS.FrequencyDensity = 2;
pusch.PTRS.REOffset = '00';
pusch.PTRS.NumPTRSSamples = 2;
pusch.PTRS.NumPTRSGroups = 2;
if variant==1
    carrier.SubcarrierSpacing = 15;
elseif variant==2
    carrier.NStartGrid = 5;
    pusch.NStartBWP = 7;
    pusch.NSizeBWP = 18;
    pusch.PRBSet = 3:8;
    pusch.TransmissionScheme = 'codebook';
    pusch.NumAntennaPorts = 2;
    pusch.TPMI = 0;
elseif variant==3
    pusch.PRBSet = 0:5;
    pusch.FrequencyHopping = 'intraSlot';
    pusch.SecondHopStartPRB = 12;
    pusch.DMRS.DMRSAdditionalPosition = 1;
elseif variant==4
    pusch.MappingType = 'B';
    pusch.SymbolAllocation = [4 8];
end
end

function [data,info,ptrs,relative] = localNativeIndices(carrier,pusch)
[data,info] = nrPUSCHIndices(carrier,pusch,'IndexOrientation','carrier');
data = double(data);
relative = [];
if pusch.TransformPrecoding
    relative = double(nrPUSCHPTRSIndices(carrier,pusch));
    assert(~isempty(relative));
    ptrs = data(relative(:,1),:);
else
    ptrs = double(nrPUSCHPTRSIndices(carrier,pusch,'IndexOrientation','carrier'));
end
end

function localAssertNativeUnion(carrier,pusch,materialized,data,ptrs)
dmrs = double(nrPUSCHDMRSIndices(carrier,pusch,'IndexOrientation','carrier'));
expected = localCoordinates(carrier,unique([data(:);dmrs(:);ptrs(:)]));
assert(isequal(sortrows(materialized.ActualCoordinates0Based),sortrows(expected)), ...
    'testPUSCHPTRSPhysicalAllocation:PhysicalUnion', ...
    'Materializer must not create phantom physical REs from allocation-relative positions.');
if pusch.TransformPrecoding
    assert(all(ismember(ptrs(:),data(:))) && ...
        size(expected,1)==numel(unique([data(:);dmrs(:)])));
end
end

function coords = localCoordinates(carrier,indices)
indices = unique(double(indices(:)));
shape = [12*double(carrier.NSizeGrid),double(carrier.SymbolsPerSlot), ...
    max(1,ceil(max(indices)/(12*double(carrier.NSizeGrid)*double(carrier.SymbolsPerSlot))))];
[k,l,p] = ind2sub(shape,indices);
coords = [k-1,l-1,p-1];
end

function coords = localExpandRows(rows)
coords = zeros(0,3);
for k = 1:height(rows)
    sc = double(rows.subcarrier_start(k))+(0:double(rows.subcarrier_count(k))-1).';
    coords = [coords;sc,repmat(double(rows.symbol_index(k)),numel(sc),1), ...
        repmat(double(rows.port_index(k)),numel(sc),1)]; %#ok<AGROW>
end
end

function cfg = localTXConfig(transform)
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictNoiseVarianceRequired = false;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = 'AWGN';
cfg.channel.awgnOnly = true;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.antenna.ue.numElements = 1;
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.carrier.NStartGrid = 0;
cfg.phy.carrier.NSlot = 0;
cfg.phy.carrier.NFrame = 0;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.CyclicPrefix = 'normal';
cfg.phy.pusch.prbSet = 6:11;
cfg.phy.pusch.symbolAllocation = [0 10];
cfg.phy.pusch.mappingType = 'A';
cfg.phy.pusch.enable = true;
cfg.phy.pusch.modulation = 'QPSK';
cfg.phy.pusch.codeRate = 0.30;
cfg.phy.pusch.mcsIndex = 4;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.numAntennaPorts = 1;
cfg.phy.pusch.numPorts = 1;
cfg.phy.pusch.dmrs.portSet = 0;
cfg.phy.pusch.dmrs.DMRSPortSet = 0;
cfg.phy.pusch.dmrs.configurationType = 1;
cfg.phy.pusch.dmrs.maxLength = 1;
cfg.phy.pusch.dmrs.additionalPositions = 0;
cfg.phy.pusch.transmissionScheme = 'nonCodebook';
cfg.phy.pusch.transformPrecoding = logical(transform);
cfg.phy.pusch.enablePTRS = true;
cfg.phy.pusch.ptrs = struct('timeDensity',1,'frequencyDensity',2, ...
    'reOffset','00','numPTRSSamples',2,'numPTRSGroups',2,'portSet',0);
end

function localThrows(fn,expected)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,expected), ...
        'testPUSCHPTRSPhysicalAllocation:WrongGuard', ...
        'Expected %s, got %s: %s',expected,cause.identifier,cause.message);
    return;
end
error('testPUSCHPTRSPhysicalAllocation:MissingGuard','Expected %s.',expected);
end
