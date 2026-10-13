function ok=testSLSNativePUCCHEmission()
% Native TX/power conversion only. Not detector or SLS study qualification.
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/validation/sls_pucch_two_port_spatial_vector.yaml');
for format=0:4
    count=20; if format<=1, count=2; end
    f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,int8(mod((0:count-1).',2)));
    [f.Assignment,spatial]=sixgr.system.abstraction.bindConfiguredPUCCHSpatialVector(cfg,f.Assignment);
    repeated=sixgr.system.abstraction.bindConfiguredPUCCHSpatialVector(cfg,f.Assignment);
    assert(repeated.Digest==f.Assignment.Digest,'Repeated binding must be idempotent.');
    W=spatial.Precoder;
    b=struct('AbsoluteSlot0',0,'UEIndex',f.Assignment.Data.UEID, ...
        'RNTI',f.Assignment.Data.RNTI,'ServingCellID',f.Assignment.Data.ServingCell, ...
        'Precoder',W,'SpatialStateDigest',f.Assignment.SpatialRelationState.Digest, ...
        'SourceClassification',"declared_component_fixture_not_study_result");
    [e,tx]=sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,b);
    assert(e.NativeWaveformExecuted && ~e.PhysicalReceptionQualified && ...
        ~e.RFImpairmentsApplied && ~e.ElementPatternsApplied && ...
        e.SourceClassification==b.SourceClassification);
    K=12*f.Carrier.NSizeGrid; L=f.Carrier.SymbolsPerSlot;
    indices=e.Coordinates0Based(:,1)+1+K*e.Coordinates0Based(:,2);
    reconstructed=complex(zeros(K*L,1)); reconstructed(indices)=e.Symbols;
    assert(isequal(reshape(reconstructed,K,L),tx.Grid));
    assert(isequal(sort(double([tx.PUCCHIndices(:);tx.DMRSIndices(:)])),sort(indices)), ...
        'Emit actual data and DMRS REs, not the reserved PRB footprint.');
    if format==4
        assert(any(e.Symbols==0), ...
            'This deterministic format-4 case must retain its zero-valued mapped REs.');
    end
    resource=f.Assignment.Resource.Data;
    active=resource.StartSymbol+(0:resource.NumSymbols-1);
    perSymbol=accumarray(e.Coordinates0Based(:,2)+1, ...
        sum(abs(e.Symbols*W.').^2,2).*e.TransmitPowerPerRE_W,[L 1]);
    assert(abs(mean(perSymbol(active+1))/e.AppliedTotalPower_W-1)<1e-12);
    assert(isequal(tx.AntennaWaveform,tx.Waveform*W.'));
    % Independent useful-sample energy for each symbol catches duty-factor,
    % mW/W, port-count and per-symbol normalization errors.
    cp=tx.OFDMInfo.CyclicPrefixLengths; nfft=tx.OFDMInfo.Nfft; offset=0;
    for symbol=0:L-1
        rows=offset+cp(symbol+1)+(1:nfft);
        sampleWatts=mean(sum(abs(tx.AntennaWaveform(rows,:)).^2,2))/1000;
        assert(abs(sampleWatts-perSymbol(symbol+1))<1e-9*e.AppliedTotalPower_W);
        offset=offset+cp(symbol+1)+nfft;
    end
    again=sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,b);
    assert(again.SHA256==e.SHA256,'Same source must produce identical emission identity.');
    wrong=b; wrong.Precoder=2*W;
    reject(@()sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,wrong), ...
        'sixgr:abstraction:PUCCHEmissionPrecoder');
    wrong=b; wrong.SpatialStateDigest="wrong_spatial_state";
    reject(@()sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,wrong), ...
        'sixgr:abstraction:PUCCHEmissionSpatialBinding');
    wrong=b; wrong.AbsoluteSlot0=1;
    reject(@()sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,wrong), ...
        'sixgr:abstraction:PUCCHEmissionIdentity');
    wrong=b; wrong.RNTI=wrong.RNTI+1;
    reject(@()sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,wrong), ...
        'sixgr:abstraction:PUCCHEmissionIdentity');
    wrong=b; wrong.Precoder=conj(W);
    reject(@()sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,wrong), ...
        'sixgr:abstraction:PUCCHEmissionSpatialBinding');
