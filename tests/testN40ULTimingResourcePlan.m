function ok=testN40ULTimingResourcePlan()
% Selected production n40 calendar: native mappings, not waveform acceptance.
setup6GRSimToolkit('Verbose',false);
paths=[ ...
    "simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml", ...
    "simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml"];
checked=0;
for path=paths
    scenario=sixgr.lls6g.config.loadScenarioConfig(path);
    cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
    assert(sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD");
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    assert(carrier.NSizeGrid==51 && carrier.SubcarrierSpacing==30);
    assert(cfg.phy.synchronization.maxReceivedULTimingAgeSlots==4, ...
        'Do not fix timing starvation by widening the received-clock age.');
    contexts=sixgr.truth.validateSharedDCIConfiguration(cfg);
    p=cfg.phy.pusch;
    assert(isequal(double(p.SymbolAllocation),[0 11]));
    tdra=double(contexts.UL.Data.ULTimeDomainAllocations);
    assert(isequal(tdra,[0 0 11 4;1 0 11 4]), ...
        'Both installed DCI TDRA entries must match the PUSCH symbol plan.');
    assert(sixgr.phy.pdcch.DCIContextFactory.supportsSymbolAllocation(cfg,'UL',[0 11]));
    assert(~sixgr.phy.pdcch.DCIContextFactory.supportsSymbolAllocation(cfg,'UL',[0 13]));
    native=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
    assert(native.ToolboxSRS.SymbolStart==11 && native.ToolboxSRS.NumSRSSymbols==1);
    assert(isequal(double(native.ToolboxSRS.SRSPeriod),[5 4]), ...
        'The repair must preserve the actual five-slot/offset-four sounding calendar.');
    grant=struct('UEIndex',1,'PRBSet',double(p.PRBSet), ...
        'SymbolAllocation',double(p.SymbolAllocation),'Modulation',char(string(p.modulation)), ...
        'NumLayers',double(p.numLayers),'RNTI',double(p.RNTI), ...
        'TransformPrecoding',logical(p.transformPrecoding), ...
        'TransmissionScheme',char(string(p.TransmissionScheme)), ...
        'NumAntennaPorts',double(p.NumAntennaPorts),'TPMI',double(p.TPMI), ...
        'NID',double(p.NID),'MappingType',char(string(p.mappingType)));
    resources=cfg.validation.pucch_resources.resources;
    occasions=0;
    for slot0=0:2*carrier.SlotsPerFrame-1
        carrier.NSlot=mod(slot0,carrier.SlotsPerFrame);
        carrier.NFrame=floor(slot0/carrier.SlotsPerFrame);
        indices=nrSRSIndices(carrier,native.ToolboxSRS);
        if isempty(indices), continue; end
        % Inspect native coordinates, not just a configured symbol label.
        [~,symbols,~]=ind2sub([12*carrier.NSizeGrid 14 native.NumSRSPorts],double(indices));
        assert(all(symbols==12,'all')); % MATLAB index12 = radio symbol11.
        assert(mod(slot0,5)==4, 'SRS must remain on the configured full-UL occasions.');
        direction=sixgr.phy.frame.SlotFormatResolver.isAvailable( ...
            cfg.phy.frameStructure.SlotState,slot0,0,double(carrier.SymbolsPerSlot),'UL');
        assert(direction.Available && all(ismember(direction.ObservedDirections,["U","UL"])), ...
            'Native sounding occasions must be full UL in the installed symbol map, not only the expected period phase.');
        grant.ScheduledAbsoluteSlot=slot0+1; grant.Slot=slot0+1;
        dataDecision=sixgr.phy.frame.resolveSRSPUSCHCollision(cfg,grant,slot0+1,1);
        assert(~dataDecision.Collision && dataDecision.SRSRECount>0 && dataDecision.PUSCHRECount>0);
        for resource=reshape(resources,1,[])
            pucch=struct('UEIndex',1,'RNTI',p.RNTI,'PUCCHResourceId',resource.id);
            decision=sixgr.phy.frame.resolveSRSPUCCHCollision(cfg,pucch,slot0+1,1);
            assert(~decision.Collision && decision.SRSRECount>0 && decision.PUCCHRECount>0);
        end
        occasions=occasions+1;
    end
    assert(occasions==8, 'Two 30-kHz frames must retain all eight native SRS occasions.');
    checked=checked+occasions;
    old=scenario.toStruct(); old.reference_signals.srs.symbol_start=13;
    rejected=false;
    try
        sixgr.lls6g.buildInternalConfig(old,tempname);
    catch cause
        assert(strcmp(cause.identifier,'sixgr:lls6g:config:SRSFirstMeasurementPUCCHCollision'), ...
            'Unexpected old-layout rejection: %s',cause.identifier);
        rejected=true;
    end
    assert(rejected, 'The previous SRS13/PUCCH12..13 starvation layout must be rejected.');
end
fprintf('N40_UL_TIMING_RESOURCE_PLAN_PASS scenarios=2 native_occasions=%d freshness_slots=4 waveform_acceptance=0\n',checked);
ok=true;
end
