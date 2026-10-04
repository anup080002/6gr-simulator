function ok=testSLSExactDataREPopulation()
% Native grant mapping + selective network covariance, not BLER qualification.
cfg=sixgr.config.defaultConfig();
policy=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg=sixgr.util.mergeStruct(cfg,policy);
cfg.run.seed=113; cfg.run.executionID='exact_resource_population';
cfg.run.pdschExecutionProfile='phy_calibration';
cfg.run.puschExecutionProfile='phy_calibration';
cfg.phy.carrier.NSizeGrid=24; cfg.phy.carrier.NStartGrid=0;
cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.numerology.scs_kHz=30;
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A', ...
    'delaySpread_s',30e-9,'doppler_Hz',0,'normalizeChannelOutputs',false,'awgnOnly',false);
cfg.channel.fading.enable=true; cfg.channel.fading.maxDoppler_Hz=0;
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=2;
cfg.channel.nTxAnt=2; cfg.channel.nRxAnt=2;
cfg.scenario.bs.nTxAnt=2; cfg.scenario.ue.nRxAnt=2;
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9;
cfg.scenario.ue.txPower_dBm=23;
cfg.antenna.bs.numElements=2; cfg.antenna.bs.numRFChains=2;
cfg.antenna.ue.numElements=2; cfg.antenna.ue.numRFChains=2;
cfg.phy.beamManagement.hybridBeamformingEnabled=false;
cfg.phy.csirs.enable=false; cfg.phy.trs.enable=false;
cfg.phy.ssb.enable=false; cfg.phy.csiim.enable=false;
cfg.phy.ptrs.enable=false;
mcs=sixgr.link.resolveMCSProfile('qam64_table1',1);
assert(mcs.Valid);
for name=["pdsch","pusch"]
    cfg.phy.(name).numLayers=2; cfg.phy.(name).nLayers=2;
    cfg.phy.(name).numPorts=2; cfg.phy.(name).nPorts=2;
    cfg.phy.(name).modulation='QPSK'; cfg.phy.(name).codeRate=mcs.TargetCodeRate;
    cfg.phy.(name).mcsTable='qam64_table1'; cfg.phy.(name).mcsIndex=1;
    cfg.phy.(name).dmrs.portSet=0:1;
    cfg.phy.(name).enablePTRS=false;
