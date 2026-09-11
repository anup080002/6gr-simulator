function ok=testSSBPRBSymbolReservation()
% Actual configured SSB calendar and NR data/DM-RS allocation, no RF proxy.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,1,1);
carrier=sixgr.phy.grid.makeCarrier(cfg);
assert(carrier.SubcarrierSpacing==15 && cfg.phy.ssb.Lmax==4);
r=sixgr.phy.frame.ssbPRBSymbolReservation(cfg,carrier,0);
assert(isequal(r.SymbolSet,[2:5 8:11]) && isequal(r.SSBIndices0,[0 1]));
rbLow=((0:carrier.NSizeGrid-1)+carrier.NStartGrid)*12*carrier.SubcarrierSpacing*1e3;
expected=find(rbLow<r.SSBHighOffsetFromPointAHz & ...
    rbLow+12*carrier.SubcarrierSpacing*1e3>r.SSBLowOffsetFromPointAHz)-1;
assert(isequal(expected,r.CarrierPRBSet));
assert(numel(r.ReservedCarrierRE0)==numel(expected)*12*8);
later=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,41,5);
rc=sixgr.phy.grid.makeCarrier(later);
repeated=sixgr.phy.frame.ssbPRBSymbolReservation(later,rc,40);
assert(isequal(r.ReservedCarrierRE0,repeated.ReservedCarrierRE0));
quiet=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,4,1);
assert(isempty(sixgr.phy.frame.ssbPRBSymbolReservation(quiet, ...
    sixgr.phy.grid.makeCarrier(quiet),3).ReservedCarrierRE0));
p=nrPDSCHConfig;
p.PRBSet=0:carrier.NSizeGrid-1;
p.MappingType='B'; p.SymbolAllocation=[6 8];
p.DMRS.DMRSAdditionalPosition=0;
[before,baseInfo]=nrPDSCHIndices(carrier,p,'IndexBase','0based');
[reserved,~]=sixgr.phy.grid.reserveSSBPDSCHResources(carrier,p,cfg);
[after,info]=nrPDSCHIndices(carrier,reserved,'IndexBase','0based');
assert(isempty(intersect(double(after(:)),r.ReservedCarrierRE0)) && info.G<baseInfo.G);
assert(numel(before)-numel(after)==numel(expected)*12*4);
% The same physical exclusion must use BWP-relative reserved PRBs.
p.NStartBWP=carrier.NStartGrid+1; p.NSizeBWP=carrier.NSizeGrid-2;
p.PRBSet=0:p.NSizeBWP-1;
reserved=sixgr.phy.grid.reserveSSBPDSCHResources(carrier,p,cfg);
after=nrPDSCHIndices(carrier,reserved,'IndexBase','0based','IndexOrientation','carrier');
assert(isempty(intersect(double(after(:)),r.ReservedCarrierRE0)));
% A real colliding DM-RS must fail before the data-index/G calculation.
p.NStartBWP=[];p.NSizeBWP=[];p.PRBSet=0:carrier.NSizeGrid-1;
p.MappingType='A';p.SymbolAllocation=[2 12];p.DMRS.DMRSTypeAPosition=2;
localReject(@()sixgr.phy.grid.reserveSSBPDSCHResources(carrier,p,cfg), ...
    'sixgr:phy:grid:allocREsPDSCH:SSBDMRSCollision');
cfg.phy.csirs.enable=false;cfg.phy.trs.enable=false;
localReject(@()sixgr.phy.grid.allocREsPDSCH(carrier,cfg, ...
    'SymbolAllocation',[2 12],'MappingType','A'), ...
    'sixgr:phy:grid:allocREsPDSCH:SSBDMRSCollision');
% Cross-numerology calendar uses physical CP boundaries, not symbol counts
% divided by a guessed SCS ratio. This is a calendar test, not mixed-SCS RF.
mixed=cfg;
mixed.phy.carrier.SubcarrierSpacing=30;
mixed.phy.carrier.SubcarrierSpacing_kHz=30;
mixed.phy.carrier.NSizeGrid=51;
mixed.phy.bwp.dl.NSizeBWP=51;
mc=sixgr.phy.grid.makeCarrier(mixed);
mr=sixgr.phy.frame.ssbPRBSymbolReservation(mixed,mc,0);
assert(isequal(mr.SymbolSet,4:11) && isequal(mr.SSBIndices0,0));
% Check reservations against actual generated SS/PBCH grid samples. Blank
% REs inside an occupied SSB PRB remain reserved by the standard as well.
[wave,wi,tx]=sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',5);
assert(~isempty(wave));
grid=wi.ResourceGridSSBurst.ResourceGrid;
offset=(tx.SSBGridValidation.SSBLowOffsetFromPointAHz- ...
    tx.SSBGridValidation.CarrierLowOffsetFromPointAHz)/(carrier.SubcarrierSpacing*1e3);
assert(offset==fix(offset));
for slot=0:size(grid,2)/carrier.SymbolsPerSlot-1
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot+1);
    cr=sixgr.phy.grid.makeCarrier(current);
    map=sixgr.phy.frame.ssbPRBSymbolReservation(current,cr,slot);
    mask=any(abs(grid(:,slot*carrier.SymbolsPerSlot+(1:carrier.SymbolsPerSlot),:))>0,3);
    [k,l]=find(mask);
    actual=double(k-1)+offset+12*carrier.NSizeGrid*double(l-1);
    assert(all(ismember(actual,map.ReservedCarrierRE0)), ...
        'An actual generated SSB resource is absent from the planned exclusion.');
end
ok=true;
end
function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:ExpectedSSBCollision','Expected %s.',id);
end
