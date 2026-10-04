function ok=testSLSNetworkReceiveWindow()
% Native filter/FFT support determines retained network-window capacity.
% Empty slots here are explicit numerical fixtures, not captured RF silence.
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg.run=struct('seed',113,'executionID','network_receive_window_component');
cfg.phy.carrier=struct('NSizeGrid',6,'NStartGrid',0,'SubcarrierSpacing',30,'NCellID',1);
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9; cfg.phy.numerology.scs_kHz=30;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A','delaySpread_s',30e-9, ...
    'doppler_Hz',70,'normalizeChannelOutputs',false);
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
s=struct('TTI',1,'GrantsDL',struct([]),'GrantsUL',struct([]), ...
    'GrantCellsDL',[],'GrantCellsUL',[],'LargeScaleState',struct('Pathloss_dB',80));
for nrb=[6 273]
    cfg.phy.carrier.NSizeGrid=nrb;
    provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
    s.TTI=1; provider.commitSlotPopulation(s);
    if nrb==6
        reject(@()provider.receiveInterferenceWindow(1,1), ...
            'sixgr:abstraction:ReceiveWindowNotAvailable');
        s.TTI=2; provider.commitSlotPopulation(s);
        [rows,e]=provider.receiveInterferenceWindow(1,1);
        assert(numel(rows)==2 && e.ObservationTTI==1 && e.RequiredCommittedThroughTTI==2 && ...
            e.ReadAtCommittedTTI==2 && ~e.WaveformMeasured && ~e.ControlRSInterferenceIncluded);
    else
        [rows,e]=provider.receiveInterferenceWindow(1,0);
        assert(isscalar(rows) && e.RequiredFollowingSlots==0);
        reject(@()provider.receiveInterferenceWindow(1,1), ...
            'sixgr:abstraction:ReceiveWindowRetention');
    end
end
% Actual committed grant binding: an interior symbol is available now;
% the narrow-grid last symbol requires a committed following population.
for nrb=[6 273]
    cfg.phy.carrier.NSizeGrid=nrb;
    provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
    s.TTI=1; s.GrantsDL=struct([]); s.GrantCellsDL=[];
    provider.commitSlotPopulation(s);
    middle=struct('RNTI',1,'PRBSet',0,'SymbolAllocation',[6 1]);
    last=struct('RNTI',2,'PRBSet',1,'SymbolAllocation',[13 1]);
    s.TTI=2; s.GrantsDL=[middle last]; s.GrantCellsDL=[1 2];
    provider.commitSlotPopulation(s);
    ctx=struct('TTI',2,'Direction',"DL",'Grant',middle,'ServingCellID',1);
    [~,e]=provider.receiveGrantWindow(ctx);
    assert(isequal(e.TTIs,2) && e.ReceiveSlotSupport.RequiredFollowingSlots==0 && e.DesiredGrantIndex==1 && ...
        e.DesiredServingCellID==1 && ~e.ResidualISIICIIncluded);
    bad=ctx; bad.Grant.SymbolAllocation=[5 1];
    reject(@()provider.receiveGrantWindow(bad),'sixgr:abstraction:NetworkPopulation');
    bad=ctx; bad.ServingCellID=2;
    reject(@()provider.receiveGrantWindow(bad),'sixgr:abstraction:NetworkPopulation');
    ctx.Grant=last; ctx.ServingCellID=2;
    reference=struct('TTI',2,'Direction',"DL",'UEIndex',2,'ServingCellID',2);
    referenceCoords=[12 13;13 13];
    [ready,referenceSupport]=provider.referenceReceptionAvailability(reference,referenceCoords);
    assert(ready==(nrb==273) && referenceSupport.RequiredCommittedThroughTTI==2+double(nrb==6));
    if nrb==6
        reject(@()provider.receiveGrantWindow(ctx),'sixgr:abstraction:ReceiveWindowNotAvailable');
        reject(@()provider.evaluateReferenceInterference(reference,referenceCoords), ...
            'sixgr:abstraction:ReceiveWindowNotAvailable');
        s.TTI=3; s.GrantsDL=struct([]); s.GrantCellsDL=[];
        provider.commitSlotPopulation(s);
    end
    assert(provider.referenceReceptionAvailability(reference,referenceCoords));
    reject(@()provider.referenceReceptionAvailability(reference,[12 14]), ...
        'sixgr:abstraction:NetworkAllocation');
    reject(@()provider.referenceReceptionAvailability(reference,[12 13;12 13]), ...
        'sixgr:abstraction:NetworkAllocation');
    [~,e]=provider.receiveGrantWindow(ctx);
    assert(e.ReceiveSlotSupport.RequiredFollowingSlots==double(nrb==6) && ...
        e.DesiredGrantIndex==2 && e.DesiredServingCellID==2);
end
fprintf('SLS_NETWORK_RECEIVE_WINDOW_PASS native_filter_capacity=1 narrow_and_100mhz=1 qualification=0\n');
ok=true;
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
