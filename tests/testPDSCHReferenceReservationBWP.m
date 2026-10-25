function ok = testPDSCHReferenceReservationBWP()
%TESTPDSCHREFERENCERESERVATIONBWP Real reservation owner, native RS operands.
% <=24 carrier PRBs, no RF/channel/receiver or scheduler/DCI claim. Shifted
% BWP cases call the SAME helper used by allocREsPDSCH's production CSI-RS,
% TRS and CSI-IM generators. The current config factory's full-carrier BWP
% route is exercised separately; this test does not add YAML BWP wiring.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
before = rng;
groups = {@localCSIRS,@localTRS,@localCSIIM,@localCollisionGuards, ...
    @localVRBAndReservedPRB,@localPublicConfigRoute};
names = ["native_CSIRS","native_TRS_pair","configured_CSIIM", ...
    "carrier_domain_guards","VRB_and_reserved_PRB","public_config_route"];
failures = strings(0,1);
for k = 1:numel(groups)
    try
        groups{k}();
        fprintf('[PASS] PDSCHReferenceReservationBWP %s\n',names(k));
    catch cause
        failures(end+1,1) = names(k)+": "+string(cause.identifier)+ ...
            " "+string(cause.message); %#ok<AGROW>
        fprintf(2,'[FAIL] PDSCHReferenceReservationBWP %s\n',failures(end));
    end
end
assert(isequal(before,rng),'Reservation inspection must not consume RNG.');
assert(isempty(failures),'testPDSCHReferenceReservationBWP:Failed', ...
    '%d/%d groups failed:\n%s',numel(failures),numel(groups),char(strjoin(failures,newline)));
ok = true;
end

function localCSIRS()
[carrier,pdsch] = localFixture();
rs = nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',4, ...
    'Density','one','SymbolLocations',3,'SubcarrierLocations',0,'NumRB',24,'RBOffset',0);
indices = nrCSIRSIndices(carrier,rs,'IndexBase','0based');
assert(rs.NumCSIRSPorts==4 && ~isempty(indices));
localPositive(carrier,pdsch,indices,'CSI-RS', ...
    'sixgr:phy:grid:allocREsPDSCH:CSIRSDMRSCollision');
end

function localTRS()
[carrier,pdsch] = localFixture();
indices = zeros(0,1);
for symbol = [4 8]
    rs = nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',1, ...
        'Density','three','SymbolLocations',symbol,'SubcarrierLocations',0, ...
        'NumRB',24,'RBOffset',0);
    native = nrCSIRSIndices(carrier,rs,'IndexBase','0based');
    indices = [indices;double(native(:))]; %#ok<AGROW>
end
localPositive(carrier,pdsch,indices,'TRS', ...
    'sixgr:phy:grid:allocREsPDSCH:TRSDMRSCollision');
end

function localCSIIM()
[carrier,pdsch] = localFixture();
cfg = struct('phy',struct('csiim',localIMConfig(6)));
plan = sixgr.phy.refsig.csiIMResource(carrier,cfg);
assert(plan.Scheduled && plan.NumRE>0);
localPositive(carrier,pdsch,plan.PhysicalIndices1Based-1,'CSI-IM', ...
    'sixgr:phy:csiim:DMRSCollision',true);
end

function localPositive(carrier,pdsch,indices,signal,dmrsError,rejectExisting)
if nargin<6, rejectExisting=false; end
original = pdsch;
expectedCarrier = localExpectedCarrier(carrier,pdsch,indices);
assert(~isempty(expectedCarrier));
expectedBWP = localToBWP(carrier,pdsch,expectedCarrier);
assert(~isequal(expectedCarrier,expectedBWP),'The shifted/narrow BWP fixture must distinguish index domains.');
[actual,receipt] = sixgr.phy.grid.reservePDSCHReferenceRE( ...
    carrier,pdsch,indices,'SignalName',signal,'DMRSCollisionIdentifier',dmrsError, ...
    'RejectExistingReservations',rejectExisting,'RejectPTRS',rejectExisting);
assert(isequal(double(actual.ReservedRE(:)),expectedBWP) && ...
    isequal(receipt.CarrierIndices0Based,expectedCarrier) && ...
    isequal(receipt.BWPIndices0Based,expectedBWP));
localCompareNative(carrier,original,actual,expectedCarrier);
assert(isequal(pdsch,original),'The helper must not mutate its caller-owned native object.');
end

function localCollisionGuards()
[carrier,pdsch] = localFixture();
dmrs = nrPDSCHDMRSIndices(carrier,pdsch,'IndexBase','0based','IndexOrientation','carrier');
for id = ["sixgr:phy:grid:allocREsPDSCH:CSIRSDMRSCollision", ...
        "sixgr:phy:grid:allocREsPDSCH:TRSDMRSCollision","sixgr:phy:csiim:DMRSCollision"]
    localThrows(@() sixgr.phy.grid.reservePDSCHReferenceRE(carrier,pdsch,dmrs(1), ...
        'DMRSCollisionIdentifier',id),char(id));
