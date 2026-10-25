function ok=testPlannedPDSCHTDRAGeometry()
% Original n40 configuration and declared geometry variants only: no PHY
% waveform, scheduler grant, received DCI, delivery or BLER qualification.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
cfg.run.totalSlots=10;
cfg.outputs.plannedAllocationEncoding='expanded_per_slot';
original=cfg;
frame=sixgr.phy.FrameStructureEngine(cfg);
assert(frame.SCSkHz==30 && frame.NRB==51 && frame.SymbolsPerSlot==14);
assert(isequal(double(cfg.phy.pdsch.symbolAllocation),[0 14]) && ...
    isequal(double(cfg.phy.pdsch.timeDomainAllocations),[0 0 14 0;1 0 10 0]));

[expanded,checks]=plan(cfg,true);
assert(isequaln(cfg,original),'Planning must not mutate the original configuration.');
assert(all(expanded.authority=="configured_RRC_BWP_resource_pool_not_scheduler_grant") && ...
    all(expanded.evidence_scope=="planned_config_not_runtime_observation"));
assert(isequal(unique(expanded.absolute_slot).',[0 1 2 3 5 6 7 8]), ...
    'sixgr:test:PlannedSpecialTDRAOmitted', ...
    'Both configured ten-symbol special DL occasions must be planned.');
assertNativeGeometry(cfg,expanded);
fprintf('PLANNED_TDRA_NATIVE_PASS slots=%s special_symbols=0:9\n', ...
    mat2str(unique(expanded.absolute_slot).'));

[uncached,uncachedChecks]=plan(cfg,false);
assert(isequaln(expanded,uncached) && isequaln(checks,uncachedChecks), ...
    'sixgr:test:PlannedTDRACacheMismatch','Cached coordinates must match every exact uncached slot.');
compactCfg=cfg; compactCfg.outputs.plannedAllocationEncoding='exact_periodic_templates';
[compact,compactChecks]=plan(compactCfg,true);
assert(height(compact)<height(expanded) && ...
    isequaln(comparable(expand(compact)),comparable(expanded)) && ...
    isequal(checks.exact_re_count,compactChecks.exact_re_count), ...
    'sixgr:test:PlannedTDRACompactionMismatch','Compaction must preserve each slot and its exact TDRA geometry.');
fprintf('PLANNED_TDRA_CACHE_PASS expanded=%d compact=%d\n',height(expanded),height(compact));

% A nonmatching K0 is not rewritten, and a missing row is not invented.
for useWrongOffset=[false true]
    absent=cfg;
    catalog=[0 0 14 0];
    if useWrongOffset, catalog=[catalog;1 0 10 1]; end %#ok<AGROW>
    absent.phy.pdsch.timeDomainAllocations=catalog;
    absent.phy.pdsch.TimeDomainAllocations=catalog;
    [rows,~]=plan(absent,true);
    assert(~any(ismember(rows.absolute_slot,[3 8])) && ...
        isequaln(comparable(rows),comparable(expanded(~ismember(expanded.absolute_slot,[3 8]),:))), ...
        'sixgr:test:PlannedTDRAInvented','Unavailable same-slot TDRA must not be clipped or inferred.');
end
conflicting=cfg;
conflicting.phy.pdsch.TimeDomainAllocations=cfg.phy.pdsch.timeDomainAllocations;
conflicting.phy.pdsch.TimeDomainAllocations(2,3)=8;
[~,badChecks]=sixgr.truth.buildPlannedREAllocation(conflicting,'TargetChannels',"PDSCH");
bad=badChecks(badChecks.feature=="PDSCH",:);
assert(~bad.resolved && bad.error_id=="sixgr:truth:ConflictingTDRACatalog");
fprintf('PLANNED_TDRA_ABSENCE_AND_CONFLICT_PASS\n');

% The selected row, rather than a hard-coded ten-symbol truncation, drives
% all pilot/data geometry. Authored order selects the first legal row.
shorter=cfg;
shorter.phy.pdsch.timeDomainAllocations=[0 0 14 0;9 0 8 0;1 0 10 0];
shorter.phy.pdsch.TimeDomainAllocations=shorter.phy.pdsch.timeDomainAllocations;
[shortRows,~]=plan(shorter,true);
assertNativeGeometry(shorter,shortRows);
assert(max(shortRows.symbol_index(shortRows.absolute_slot==3))==7 && ...
    max(expanded.symbol_index(expanded.absolute_slot==3))==9);
fprintf('PLANNED_TDRA_AUTHORED_ORDER_PASS\n');

% Isolate the installed control calendar in a declared component variant.
% The original n40 case above retains all its actual SSB/CSI/TRS exclusions.
calendar=cfg;
calendar.phy.ssb.enable=false;
calendar.phy.csirs.enable=false;
calendar.phy.trs.enable=false;
calendar.phy.csiim.enabled=false;
calendar.phy.pdcch.operatorControl.connected_monitoring.period_slots=2;
calendar.phy.pdcch.operatorControl.connected_monitoring.offset_slots=0;
calendar.phy.pdcch.operatorControl.connected_monitoring.duration_slots=1;
assert(any(string(calendar.phy.pdsch.rateMatchingPattern)=="connected_coreset"));
[calendarCached,~]=plan(calendar,true);
[calendarExact,~]=plan(calendar,false);
assert(isequaln(calendarCached,calendarExact), ...
    'sixgr:test:PlannedCORESETCalendarCacheMismatch', ...
    'Monitoring and nonmonitoring slots must not share a PDSCH coordinate template.');
assertNativeGeometry(calendar,calendarCached);
active=sum(calendarCached.re_count(calendarCached.absolute_slot==0));
inactive=sum(calendarCached.re_count(calendarCached.absolute_slot==1));
assert(inactive>active,'The declared CORESET calendar must change actual available RE geometry.');
calendar.outputs.plannedAllocationEncoding='exact_periodic_templates';
[calendarCompact,~]=plan(calendar,true);
assert(isequaln(comparable(expand(calendarCompact)),comparable(calendarExact)));
fprintf('PLANNED_CORESET_CALENDAR_PASS active_re=%d inactive_re=%d\n',active,inactive);
ok=true;
end

function [rows,checks]=plan(cfg,reuse)
[rows,checks]=sixgr.truth.buildPlannedREAllocation(cfg,'TargetChannels',"PDSCH", ...
    'ReusePeriodicCoordinateTemplates',reuse);
sixgr.truth.assertAllocationPreflight(checks);
rows=rows(rows.channel=="PDSCH",:);
end

function assertNativeGeometry(cfg,rows)
frame=sixgr.phy.FrameStructureEngine(cfg);
catalog=double(cfg.phy.pdsch.timeDomainAllocations);
for slot=0:cfg.run.totalSlots-1
    allocation=double(cfg.phy.pdsch.symbolAllocation);
    if ~frame.IsDLAllocation(slot,allocation)
        partition=frame.SlotPartition(slot);
        region=double(partition.DLSymbolAllocation);
        hit=find(catalog(:,2)>=region(1) & catalog(:,2)+catalog(:,3)<=sum(region) & ...
            catalog(:,4)==0,1,'first');
        if isempty(hit)
            assert(~any(rows.absolute_slot==slot));
            continue;
        end
        allocation=catalog(hit,2:3);
    end
    actual=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot+1);
    actual.phy.pdsch.symbolAllocation=allocation;
    carrier=sixgr.phy.grid.makeCarrier(actual);
    pdsch=sixgr.phy.grid.pdschConfigFromConfig(carrier,actual);
    reservation=sixgr.phy.frame.ssbPRBSymbolReservation(actual,carrier,slot);
    available=sixgr.phy.grid.pdschPRBsWithoutReservedDMRS( ...
        carrier,pdsch,reservation.ReservedCarrierRE0);
    if isempty(available)
        assert(~any(rows.absolute_slot==slot));
        continue;
    end
    [~,~,pdsch]=sixgr.phy.grid.allocREsPDSCH(carrier,actual,'PRBSet',available);
    indices={nrPDSCHIndices(carrier,pdsch),nrPDSCHDMRSIndices(carrier,pdsch), ...
        nrPDSCHPTRSIndices(carrier,pdsch)};
    labels=["PDSCH_DATA","PDSCH_DMRS","PDSCH_PTRS"];
    selected=rows(rows.absolute_slot==slot,:);
    assert(~isempty(selected) && all(selected.symbol_index>=allocation(1) & ...
        selected.symbol_index<sum(allocation)));
    for k=1:numel(labels)
        native=double(indices{k}(:));
        expected=sort(unique(native));
        emitted=selected(selected.component==labels(k),:);
        restored=zeros(0,1);
        K=12*double(carrier.NSizeGrid); L=double(carrier.SymbolsPerSlot);
        for j=1:height(emitted)
            sc=emitted.subcarrier_start(j)+(0:emitted.subcarrier_count(j)-1);
            restored=[restored;sc(:)+K*emitted.symbol_index(j)+K*L*emitted.port_index(j)+1]; %#ok<AGROW>
        end
        assert(isequal(sort(restored),expected), ...
            'sixgr:test:PlannedTDRANativeMismatch', ...
            'Slot %d %s must equal native indices for the selected original TDRA.',slot,labels(k));
        physical=mod(restored-1,K*L);
        assert(isempty(intersect(physical,reservation.ReservedCarrierRE0)));
    end
end
end

function expanded=expand(compact)
parts=cell(height(compact),1);
for k=1:height(compact)
    slots=str2double(split(string(compact.occurrence_slots(k)),"|"));
    assert(all(isfinite(slots)) && numel(slots)==compact.occurrence_count(k));
    part=compact(repmat(k,numel(slots),1),:);
    part.absolute_slot=slots(:);
    parts{k}=part;
end
expanded=vertcat(parts{:});
end

function out=comparable(rows)
names=["absolute_slot","direction","channel","component","subcarrier_start", ...
    "subcarrier_count","symbol_index","port_index","re_count","layer_count", ...
    "authority","resolver","grid_domain","grid_subcarrier_spacing_hz", ...
    "grid_subcarrier_count","grid_symbol_count"];
out=sortrows(rows(:,names),names);
end
