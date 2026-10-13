function ok=testPlannedPRACHCalendarCoverage(builder)
% Exact 100-MHz H4 calendar coverage, not a waveform/performance run.
arguments
    builder (1,1) function_handle = @sixgr.truth.buildPlannedREAllocation
end
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
    'simulator','configs','scenarios','h4_100_cdlc100_connected_adaptive.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
frame=sixgr.phy.FrameStructureEngine(cfg);
assert(frame.CenterFrequencyHz==4e9 && frame.BandwidthHz==100e6 && ...
    frame.DuplexMode=="TDD" && frame.NRB==273);
period=double(frame.PRACHTiming.PeriodCarrierSlots);
cfg.run.totalSlots=2*period+ceil(period/2);
cfg.prach_lls.NumSlots=cfg.run.totalSlots;
[rows,checks]=builder(cfg,'TargetChannels','PRACH');
sixgr.truth.assertAllocationPreflight(checks);
prach=rows(rows.channel=="PRACH",:);
canonical=frame.PRACHTiming.Occasions;
expected=double(canonical.AbsoluteSlot)+(0:2)*period;
expected=unique(expected(expected<cfg.run.totalSlots));
% Independent H4 anchor: TS 38.211 Table 6.3.3.2-3 row 157 is B4,
% x=1,y=0,subframe=4,one PRACH slot/time occasion. At this 30-kHz
% carrier the native origin is slot 9 and repeats every 20 carrier slots.
assert(period==20 && isequal(expected(:),[9;29;49]), ...
    'sixgr:test:H4PRACHCalendarAnchor', ...
    'The H4 calendar must preserve its installed row-157 PRACH/TDD clock.');
assert(numel(expected)>1 && isequal(sort(unique(prach.absolute_slot)),sort(expected(:))), ...
    'sixgr:test:PlannedPRACHFirstOccasionOnly', ...
    'Every configured PRACH repetition in the run window must be present, not only FirstActiveOccasion.');
assert(all(prach.evidence_scope=="planned_config_not_runtime_observation") && ...
    all(prach.grid_domain=="prach_native_ofdm"), ...
    'Planned PRACH resources must not be presented as executed carrier-grid traffic.');
assert(all(prach.absolute_slot>=0 & prach.absolute_slot<cfg.run.totalSlots));
assert(all(prach.occurrence_count==1));

% Compare every exported contiguous native-RE run with direct Toolbox
% materialization using the resolved NPRACHSlot/ActiveSlot/time/frequency.
strict=sixgr.rach.PRACHConfig(cfg);
carrier=sixgr.phy.grid.makeCarrier(cfg);
expectedRE=0;
for repetition=0:2
    for ordinal=1:height(canonical)
        row=canonical(ordinal,:);
        slot=double(row.AbsoluteSlot)+repetition*period;
        if slot>=cfg.run.totalSlots,continue;end
        carrier.NFrame=floor(slot/carrier.SlotsPerFrame);
        carrier.NSlot=mod(slot,carrier.SlotsPerFrame);
        resource=strict.ToolboxPRACH;
        resource.NPRACHSlot=double(row.PRACHSlot)+ ...
            repetition*double(frame.PRACHTiming.PeriodPRACHSlots);
        resource.ActivePRACHSlot=double(row.ActivePRACHSlot);
        resource.TimeIndex=double(row.TimeIndex);
        resource.FrequencyIndex=double(row.FrequencyIndex);
        exact=double(nrPRACHIndices(carrier,resource,'IndexStyle','subscript','IndexBase','0based'));
        if size(exact,2)==2,exact(:,3)=0;end
        identity="prach_slot_"+string(slot)+"_native_"+string(resource.NPRACHSlot)+ ...
            "_active_"+string(resource.ActivePRACHSlot)+"_time_"+string(resource.TimeIndex)+ ...
            "_frequency_"+string(resource.FrequencyIndex);
        observed=prach(prach.allocation_id==identity,:);
        coordinates=zeros(0,3);
        for n=1:height(observed)
            k=observed.subcarrier_start(n)+(0:observed.subcarrier_count(n)-1).';
            coordinates=[coordinates;[k,repmat(observed.symbol_index(n),numel(k),1), ...
                repmat(observed.port_index(n),numel(k),1)]]; %#ok<AGROW>
        end
        assert(isequal(sortrows(coordinates),sortrows(unique(exact,'rows'))), ...
            'sixgr:test:PlannedPRACHNativeClockMismatch', ...
            'Each repeated PRACH occasion must retain its exact native-grid coordinates.');
        expectedRE=expectedRE+size(unique(exact,'rows'),1);
    end
end
assert(sum(prach.re_count)==expectedRE && checks.exact_re_count(checks.feature=="PRACH")==expectedRE);
fprintf('PLANNED_PRACH_CALENDAR_PASS builder=%s slots=%d occurrences=%d exactRE=%d\n', ...
    func2str(builder),cfg.run.totalSlots,numel(unique(prach.allocation_id)),expectedRE);
ok=true;
end
