function ok=testDataWaveformPreviewPorts()
% Declared arrays test exact serialization, not decoder/RF qualification.
n=513; fs=30.72e6;
tx=complex(reshape(1:4*n,n,4),reshape(4*n+1:8*n,n,4))/97;
rx=complex(reshape(1:2*(n+3),n+3,2),-reshape(1:2*(n+3),n+3,2))/83;
T=sixgr.link.buildWaveformPreviewTable('DL',-10,2,3,tx,rx,fs);
assert(height(T)==4*256 && all(ismember( ...
    ["TxAntennaIndex","RxAntennaIndex","ObservationSampleRateHz"], ...
    string(T.Properties.VariableNames))), ...
    'test:WaveformPortsDiscarded','Every supplied TX/RX waveform column needs explicit retained identity.');
for port=1:4
    rows=T(T.TxAntennaIndex==port,:); index=rows.SampleIndex;
    valid=index<=n;
    assert(isequal(rows.TxReal(valid),real(tx(index(valid),port))) && ...
        isequal(rows.TxImag(valid),imag(tx(index(valid),port))));
    assert(all(isnan(rows.TxReal(~valid))) && all(isnan(rows.TxImag(~valid))));
    assert(all(rows.ObservationSampleRateHz==fs) && isequal(rows.Time_s,(index-1)/fs));
    if port<=2
        assert(all(rows.RxAntennaIndex==port) && ...
            isequal(rows.RxReal,real(rx(index,port))) && ...
            isequal(rows.RxImag,imag(rx(index,port))));
    else
        assert(all(isnan(rows.RxAntennaIndex)) && all(isnan(rows.RxReal)) && all(isnan(rows.RxImag)), ...
            'Absent receive branches must not be synthesized from another antenna.');
    end
end
receiveOnly=sixgr.link.buildWaveformPreviewTable('UL',20,2,3,[],rx,fs);
assert(height(receiveOnly)==2*256 && all(isnan(receiveOnly.TxAntennaIndex)) && ...
    all(isnan(receiveOnly.TxReal)) && isequal(unique(receiveOnly.RxAntennaIndex),[1;2]));
folder=tempname; mkdir(folder); cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
out=sixgr.truth.exportLLSLiveSignalChainTables(folder,table(),table(), ...
    struct('WaveformPreviewTable',T,'FinalSnapshot',true));
saved=sixgr.util.csvReadTable(out.WaveformPreviewPath,'TextType','string');
assert(isequaln(saved,T),'All branch identities and measured values must survive CSV export.');
ok=true;
end
