function ok = testTRSPeriodicCadenceAuthority()
% Native mapping/configuration gate, not RF/RX or scheduler qualification.
% TS 38.214 V18.8.0 5.1.6.1.1 periodic trs-Info cadence and bandwidth.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
before = rng;
groups = {@localNativePeriods,@localBandwidthBoundary,@localOldCadences, ...
    @localExplicitRecurrence,@localNativeBinding,@localScenarioPolicies};
names = ["native_15_30_120_kHz","52_RB_boundary","old_invalid_cadences", ...
    "explicit_frame_recurrence","original_native_binding","three_YAML_policies"];
failures = strings(0,1);
for k=1:numel(groups)
    try
        groups{k}();
        fprintf('[PASS] TRSPeriodicCadenceAuthority %s\n',names(k));
    catch cause
        failures(end+1,1)=names(k)+": "+string(cause.identifier)+" "+string(cause.message); %#ok<AGROW>
        fprintf(2,'[FAIL] TRSPeriodicCadenceAuthority %s\n',failures(end));
    end
end
assert(isequal(before,rng),'TRS configuration/native reference checks must not consume RNG.');
assert(isempty(failures),'testTRSPeriodicCadenceAuthority:Failed', ...
    '%d/%d groups failed:\n%s',numel(failures),numel(groups),char(strjoin(failures,newline)));
ok=true;
end

function localNativePeriods()
for scs=[15 30 120]
    for periodMs=[10 20 40 80]
        period=periodMs*(scs/15);
        cfg=localConfig(scs,52,period);
        strict=sixgr.phy.trs.buildTRSConfigFromScenario(cfg,'RuntimeSlot',3);
        assert(strict.StrictValidation.StrictValid && ...
            strict.PeriodicityValidation.PeriodMilliseconds==periodMs && ...
            strict.ToolboxCarrier.SubcarrierSpacing==scs && strict.NumRB==52);
        localNativeActivity(cfg,strict);
        later=sixgr.phy.trs.buildTRSConfigFromScenario(cfg,'RuntimeSlot',period+3);
        assert(isequal(later.SlotNumbers,period+[2 3]) && ...
            isequal(later.ConfiguredSlotNumbers,[2 3]) && ...
            later.PeriodicityValidation.PeriodSlots==period);
    end
end
end

function localBandwidthBoundary()
for scs=[15 30 120]
    ratio=scs/15;
    valid=sixgr.phy.trs.buildTRSConfigFromScenario(localConfig(scs,52,10*ratio));
    assert(valid.NumRB==52 && valid.ToolboxCSIRS.NumRB==52);
    localMustFail(@()sixgr.phy.trs.buildTRSConfigFromScenario( ...
        localConfig(scs,53,10*ratio)),'sixgr:phy:trs:TRSPeriodicityBandwidth');
    valid=sixgr.phy.trs.buildTRSConfigFromScenario(localConfig(scs,53,20*ratio));
    assert(valid.StrictValidation.StrictValid && valid.NumRB==53 && ...
        all(cellfun(@(r)r.NumRB==53,valid.ToolboxResources)));
end
end

function localOldCadences()
% Actual old full-band values: h4 273RB/mu1/20slots, n77 106RB/mu0/10slots,
% and n40 51RB/mu1/10slots. No bandwidth reduction can rescue these inputs.
localMustFail(@()sixgr.phy.trs.buildTRSConfigFromScenario(localConfig(30,273,20)), ...
    'sixgr:phy:trs:TRSPeriodicityBandwidth');
localMustFail(@()sixgr.phy.trs.buildTRSConfigFromScenario(localConfig(15,106,10)), ...
    'sixgr:phy:trs:TRSPeriodicityBandwidth');
localMustFail(@()sixgr.phy.trs.buildTRSConfigFromScenario(localConfig(30,51,10)), ...
    'sixgr:phy:trs:InvalidPeriodicCadence');
localMustFail(@()sixgr.phy.trs.buildTRSConfigFromScenario(localConfig(120,52,20)), ...
    'sixgr:phy:trs:InvalidPeriodicCadence');
for period=[15 30 100]
    localMustFail(@()sixgr.phy.trs.buildTRSConfigFromScenario(localConfig(15,52,period)), ...
        'sixgr:phy:trs:InvalidPeriodicCadence');
end
end

