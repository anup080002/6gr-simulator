function ok = testCommonDLCSIRSOwnership()
% Reproduce the common-PDSCH/CSI-RS collision in the connected 5-MHz run.
% Allocation evidence only: no claimed PHY CRC or statistical qualification.
setup6GRSimToolkit('Verbose',false);
s = sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml');
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
% Explicit retained failing-calendar fixture, independent of later YAML fixes.
cfg.phy.csirs.period_slots = 5;
cfg.phy.csirs.offset_slots = 2;
plan = sixgr.phy.frame.CommonDLResourcePlan(cfg);
allocation = struct('PRBStart',3,'NumPRB',6,'SymbolStart',2,'NumSymbols',12);
before = rng;

% Canonical slot 33 had Msg4 and an independently transmitted CSI-RS.
% RA/common receivers cannot inherit dedicated CSI-RS puncturing authority.
[free,evidence] = plan.checkPDSCH(allocation,32);
assert(~free && any(evidence.ConflictingOwners == "CSI-RS"), ...
    'testCommonDLCSIRSOwnership:CommonCollisionAdmitted', ...
    'Common/RA PDSCH must not be admitted over independently scheduled CSI-RS.');
assert(all(evidence.OverlapRECounts>0) && ~evidence.ProxyUsed && ~evidence.FallbackUsed);
localReject(@()plan.validateSIB1References(), ...
    'sixgr:phy:frame:SIB1CSIRSCollision');
% The production RA planning boundary must enforce the same ownership;
% calling a helper in isolation would not prevent the observed collision.
localReject(@()sixgr.mac.ra.RAConfig(cfg), ...
    'sixgr:phy:frame:SIB1CSIRSCollision');
% A collision only on the second SIB1 repetition must not evade preflight.
later = cfg;
later.phy.csirs.period_slots = 40;
later.phy.csirs.offset_slots = 22;
laterPlan = sixgr.phy.frame.CommonDLResourcePlan(later);
localReject(@()laterPlan.validateSIB1References(), ...
    'sixgr:phy:frame:SIB1CSIRSCollision');

% A noncolliding authored calendar leaves the CSI-RS producer enabled.
% It neither deletes reference samples nor changes an already coded TB.
legal = cfg;
legal.phy.csirs.offset_slots = 0;
legalPlan = sixgr.phy.frame.CommonDLResourcePlan(legal);
legalPlan.validateSIB1References();
assert(legalPlan.checkPDSCH(allocation,32));
[free,common] = legalPlan.checkPDSCH(allocation,5);
assert(~free && any(common.ConflictingOwners == "CSI-RS"));
[free,connected] = legalPlan.checkConnectedPDSCH(allocation,5);
assert(free && connected.CSIRSRateMatchedRECount>0);
localVerifyExactReservation(legal,allocation,5,connected.CSIRSRateMatchedRECount);

% Common admission is frequency/symbol selective, not a whole-slot ban.
narrow = legal;
narrow.phy.csirs.numRB = 12;
narrow.phy.csirs.numRBsByResource = 12;
narrowPlan = sixgr.phy.frame.CommonDLResourcePlan(narrow);
outside = allocation; outside.PRBStart = 20; outside.NumPRB = 2;
assert(narrowPlan.checkPDSCH(outside,5));

% Dedicated sharing must not erase an active DM-RS to make room for CSI-RS.
badDMRS = legal;
badDMRS.phy.csirs.symbolLocations = 2;
badDMRS.phy.csirs.symbolLocationsByResource = 2;
badDMRSPlan = sixgr.phy.frame.CommonDLResourcePlan(badDMRS);
localReject(@()badDMRSPlan.checkConnectedPDSCH(allocation,5), ...
    'sixgr:phy:grid:allocREsPDSCH:CSIRSDMRSCollision');

% Both reference families can share connected data only by exact allocation.
% Neither becomes available to common/RA traffic through the dedicated API.
joint = allocation;
joint.NumSymbols = 8;
[free,common] = plan.checkPDSCH(joint,7);
assert(~free && all(ismember(["CSI-RS","TRS"],common.ConflictingOwners)));
[free,connected] = plan.checkConnectedPDSCH(joint,7);
assert(free && connected.CSIRSRateMatchedRECount>0 && connected.TRSRateMatchedRECount>0);
localVerifyExactReservation(cfg,joint,7,connected.CSIRSRateMatchedRECount);
assert(~plan.checkPDSCH(joint,7),'Dedicated sharing must not mutate common ownership.');

% Disabling CSI-RS removes only its reservation; existing SIB1 stays owned.
disabled = cfg;
disabled.phy.csirs.enable = false;
disabledPlan = sixgr.phy.frame.CommonDLResourcePlan(disabled);
disabledPlan.validateSIB1References();
assert(disabledPlan.checkPDSCH(allocation,32));
[free,si] = legalPlan.checkConnectedPDSCH(allocation,legalPlan.SIB1Slot0);
assert(~free && any(si.ConflictingOwners == "SIB1_PDSCH_and_Type0_PDCCH"));
assert(isequal(before,rng),'Resource planning must not consume payload/noise RNG.');
ok = true;
fprintf('COMMON_DL_CSIRS_OWNERSHIP_PASS common_exclusion=1 exact_connected_reservation=1 calendar_guard=1\n');
end

function localVerifyExactReservation(cfg,allocation,slot0,expectedCount)
current = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
carrier = sixgr.phy.grid.makeCarrier(current);
[ind,symbols] = sixgr.phy.refsig.csirs(carrier,current);
assert(~isempty(symbols));
plane = 12*carrier.NSizeGrid*carrier.SymbolsPerSlot;
reference = unique(mod(double(ind(:))-1,plane));
[data,~,pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier,current, ...
    'PRBSet',allocation.PRBStart+(0:allocation.NumPRB-1), ...
    'SymbolAllocation',[allocation.SymbolStart allocation.NumSymbols]);
k = mod(reference,12*carrier.NSizeGrid);
l = floor(reference/(12*carrier.NSizeGrid));
inside = k>=12*allocation.PRBStart & k<12*(allocation.PRBStart+allocation.NumPRB) & ...
    l>=allocation.SymbolStart & l<allocation.SymbolStart+allocation.NumSymbols;
reference = reference(inside);
pilots = [reshape(nrPDSCHDMRSIndices(carrier,pdsch),[],1); ...
    reshape(nrPDSCHPTRSIndices(carrier,pdsch),[],1)];
occupied = unique(mod(double([data(:);pilots(:)])-1,plane));
assert(numel(reference)==expectedCount && ...
    all(ismember(reference,mod(double(pdsch.ReservedRE(:)),plane))) && ...
    isempty(intersect(reference,occupied)));
end

function localReject(action,identifier)
try
    action();
catch cause
    assert(strcmp(cause.identifier,identifier), ...
        'Expected %s; received %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('testCommonDLCSIRSOwnership:MissingRejection','Expected %s.',identifier);
end