end
cfg.phy.pusch.transformPrecoding=false;
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
cfg.system.linkAbstraction.networkSpatial.sinrResourcePopulation='native_shared_channel_data_re';
large=struct('Pathloss_dB',[80 90;85 80],'TxPower_dBm',30*ones(2));
for direction=["DL","UL"]
    g=makeGrant(cfg,direction,1,0:5,[2 10]);
    [map,carrier,native]=sixgr.system.abstraction.scheduledDataREMap(cfg,g,0);
    projected=sixgr.phy.grant.applyPHYGrantToConfig(cfg,g.PHYGrant);
    if direction=="DL"
        tx=sixgr.phy.dl.PDSCH_Tx(projected,'Carrier',carrier,'PDSCH',native,'TargetCodeRate',mcs.TargetCodeRate);
        transmitted=tx.PDSCHLayerIndices;
    else
        tx=sixgr.phy.ul.PUSCH_Tx(projected,'Carrier',carrier,'PUSCH',native,'TargetCodeRate',mcs.TargetCodeRate);
        transmitted=tx.PUSCHLayerIndices;
    end
    assert(isequal(double(transmitted),map.LayerIndices1Based), ...
        'Network mapping must match actual coded waveform layer indices.');
    % Different allocation duration changes actual pilot locations, not only
    % the rectangle: compare intersections against native indices directly.
    h=makeGrant(cfg,direction,2,3:8,[2 6]);
    other=sixgr.system.abstraction.scheduledDataREMap(cfg,h,0);
    p=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
    ctx=struct('TTI',1,'Direction',direction,'Grant',g,'ServingCellID',1);
    s=struct('TTI',1,'GrantsDL',struct([]),'GrantsUL',struct([]), ...
        'GrantCellsDL',[],'GrantCellsUL',[],'LargeScaleState',large);
    s.("Grants"+direction)=g; s.("GrantCells"+direction)=1;
    a=p.evaluate(ctx,s);
    assert(isequal(a.Coordinates0Based,map.Coordinates0Based) && ...
        size(a.Channel,3)==map.PhysicalRECount && all(a.ActiveInterferersPerRE==0));
    s.("Grants"+direction)=[g h]; s.("GrantCells"+direction)=[1 2];
    b=p.evaluate(ctx,s);
    mask=ismember(map.Coordinates0Based,other.Coordinates0Based,'rows');
    assert(any(mask) && any(~mask) && isequal(b.ActiveInterferersPerRE,double(mask)));
    assert(isequal(b.ExternalCovariance(:,:,~mask),a.ExternalCovariance(:,:,~mask)));
    assert(~b.ReferenceSignalInterferenceQualified && ~b.CommonControlInterferenceQualified && ...
        contains(b.SourceClassification,'not_waveform_measurement'));
    keyCtx=ctx; keyCtx.Grant.TBSBits=double(tx.TransportBlockSize);
    keyCtx.TBSBits=double(tx.TransportBlockSize); keyCtx.NumLayers=2;
    keyCtx.TargetCodeRate=mcs.TargetCodeRate; keyCtx.SCS_kHz=30; keyCtx.ChannelModel='TDL-A';
    key=sixgr.system.CalibratedLinkPHY.calibrationKey(keyCtx,b);
    legacy=rmfield(b,{'DataREAllocationIdentity','DataREAllocationSHA256'});
    reject(@()sixgr.system.CalibratedLinkPHY.calibrationKey(keyCtx,legacy), ...
        'sixgr:abstraction:DataREAllocationIdentity');
    legacy.ResourcePopulation='allocated_prb_symbol_footprint_including_pilots';
    oldKey=sixgr.system.CalibratedLinkPHY.calibrationKey(keyCtx,legacy);
    assert(key.AllocationSHA256~=oldKey.AllocationSHA256, ...
        'Native data population must not reuse the rectangle calibration identity.');
    tampered=b; tampered.DataREAllocationIdentity.PhysicalRECount=1;
    reject(@()sixgr.system.CalibratedLinkPHY.calibrationKey(keyCtx,tampered), ...
        'sixgr:abstraction:DataREAllocationIdentity');
    if direction=="DL"
        cross=p.channel(direction,1,2,0,large,map.Coordinates0Based(mask,:));
        power=1/(12*carrier.NSizeGrid);
    else
        cross=p.channel(direction,2,1,0,large,map.Coordinates0Based(mask,:));
        power=10^((23-30)/10)/(12*numel(h.PRBSet));
    end
    W=h.PHYGrant.PrecodingState.MatrixPorts;
    W=W/norm(W,'fro'); ix=find(mask);
    for k=1:numel(ix)
        effective=cross(:,:,k)*W;
        expected=a.ExternalCovariance(:,:,ix(k))+power*(effective*effective');
        assert(norm(b.ExternalCovariance(:,:,ix(k))-expected,'fro')<1e-20);
    end
    bad=g; bad.PRBSet=1:6;
    reject(@()sixgr.system.abstraction.scheduledDataREMap(cfg,bad,0),'sixgr:abstraction:DataREGrantIdentity');
    reject(@()sixgr.system.abstraction.scheduledDataREMap(cfg,g,1),'sixgr:abstraction:DataREGrantIdentity');
end
ok=true;
fprintf('SLS_EXACT_DATA_RE_POPULATION_PASS DL_UL_native_TX_identity=1 partial_overlap_covariance=1\n');
end

function g=makeGrant(cfg,direction,rnti,prbs,symbols)
g=struct('Direction',char(direction),'Frame',0,'Slot',0,'ScheduledAbsoluteSlot',0, ...
    'RNTI',rnti,'UEIndex',rnti,'ServingCell',rnti,'PRBSet',prbs, ...
    'SymbolAllocation',symbols,'Modulation','QPSK','NumLayers',2,'Layers',2, ...
    'NumLogicalPorts',2,'NumRFChains',2,'TargetCodeRate',cfg.phy.pdsch.codeRate, ...
    'MCSIndex',1,'MCSTable','qam64_table1', ...
    'PrecodingMatrixLogicalPorts',eye(2)/sqrt(2),'PrecodingMatrix',eye(2)/sqrt(2), ...
    'PrecoderNormalizationConvention','unit_frobenius','PrecoderSource','numerical_contract_fixture');
g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,g,'Frame',0,'Slot',0);
end

function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s',id);
end
