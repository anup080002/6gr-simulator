function ok=testSLSFiniteWindowPhysicalClock()
% Production finite-window channel starts on its actual retained CP clock.
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg.run=struct('seed',113,'executionID','finite_physical_clock');
cfg.phy.carrier=struct('NSizeGrid',6,'NStartGrid',0,'SubcarrierSpacing',120,'NCellID',1);
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9; cfg.phy.numerology.scs_kHz=120;
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9;
cfg.scenario.ue.txPower_dBm=23;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A','delaySpread_s',30e-9, ...
    'doppler_Hz',70,'normalizeChannelOutputs',false);
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
cfg.system.linkAbstraction.networkSpatial.sinrPredictorModel='finite_committed_shared_data';
g=struct('RNTI',4660,'UEIndex',1,'PRBSet',0,'SymbolAllocation',[6 1],'NumLayers',1, ...
    'PHYGrant',struct('PrecodingState',struct('MatrixPorts',[1;1i]/sqrt(2))));
large=struct('Pathloss_dB',80,'TxPower_dBm',30);
for direction=["DL","UL"]
    for slot=[3 83]
        p=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
        state=struct('TTI',slot-1,'GrantsDL',struct([]),'GrantsUL',struct([]), ...
            'GrantCellsDL',[],'GrantCellsUL',[],'LargeScaleState',large);
        p.commitSlotPopulation(state); state.TTI=slot; p.commitSlotPopulation(state);
        state.TTI=slot+1; state.("Grants"+direction)=g; state.("GrantCells"+direction)=1;
        p.commitSlotPopulation(state);
        ctx=struct('TTI',slot+1,'Direction',direction,'Grant',g,'ServingCellID',1);
        o=p.evaluate(ctx,state);
        carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',120);
        info=nrOFDMInfo(carrier);
        perSlot=sum(reshape(info.SymbolLengths,carrier.SymbolsPerSlot,[]),1);
        first=o.FiniteWindow.ReceiveWindow.AbsoluteSlots0(1);
        expected=(floor(first/carrier.SlotsPerSubframe)*sum(perSlot)+ ...
            sum(perSlot(1:mod(first,carrier.SlotsPerSubframe))))/info.SampleRate;
        assert(o.FiniteWindow.DesiredObservation.ChannelStartTime_s==expected && ...
            abs(expected-first*.000125)>1e-10, ...
            'Finite-window fading retained the average-slot epoch.');
        assert(o.ResidualISIICIIncluded && all(isfinite(o.FiniteWindow.SpatialResult.SINRLinear),'all') && ...
            ~o.CommonControlInterferenceQualified);
        fprintf('SLS_FINITE_PHYSICAL_CLOCK direction=%s slot0=%d first_slot0=%d time=%.17g\n', ...
            direction,slot,first,expected);
    end
end
ok=true;
end