function localExplicitRecurrence()
for scs=[15 30 120]
    cfg=localConfig(scs,52,80*(scs/15));
    cfg.phy.trs.slotNumbers=[2 3 7 8];
    originalIDs=[4 9 12 15 28 31 44 48];
    cfg.lls6g.reference_signals.trs.resource_ids=originalIDs;
    strict=sixgr.phy.trs.buildTRSConfigFromScenario(cfg,'RuntimeSlot',3);
    assert(strict.StrictValidation.StrictValid && ...
        strict.PeriodicityValidation.PeriodMilliseconds==10 && ...
        strict.PeriodicityValidation.ResourceSetsPerCalendar==2 && ...
        strict.PeriodicityValidation.PeriodSlots==10*(scs/15));
    assert(isequal(strict.ConfiguredSlotNumbers,[2 3 7 8]) && isequal(strict.SlotNumbers,[2 3]));
    for frame=0:1
        for setIndex=0:1
            firstSlot=[2 7];
            selected=sixgr.phy.trs.buildTRSConfigFromScenario(cfg, ...
                'RuntimeSlot',frame*10*(scs/15)+firstSlot(setIndex+1)+1);
            expectedIDs=originalIDs(setIndex*4+(1:4));
            assert(isequal(selected.ConfiguredNZPCSIRSResourceIDs,originalIDs) && ...
                isequal(selected.NZPCSIRSResourceIDs,expectedIDs));
            generated=sixgr.phy.trs.generateTRSSymbolsAndIndices(selected);
            assert(isequal(unique(generated.ResourceMappingTable.NZPCSIRSResourceID,'stable').',expectedIDs));
            assert(isequal([generated.SlotResources.Slot], ...
                frame*10*(scs/15)+firstSlot(setIndex+1)+(0:1)));
        end
    end
    badIDs=cfg; badIDs.lls6g.reference_signals.trs.resource_ids=originalIDs(1:7);
    localMustFail(@()sixgr.phy.trs.buildTRSConfigFromScenario(badIDs,'RuntimeSlot',8), ...
        'sixgr:qcl:InvalidTRSResourceIDs');
    for slot0=[2 3 7 8]+10*(scs/15)
        window=sixgr.truth.resolveTRSObservationWindow(cfg,slot0+1);
        assert(window.ResourceActive && window.Authority=="explicit_slot_numbers");
    end
    cfg.phy.trs.numRB=53; cfg.phy.carrier.NSizeGrid=53;
    localMustFail(@()sixgr.phy.trs.buildTRSConfigFromScenario(cfg,'RuntimeSlot',3), ...
        'sixgr:phy:trs:TRSPeriodicityBandwidth');
    % Omitting RuntimeSlot is not an escape: the configured list still
    % denotes the same recurring within-frame resources.
    localMustFail(@()sixgr.phy.trs.buildTRSConfigFromScenario(cfg), ...
        'sixgr:phy:trs:TRSPeriodicityBandwidth');
end
end

function localNativeBinding()
strict=sixgr.phy.trs.buildTRSConfigFromScenario(localConfig(30,53,40));
bad=strict; bad.PeriodSlots=20;
validation=sixgr.phy.trs.validateTRSConfigStrict(bad);
assert(~validation.StrictValid && any(validation.FailureReasons== ...
    "trs_periodicity_invalid:sixgr:phy:trs:TRSPeriodicityBandwidth"));
bad=strict; bad.NumRB=52; bad.PeriodSlots=20;
localMustFail(@()sixgr.phy.trs.validateTRSPeriodicity(bad), ...
    'sixgr:phy:trs:TRSCadenceNativeMismatch');
bad=strict; bad.SubcarrierSpacingKHz=15;
localMustFail(@()sixgr.phy.trs.validateTRSPeriodicity(bad), ...
    'sixgr:phy:trs:TRSCadenceNativeMismatch');
bad=strict; resource=bad.ToolboxResources{2}; resource.NumRB=52;
bad.ToolboxResources{2}=resource;
localMustFail(@()sixgr.phy.trs.validateTRSPeriodicity(bad), ...
    'sixgr:phy:trs:TRSCadenceNativeMismatch');
bad=strict; bad.SlotAuthority="finite_fixture_skip";
localMustFail(@()sixgr.phy.trs.validateTRSPeriodicity(bad), ...
    'sixgr:phy:trs:InvalidRecurringSlotAuthority');
bad=strict; bad.PeriodSlots=char(40);
localMustFail(@()sixgr.phy.trs.validateTRSPeriodicity(bad), ...
    'sixgr:phy:trs:InvalidPeriodicCadence');
bad=strict; bad.ConfiguredSlotNumbers=[3 4];
localMustFail(@()sixgr.phy.trs.validateTRSPeriodicity(bad), ...
    'sixgr:phy:trs:InvalidRecurringSlotAuthority');
cfg=localConfig(30,52,40);
bad=sixgr.phy.trs.buildTRSConfigFromScenario(cfg,'RuntimeSlot',43);
bad.RuntimeObservationWindow.AbsoluteSlotNumbers=bad.RuntimeObservationWindow.AbsoluteSlotNumbers+40;
localMustFail(@()sixgr.phy.trs.validateTRSPeriodicity(bad), ...
    'sixgr:phy:trs:InvalidRecurringSlotAuthority');
cfg=localConfig(30,52,40); cfg.phy.trs.slotNumbers=[2 3];
bad=sixgr.phy.trs.buildTRSConfigFromScenario(cfg);
bad=rmfield(bad,'ConfiguredSlotNumbers');
localMustFail(@()sixgr.phy.trs.validateTRSPeriodicity(bad), ...
    'sixgr:phy:trs:InvalidRecurringSlotAuthority');
end

function localScenarioPolicies()
paths=["h4_100_common_connected.yaml", ...
    "lls_tdd_4ghz_20mhz_64txru_4rx_cdlc100_impaired.yaml", ...
    "lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml"];
widths=[273 106 51]; spacing=[30 15 30]; periods=[40 20 20];
for k=1:numel(paths)
    scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
        'simulator','configs','scenarios',paths(k)));
    source=scenario.toStruct();
    cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
    assert(cfg.phy.trs.period_slots==periods(k) && cfg.phy.trs.numRB==widths(k));
    assert(source.reference_signals.trs_periodicity_slots==periods(k) && ...
        source.reference_signals.trs.periodicity_slots==periods(k) && ...
        string(source.reference_signals.trs.periodicity)==string(periods(k)/(spacing(k)/15))+"ms" && ...
        source.reference_signals.trs_periodicity_ms==periods(k)/(spacing(k)/15));
    first=cfg.phy.trs.period_offset+1;
    strict=sixgr.phy.trs.buildTRSConfigFromScenario(cfg,'RuntimeSlot',first);
    assert(strict.StrictValidation.StrictValid && strict.NumRB==widths(k) && ...
        strict.ToolboxCarrier.SubcarrierSpacing==spacing(k) && ...
        strict.PeriodicityValidation.PeriodSlots==periods(k));
    localNativeActivity(cfg,strict);