end
owned=b;
owned.Obligation=struct('ResourceID',"native_fixture_obligation", ...
    'AbsoluteSlot0',0,'UEIndex',b.UEIndex,'RNTI',b.RNTI,'CellID',b.ServingCellID, ...
    'Transport',"PUCCH",'ContextDigest',"independent_receiver_context");
bound=sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,owned);
assert(bound.ObligationID==owned.Obligation.ResourceID && strlength(bound.ObligationSHA256)==64);
changed=owned; changed.Obligation.ContextDigest="different_valid_receiver_hypothesis";
other=sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,changed);
assert(other.ObligationSHA256~=bound.ObligationSHA256 && other.SHA256~=bound.SHA256 && ...
    other.WaveformSHA256==bound.WaveformSHA256 && isequal(other.Symbols,bound.Symbols), ...
    'Independent receiver lineage must not construct or alter transmitter bits.');
changed=owned; changed.Obligation.RNTI=b.RNTI+1;
reject(@()sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,changed), ...
    'sixgr:abstraction:PUCCHEmissionObligation');
changed=b; changed.SourceClassification="modeled_SLS_ideal_delayed_control";
reject(@()sixgr.system.abstraction.executePUCCHEmission(f.Carrier,f.Assignment,f.Report,changed), ...
    'sixgr:abstraction:PUCCHEmissionObligation');
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.spatialVectorCatalog.BeamID=1;
reject(@()sixgr.system.abstraction.bindConfiguredPUCCHSpatialVector(bad,f.Assignment), ...
    'sixgr:abstraction:PUCCHEmissionSpatialBinding');
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.spatialVectorCatalog.ConfigurationEpoch=2;
reject(@()sixgr.system.abstraction.bindConfiguredPUCCHSpatialVector(bad,f.Assignment), ...
    'sixgr:abstraction:PUCCHEmissionSpatialBinding');
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.spatialVectorCatalog.PrecoderReal=[1 1];
reject(@()sixgr.system.abstraction.bindConfiguredPUCCHSpatialVector(bad,f.Assignment), ...
    'sixgr:abstraction:PUCCHEmissionSpatialBinding');
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.spatialVectorCatalog.PrecoderImag= ...
    -bad.system.linkAbstraction.dynamicPUCCH.spatialVectorCatalog.PrecoderImag;
reject(@()sixgr.system.abstraction.bindConfiguredPUCCHSpatialVector(bad,f.Assignment), ...
    'sixgr:abstraction:PUCCHEmissionSpatialBinding');
% An actual normalized transmitter state must never acquire absolute watts.
s=struct('OperatingPointAuthority','configured_occupied_re_esn0', ...
    'ReferenceEnergyPerOccupiedRE',1,'Mu',0,'MRB',f.Assignment.Resource.Data.NumPRBs, ...
    'BandwidthSource','selected_pucch_resource_and_active_carrier_scs', ...
    'P0dBm',NaN,'PathlossdB',NaN,'DeltaFdB',NaN,'DeltaTFdB',NaN, ...
    'ClosedLoopAdjustmentdB',NaN,'PCMAXdBm',NaN,'PathlossReferenceRSID',1, ...
    'TPCCommandSource','not_applied_normalized_fixed_esn0','StateID','normalized_fixture', ...
    'RuntimeMeasuredPathlossUsed',false);
normalized=sixgr.phy.pucch.PUCCHPowerControlState(s);
a=sixgr.phy.pucch.PUCCHTransmissionAssignment(f.Assignment.Data, ...
    f.Assignment.Resource,normalized,f.Assignment.SpatialRelationState);
reject(@()sixgr.system.abstraction.executePUCCHEmission(f.Carrier,a,f.Report,b), ...
    'sixgr:abstraction:PUCCHEmissionAbsolutePower');
fprintf('SLS_NATIVE_PUCCH_EMISSION_PASS formats=5 data_dmrs_power_phase_identity=1\n');
ok=true;
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
