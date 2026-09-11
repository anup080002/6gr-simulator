function ok=testObservedBroadcastREAllocation()
% Actual TX/grid and committed-buffer fixture, not a full access/main run.
setup6GRSimToolkit('Verbose',false);
for scenario=["lls_causal_tdd_connected_feedback_fixture.yaml","lls_causal_access_to_data_wiring.yaml"]
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',scenario));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    p=sixgr.link.prepareCellSearchBroadcast(cfg,true);
    carrier=p.Tx.Carrier; base=20;
    first=sixgr.phy.frame.slotStartSample(carrier,base,p.SampleRateHz);
    observation=localObservation(p,first,true);
    T=sixgr.truth.buildObservedBroadcastREAllocation(p,observation,1);
    ssb=T(T.channel=="SSB",:); si=T(T.channel~="SSB",:);
    assert(~isempty(ssb) && all(ismember(["PSS","SSS","PBCH","PBCH-DMRS"],unique(ssb.component))));
    assert(all(ismember(["PDCCH","PDSCH"],unique(si.channel))) && all(si.rnti==65535));
    assert(all(T.direction=="DL") && all(isnan(T.ue_id)) && all(T.absolute_slot>=base));
    assert(all(T.symbol_index>=0 & T.symbol_index<carrier.SymbolsPerSlot));
    assert(all(T.subcarrier_start+T.subcarrier_count<=carrier.NSizeGrid*12));
    assert(all(T.port_index<size(p.TransmitSamples,2)) && ...
        numel(unique(ssb.ssb_index0))==numel(p.Tx.SSBBurstPlan.ActiveSSBIndices0Based));
    assert(sum(ssb.re_count)==nnz(p.Tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid));
    assert(sum(si.re_count)==nnz(p.Tx.SIB1Grid)*nnz(p.Tx.SIB1SpatialMapping.PrecoderMatrix));
    assert(all(si.absolute_slot==base+p.Tx.SIB1AbsoluteSlot));
    assert(all(T.sfn==floor(T.absolute_slot/(10*carrier.SlotsPerSubframe))));
    replay=sixgr.truth.deduplicateObservedREAllocation([T;T]);
    assert(height(replay)==height(T),'Same cell broadcast must not duplicate per receiving UE.');
    % Independently demodulate the actual per-beam precoded SSB waveform.
    grid=p.Tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid;
    v=p.Tx.SSBInfo.SSBGridValidation;
    low=(v.SSBLowOffsetFromPointAHz-v.CarrierLowOffsetFromPointAHz)/(1000*carrier.SubcarrierSpacing);
    % nrWaveformGenerator applies symbol phase compensation at the declared
    % RF carrier. The independent demodulator must invert that same f0,
    % not its default zero-Hz phase reference. No fitted phase is used.
    actual=nrOFDMDemodulate(carrier,p.Tx.SSBWaveform, ...
        'SampleRate',p.SampleRateHz,'CarrierFrequency',p.Tx.SSBInfo.CarrierFrequency_Hz);
    actual=actual(low+(1:240),1:size(grid,2),:);
    mismatch=norm(actual(:)-grid(:))/norm(grid(:));
    assert(mismatch<1e-10,'Retained spatial grid does not match the actual SSB waveform: %.15g',mismatch);
    localReject(@()sixgr.truth.buildObservedBroadcastREAllocation(p,localObservation(p,first,false),1), ...
        'sixgr:truth:BroadcastGridObservationMismatch');
    localReject(@()sixgr.truth.buildObservedBroadcastREAllocation(p,localObservation(p,first+1,true),1), ...
        'sixgr:truth:BroadcastGridOriginMismatch');
    wrong=p; wrong.Tx.SSBInfo.SSBResourceOwnership.NCellID=carrier.NCellID+1;
    localReject(@()sixgr.truth.buildObservedBroadcastREAllocation(wrong,observation,1), ...
        'sixgr:truth:BroadcastGridPCIMismatch');
    wrong=p; wrong.Tx.SIB1WaveformStartSample=wrong.Tx.SIB1WaveformStartSample+1;
    localReject(@()sixgr.truth.buildObservedBroadcastREAllocation(wrong,observation,1), ...
        'sixgr:truth:SIB1GridTimingMismatch');
    wrong=p;
    dataIndex=double(wrong.Tx.PDSCHTx.ResourcePlan.DataIndices(1))+1;
    wrong.Tx.PDSCHTx.Grid(dataIndex)=wrong.Tx.PDSCHTx.Grid(dataIndex)+1;
    localReject(@()sixgr.truth.buildObservedBroadcastREAllocation(wrong,observation,1), ...
        'sixgr:truth:CanonicalTXGridMismatch');
    fprintf('OBSERVED_BROADCAST_GRID_PASS: %s rows=%d exact waveform grid error=%.3g\n',scenario,height(T),mismatch);
end
ok=true;
end

function o=localObservation(p,first,complete)
o=sixgr.phy.waveform.WaveformObservationBuffer(first,first+p.NumSamples,p.SampleRateHz,size(p.TransmitSamples,2));
if complete
    o.append(sixgr.phy.waveform.WaveformChunk(p.TransmitSamples,first),p.SampleRateHz);
end
end

function localReject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Unexpected failure: %s %s',cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