end
data = double(nrPDSCHIndices(carrier,pdsch,'IndexBase','0based','IndexOrientation','carrier'));
K = 12*double(carrier.NSizeGrid);
L = double(carrier.SymbolsPerSlot);
target = mod(data(1),K*L);
targetBWP = localToBWP(carrier,pdsch,target);
% Existing input reservation deliberately uses layer 1 rather than layer 0.
pdsch.ReservedRE = targetBWP + 12*double(pdsch.NSizeBWP)*L;
localThrows(@() sixgr.phy.grid.reservePDSCHReferenceRE(carrier,pdsch,target, ...
    'RejectExistingReservations',true, ...
    'ExistingCollisionIdentifier','sixgr:phy:csiim:ReferenceCollision'), ...
    'sixgr:phy:csiim:ReferenceCollision');
pdsch.ReservedRE = [];
pdsch.EnablePTRS = true;
pdsch.PTRS.TimeDensity = 1;
pdsch.PTRS.FrequencyDensity = 2;
ptrs = nrPDSCHPTRSIndices(carrier,pdsch,'IndexBase','0based','IndexOrientation','carrier');
assert(~isempty(ptrs));
localThrows(@() sixgr.phy.grid.reservePDSCHReferenceRE(carrier,pdsch,ptrs(1), ...
    'RejectPTRS',true,'PTRSCollisionIdentifier','sixgr:phy:csiim:PTRSCollision'), ...
    'sixgr:phy:csiim:PTRSCollision');
% CSI-RS/TRS use their pre-existing permitted exact PT-RS puncturing policy.
[reserved,receipt] = sixgr.phy.grid.reservePDSCHReferenceRE(carrier,pdsch,ptrs(1));
after = nrPDSCHPTRSIndices(carrier,reserved,'IndexBase','0based','IndexOrientation','carrier');
assert(~ismember(ptrs(1),after) && numel(receipt.CarrierIndices0Based)==1);
end

function localVRBAndReservedPRB()
[carrier,pdsch] = localFixture();
pdsch.NumLayers = 1;
pdsch.DMRS.DMRSPortSet = 0;
pdsch.PRBSet = 0:3;
pdsch.PRBSetType = 'VRB';
pdsch.VRBToPRBInterleaving = true;
pdsch.VRBBundleSize = 2;
[~,info] = nrPDSCHIndices(carrier,pdsch);
physical = double(info.PRBSet);
assert(~isequal(sort(physical),sort(pdsch.PRBSet)), ...
    'The declared VRB fixture must exercise a nonidentity physical map.');
pattern = nrPDSCHReservedConfig('PRBSet',physical(1),'SymbolSet',4,'Period',1);
pdsch.ReservedPRB = {pattern};
K = 12*double(carrier.NSizeGrid);
offset = 12*(double(pdsch.NStartBWP)-double(carrier.NStartGrid));
% Exact native physical PRB on each side of the whole-PRB exclusion.
reservedHole = offset+12*physical(1)+K*4;
active = offset+12*physical(end)+K*4;
[actual,receipt] = sixgr.phy.grid.reservePDSCHReferenceRE( ...
    carrier,pdsch,[reservedHole active]);
assert(isequal(receipt.CarrierIndices0Based,active) && ...
    isequal(double(actual.ReservedRE(:)),localToBWP(carrier,pdsch,active)), ...
    'Reference support must follow the physical VRB map and not revive ReservedPRB holes.');
localCompareNative(carrier,pdsch,actual,active);
empty = sixgr.phy.grid.reservePDSCHReferenceRE(carrier,pdsch,zeros(0,1));
assert(isequal(empty,pdsch));
end

function localPublicConfigRoute()
% Actual existing config route, no new BWP binding or private-source copy.
cfg = struct();
cfg.phy.pdsch = struct('prbSet',0:5,'symbolAllocation',[0 14], ...
    'mappingType','A','modulation','QPSK','numLayers',1, ...
    'enablePTRS',false,'dmrs',struct('portSet',0,'additionalPositions',0));
cfg.phy.csirs = struct('enable',true,'period_slots',4,'offset_slots',0, ...
    'nPorts',4,'numResources',1,'resourceID',0,'rowNumber',4, ...
    'symbolLocations',3,'subcarrierLocations',0,'rbOffset',0,'numRB',24);
cfg.phy.csiim = localIMConfig(6);
carrier = nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
original = cfg;
[data,info,pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier,cfg);
[rs,~] = sixgr.phy.refsig.csirs(carrier,cfg,'IndexBase','0based');
im = sixgr.phy.refsig.csiIMResource(carrier,cfg);
raw = pdsch;
raw.ReservedRE = [];
expected = localExpectedCarrier(carrier,raw,[double(rs(:));im.PhysicalIndices1Based-1]);
assert(isempty(pdsch.NStartBWP) && isempty(pdsch.NSizeBWP) && ...
    isequal(double(pdsch.ReservedRE(:)),expected) && info.CSIIMReservation.Scheduled);
