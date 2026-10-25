function ok=testObservedSSBOnlyREAllocation()
% Actual native TX and committed-buffer fixture; no channel/RX qualification.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','observed_ssb_only',char(java.util.UUID.randomUUID()));
mkdir(folder);
for scenario=["lls_causal_tdd_connected_feedback_fixture.yaml","lls_causal_access_to_data_wiring.yaml"]
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',scenario));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    p=sixgr.link.prepareCellSearchBroadcast(cfg,true,'RuntimeSlot',20,'Content','SSB_MIB');
    o=sixgr.phy.waveform.WaveformObservationBuffer(p.BroadcastStartSample, ...
        p.BroadcastStartSample+p.NumSamples,p.SampleRateHz,size(p.TransmitSamples,2));
    o.append(sixgr.phy.waveform.WaveformChunk(p.TransmitSamples,p.BroadcastStartSample),p.SampleRateHz);
    hash=o.sampleHash();
    T=sixgr.truth.buildObservedBroadcastREAllocation(p,o,1);
    assert(~isempty(T) && all(T.channel=="SSB") && all(isnan(T.rnti)));
    assert(all(ismember(["PSS","SSS","PBCH","PBCH-DMRS"],unique(T.component))));
    assert(sum(T.re_count)==nnz(p.Tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid));
    assert(all(T.authority=="executed_ssb_mib_only_tx_grid_and_committed_waveform_interval"));
    assert(all(T.absolute_slot>=20) && all(T.sfn==mod(floor(T.absolute_slot/p.Tx.Carrier.SlotsPerFrame),1024)));
    assert(height(sixgr.truth.deduplicateObservedREAllocation([T;T]))==height(T));
    path=fullfile(folder,erase(scenario,'.yaml')+'.csv');
    sixgr.util.csvWriteTable(path,T);
    R=sixgr.util.csvReadTable(path,'TextType','string');
    assert(height(R)==height(T) && isequal(R.channel,T.channel) && ...
        isequal(R.re_count,T.re_count) && isequal(R.transmit_grid_sha256,T.transmit_grid_sha256));
    bad=p; bad.Tx=rmfield(bad.Tx,'Content'); localReject(bad,o);
    bad=p; bad.WaveformContent="ssb_mib_sib1_composite"; localReject(bad,o);
    bad=p; bad.Tx.SIB1Transmissions=struct('declared',true); localReject(bad,o);
    bad=p; bad.Tx.SIB1Transmissions=[]; localReject(bad,o);
    bad=p; bad.Tx.SIB1EmissionIncluded=true; localReject(bad,o);
    bad=p; bad.Tx.SIB1Grid=zeros(1); localReject(bad,o);
    % Removing all explicit scope does not legalize a composite's absent SI.
    bad=p; bad=rmfield(bad,{'Content','WaveformContent'});
    bad.Tx=rmfield(bad.Tx,{'Content','WaveformContent'});
    bad.Tx.WaveformContent="ssb_mib_sib1_composite";
    localReject(bad,o,'sixgr:phy:broadcast:MissingSIB1Transmissions');
    assert(o.sampleHash()==hash && isequal(o.readComplete(),p.TransmitSamples));
end
fprintf('SSB_ONLY_OBSERVED_RE_PASS native_TX_export_only %s\n',folder);
ok=true;
end

function localReject(p,o,id)
if nargin<3, id='sixgr:truth:BroadcastContentMismatch'; end
try
    sixgr.truth.buildObservedBroadcastREAllocation(p,o,1);
catch ex
    assert(strcmp(ex.identifier,id),'Expected %s, got %s: %s',id,ex.identifier,ex.message);
    return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