end
end

function localNativeActivity(cfg,strict)
period=cfg.phy.trs.period_slots; offset=cfg.phy.trs.period_offset;
slots=unique([max(0,offset-1),offset,offset+1,offset+2,offset+period,offset+period+1]);
carrier=strict.ToolboxCarrier;
for absolute0=slots
    carrier.NSlot=mod(absolute0,carrier.SlotsPerFrame);
    carrier.NFrame=floor(absolute0/carrier.SlotsPerFrame);
    nativeActive=false;
    for resourceSlot=0:1
        native=strict.ToolboxResources{1};
        native.CSIRSPeriod=[period mod(offset+resourceSlot,period)];
        indices=nrCSIRSIndices(carrier,native);
        symbols=nrCSIRS(carrier,native);
        assert(numel(indices)==numel(symbols));
        if ~isempty(indices)
            nativeActive=true;
            % Row 1 has three RE/RB per symbol, not a reduced-band proxy.
            [sc,~,~]=ind2sub([12*carrier.NSizeGrid carrier.SymbolsPerSlot],double(indices));
            assert(numel(unique(floor((sc-1)/12)))==strict.NumRB);
        end
    end
    window=sixgr.truth.resolveTRSObservationWindow(cfg,absolute0+1);
    assert(window.ResourceActive==nativeActive && ...
        sixgr.truth.isActiveTRSOccasion(cfg,absolute0+1)==nativeActive);
end
end

function cfg=localConfig(scs,width,period)
cfg=struct();
cfg.phy.carrier=struct('NCellID',7,'NSizeGrid',width,'NStartGrid',5, ...
    'SubcarrierSpacing',scs);
cfg.phy.numerology=struct('scs_kHz',scs,'slotsPerFrame',10*(scs/15));
cfg.phy.trs=struct('enable',true,'nPorts',1,'csirsRowNumber',1, ...
    'symbolLocation',[4 8],'subcarrierLocation',0,'rbOffset',0, ...
    'numRB',width,'scramblingID',7,'slotNumbers',[], ...
    'period_slots',period,'period_offset',2,'burstLengthSlots',2);
cfg.channel.model='AWGN';
end

function localMustFail(callback,id)
try
    callback();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('testTRSPeriodicCadenceAuthority:MissingGuard','Expected %s.',id);
end