assert(isequal(double(data),double(nrPDSCHIndices(carrier,pdsch))));
localCompareNative(carrier,raw,pdsch,expected);
assert(isequaln(cfg,original));
% Original shared generators retain their exact collision errors.
bad = cfg;
bad.phy.csirs.symbolLocations = 2;
localThrows(@() sixgr.phy.grid.allocREsPDSCH(carrier,bad), ...
    'sixgr:phy:grid:allocREsPDSCH:CSIRSDMRSCollision');
bad = cfg;
bad.phy.csiim.symbol = 3;
bad.phy.csiim.subcarrier = 0;
localThrows(@() sixgr.phy.grid.allocREsPDSCH(carrier,bad),'sixgr:phy:csiim:ReferenceCollision');
end

function [carrier,pdsch] = localFixture()
carrier = nrCarrierConfig('NSizeGrid',24,'NStartGrid',5,'SubcarrierSpacing',30);
pdsch = nrPDSCHConfig('NStartBWP',11,'NSizeBWP',12,'PRBSet',[0 1 4 5], ...
    'SymbolAllocation',[0 14],'NumLayers',2,'EnablePTRS',false);
pdsch.DMRS.DMRSPortSet = [0 1];
pdsch.DMRS.DMRSAdditionalPosition = 0;
end

function cfg = localIMConfig(symbol)
cfg = struct('enabled',true,'resource_id',2,'pattern',1,'subcarrier',4, ...
    'symbol',symbol,'starting_rb',0,'num_rbs',24,'period_slots',4,'offset_slots',0);
end

function expected = localExpectedCarrier(carrier,pdsch,indices)
% Independent explicit physical PRB rectangle from the NATIVE mapped set;
% ordinary positive fixtures have no ReservedPRB holes (tested separately).
K = 12*double(carrier.NSizeGrid);
L = double(carrier.SymbolsPerSlot);
[~,info] = nrPDSCHIndices(carrier,pdsch);
startBWP = pdsch.NStartBWP;
if isempty(startBWP), startBWP=carrier.NStartGrid; end
prbs = double(info.PRBSet)+double(startBWP)-double(carrier.NStartGrid);
base = unique(mod(double(indices(:)),K*L));
expected = base(ismember(floor(mod(base,K)/12),prbs) & ...
    floor(base/K)>=pdsch.SymbolAllocation(1) & floor(base/K)<sum(pdsch.SymbolAllocation));
end

function bwp = localToBWP(carrier,pdsch,carrierBase)
startBWP = pdsch.NStartBWP;
if isempty(startBWP), startBWP=carrier.NStartGrid; end
sizeBWP = pdsch.NSizeBWP;
if isempty(sizeBWP), sizeBWP=carrier.NSizeGrid; end
K = 12*double(carrier.NSizeGrid);
bwp = mod(carrierBase,K)-12*(double(startBWP)-double(carrier.NStartGrid)) + ...
    12*double(sizeBWP)*floor(carrierBase/K);
bwp = bwp(:);
end

function localCompareNative(carrier,before,after,expectedCarrier)
K = 12*double(carrier.NSizeGrid);
L = double(carrier.SymbolsPerSlot);
oldData = double(nrPDSCHIndices(carrier,before,'IndexBase','0based','IndexOrientation','carrier'));
newData = double(nrPDSCHIndices(carrier,after,'IndexBase','0based','IndexOrientation','carrier'));
dmrs = double(nrPDSCHDMRSIndices(carrier,after,'IndexBase','0based','IndexOrientation','carrier'));
ptrs = double(nrPDSCHPTRSIndices(carrier,after,'IndexBase','0based','IndexOrientation','carrier'));
assert(isempty(intersect(expectedCarrier,mod([newData(:);dmrs(:);ptrs(:)],K*L))));
expectedData = oldData(~ismember(mod(oldData(:,1),K*L),expectedCarrier),:);
assert(isequal(newData,expectedData),'Only exactly reserved native data rows may disappear.');
assert(isequal(nrPDSCHDMRSIndices(carrier,before),nrPDSCHDMRSIndices(carrier,after)), ...
    'Reference reservation must never puncture native DM-RS.');
materialized = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(carrier,after);
assert(materialized.RateMatchProof.NoOccupiedReservedRECollision && ...
    materialized.RateMatchProof.ToolboxDataExcludesReservedRE);
end

function localThrows(fcn,expected)
try
    fcn();
catch cause
    assert(strcmp(cause.identifier,expected),'testPDSCHReferenceReservationBWP:WrongGuard', ...
        'Expected %s, got %s: %s',expected,cause.identifier,cause.message);
    return;
end
error('testPDSCHReferenceReservationBWP:MissingGuard','Expected %s.',expected);
end
