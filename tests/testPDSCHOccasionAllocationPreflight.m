function ok=testPDSCHOccasionAllocationPreflight()
% Real configured NR RE geometry; planning is not an observed waveform/grant.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_tdd_connected_feedback_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
[rows,checks]=sixgr.truth.buildPlannedREAllocation(cfg,'TargetChannels',["PDSCH","PUSCH"]);
sixgr.truth.assertAllocationPreflight(checks);
dl=rows(rows.channel=="PDSCH",:); ul=rows(rows.channel=="PUSCH",:);
assert(~isempty(dl) && ~isempty(ul));
assert(all(dl.authority=="configured_RRC_BWP_resource_pool_not_scheduler_grant"));
assert(all(rows.evidence_scope=="planned_config_not_runtime_observation"));
reservedCounts=[]; quietCounts=[];
for slot=unique(dl.absolute_slot).'
    actual=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot+1);
    carrier=sixgr.phy.grid.makeCarrier(actual);
    reservation=sixgr.phy.frame.ssbPRBSymbolReservation(actual,carrier,slot);
    selected=dl(dl.absolute_slot==slot,:);
    occupied=false(12*carrier.NSizeGrid,carrier.SymbolsPerSlot);
    for i=1:height(selected)
        occupied(selected.subcarrier_start(i)+(1:selected.subcarrier_count(i)), ...
            selected.symbol_index(i)+1)=true;
    end
    assert(~any(occupied(reservation.ReservedCarrierRE0+1)), ...
        'Planned PDSCH overlaps a real SS/PBCH reservation.');
    if isempty(reservation.ReservedCarrierRE0)
        quietCounts(end+1)=nnz(occupied); %#ok<AGROW>
        % Quiet occasions must retain their own full configured PRB pool.
        p=sixgr.phy.grid.pdschConfigFromConfig(carrier,actual);
        d=nrPDSCHDMRSIndices(carrier,p,'IndexStyle','subscript', ...
            'IndexBase','0based','IndexOrientation','carrier');
        assert(all(occupied(double(d(:,1))+12*carrier.NSizeGrid*double(d(:,2))+1)));
    else
        reservedCounts(end+1)=nnz(occupied); %#ok<AGROW>
    end
end
assert(~isempty(reservedCounts) && ~isempty(quietCounts));
assert(max(quietCounts)>max(reservedCounts),'SSB exclusions must not leak into quiet slots.');
% A configuration whose entire selected pool conflicts must still fail.
bad=cfg; bad.run.totalSlots=1;
actual=sixgr.phy.grid.applyRuntimeCarrierTimeline(bad,1);
c=sixgr.phy.grid.makeCarrier(actual);
r=sixgr.phy.frame.ssbPRBSymbolReservation(actual,c,0);
bad.phy.pdsch.prbSet=r.CarrierPRBSet;
[~,badChecks]=sixgr.truth.buildPlannedREAllocation(bad,'TargetChannels',"PDSCH");
assert(~badChecks.resolved(badChecks.feature=="PDSCH"));
assert(badChecks.error_id(badChecks.feature=="PDSCH")=="sixgr:truth:NoPDSCHOccasion");
ok=true;
disp('PDSCH_OCCASION_PREFLIGHT_PASS: actual per-slot reservations, no fake grants, all-blocked rejection.');
end
