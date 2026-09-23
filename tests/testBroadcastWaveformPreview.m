function ok=testBroadcastWaveformPreview()
% Exact capture/publication contract; declared samples are not RF qualification.
fs=7680000; first=76800; n=513;
x=complex(reshape(1:2*n,n,2),reshape(2*n+1:4*n,n,2));
y=complex(reshape(1:4*n,n,4),-reshape(1:4*n,n,4))/7;
tx=buffer(x,first,fs); rx=buffer(y,first,fs);
T=sixgr.link.buildBroadcastWaveformPreview(tx,rx,-30,2,11,1,1);
assert(height(T)==4*256 && all(T.ObservationKind=="broadcast_window"));
for k=1:4
    rows=T(T.RxAntennaIndex==k,:); idx=rows.SampleIndex;
    assert(isequal(rows.RxReal,real(y(idx,k))) && isequal(rows.RxImag,imag(y(idx,k))));
    assert(isequal(rows.AbsoluteSampleIndex,first+idx-1));
    assert(isequal(rows.Time_s,(first+idx-1)/fs));
    if k<=2
        assert(all(rows.TxAntennaIndex==k) && isequal(rows.TxReal,real(x(idx,k))));
    else
        assert(all(isnan(rows.TxAntennaIndex)) && all(isnan(rows.TxReal)));
    end
end
state=struct('SharedWaveformStream',sixgr.truth.CoupledWaveformStream(), ...
    'SharedBroadcastWaveformPreviewTable',T);
assert(isequaln(sixgr.truth.finalCoupledWaveformPreview(state,table()),T));
reject(@()sixgr.truth.finalCoupledWaveformPreview(state,table(1,'VariableNames',{'Slot'})), ...
    'sixgr:truth:MissingFinalSharedWaveformPreview');
bad=state; bad.SharedBroadcastWaveformPreviewTable.ObservationKind(:)="PDSCH";
reject(@()sixgr.truth.finalCoupledWaveformPreview(bad), ...
    'sixgr:truth:MissingFinalSharedWaveformPreview');
bad=state; bad.SharedBroadcastWaveformPreviewTable.Source(:)="synthetic";
reject(@()sixgr.truth.finalCoupledWaveformPreview(bad), ...
    'sixgr:truth:MissingFinalSharedWaveformPreview');
reject(@()sixgr.link.buildBroadcastWaveformPreview(tx,buffer(y,first+1,fs),-30,2,11,1,1), ...
    'sixgr:link:BroadcastPreviewClockMismatch');
incomplete=sixgr.phy.waveform.WaveformObservationBuffer(first,first+n,fs,4);
reject(@()sixgr.link.buildBroadcastWaveformPreview(tx,incomplete,-30,2,11,1,1), ...
    'WAVEFORM:IncompleteObservation');
folder=tempname(fullfile(pwd,'logs'));
out=sixgr.truth.exportLLSLiveSignalChainTables(folder,table(),table(),struct('WaveformPreviewTable',T));
saved=readtable(out.WaveformPreviewPath,'TextType','string');
assert(height(saved)==height(T) && isequaln(saved.RxReal,T.RxReal));
assert(all(saved.EvidenceScope=="shared_broadcast_observation_not_data_constellation"));
assert(isempty(out.ModulationTrace) && isempty(out.ChannelEstimationTrace));
fprintf('BROADCAST_PREVIEW_CONTRACT_PASS rows=%d branches=4 no_data_rows=1 folder=%s\n',height(T),folder);
ok=true;
end

function b=buffer(x,first,fs)
b=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(x,1),fs,size(x,2));
b.append(sixgr.phy.waveform.WaveformChunk(x,first),fs);
end

function reject(f,id)
try
    f();
catch e
    assert(strcmp(e.identifier,id),'Expected %s, got %s: %s',id,e.identifier,e.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
