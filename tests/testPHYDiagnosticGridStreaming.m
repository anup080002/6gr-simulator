function ok=testPHYDiagnosticGridStreaming()
% Declared array/export fixtures, NOT decoded PHY or statistical evidence.
setup6GRSimToolkit('Verbose',false);
[cfg,tx,rxWave,rx,points,context]=fixture();
small=sixgr.link.buildPHYSignalDiagnosticSnapshot(cfg,"UL",tx,rxWave,rx,points,context);
assert(small.Available && small.SourceTableComplete);
mask=small.SourceTable.Panel=="channel_estimate_grid";
expected=small.SourceTable(mask,:);
grid=sixgr.link.PHYDiagnosticChannelGrid.pack(rx.ChannelEstimate,expected(1,:),expected.GridSHA256(1));
parts=cell(grid.Shape(3)*grid.Shape(4),1); at=0;
for txIndex=1:grid.Shape(4)
    for rxIndex=1:grid.Shape(3)
        at=at+1; parts{at}=sixgr.link.PHYDiagnosticChannelGrid.rows(grid,rxIndex,txIndex);
    end
end
assert(isequaln(vertcat(parts{:}),expected), ...
    'test:GridChunkSemantics','Every old inline column, coordinate, zero and phase segment must match.');
streamed=small; streamed.SourceTable(mask,:)=[];
streamed.DeferredChannelGrid=grid; streamed.SourceTableComplete=false;
sixgr.link.PHYDiagnosticChannelGrid.validate(grid,streamed);
root=fullfile(pwd,'results','diagnostics','phy_grid_streaming', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
a=sixgr.truth.exportPHYSignalDiagnostic(fullfile(root,'inline'),cfg,struct('UL',small),false);
b=sixgr.truth.exportPHYSignalDiagnostic(fullfile(root,'streamed'),cfg,struct('UL',streamed),false);
assert(a.ULAvailable && b.ULAvailable && a.SourceTableComplete && ~b.SourceTableComplete && ...
    a.SourceRowCount==b.SourceRowCount && b.DeferredChannelGridRowCount==numel(rx.ChannelEstimate));
assert(strcmp(sixgr.util.sha256File(a.SourceCSV),sixgr.util.sha256File(b.SourceCSV)), ...
    'test:GridCSVChanged','Chunked and inline canonical CSV bytes must match.');
before=sixgr.util.sha256File(b.SourceCSV);
corrupt=streamed; corrupt.DeferredChannelGrid.Tensor(1)=corrupt.DeferredChannelGrid.Tensor(1)+1;
try
    sixgr.truth.exportPHYSignalDiagnostic(fullfile(root,'streamed'),cfg,struct('UL',corrupt),false);
    error('test:MissingGridIntegrityRejection','Corrupt measured coefficients must be rejected.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:link:PHYDiagnosticGridIntegrity'));
end
assert(strcmp(before,sixgr.util.sha256File(b.SourceCSV)), ...
    'test:GridFailedPublicationOverwroteSource','Keep the prior complete CSV on an interrupted publication.');
missing=rmfield(streamed,'DeferredChannelGrid');
try
    sixgr.truth.exportPHYSignalDiagnostic(fullfile(root,'streamed'),cfg,struct('UL',missing),false);
    error('test:MissingGridPopulationRejection','Missing deferred values cannot become an available source.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:PHYDiagnosticMissingDeferredGrid'));
end
assert(strcmp(before,sixgr.util.sha256File(b.SourceCSV)));

% Post-receiver augmentation must bind the same executed-link provenance
% to deferred and inline coefficients, not just to the small display panels.
aug=context; aug.RuntimeChannelPathGains=complex([1;.9]);
aug.RuntimeChannelPathGainSampleTimes_s=[0;1/context.SampleRate_Hz];
aug.RuntimeChannelPathDelays_s=0;
aug.RuntimeChannelLinkKey="declared_export_fixture_link";
aug.RuntimeChannelStateKey="declared_export_fixture_state";
inlineAug=sixgr.link.buildPHYSignalDiagnosticSnapshot(cfg,"UL",struct(),[],struct(),table(),aug,small);
streamAug=sixgr.link.buildPHYSignalDiagnosticSnapshot(cfg,"UL",struct(),[],struct(),table(),aug,streamed);
aa=sixgr.truth.exportPHYSignalDiagnostic(fullfile(root,'inline_augmented'),cfg,struct('UL',inlineAug),false);
bb=sixgr.truth.exportPHYSignalDiagnostic(fullfile(root,'streamed_augmented'),cfg,struct('UL',streamAug),false);
assert(strcmp(sixgr.util.sha256File(aa.SourceCSV),sixgr.util.sha256File(bb.SourceCSV)));
again=sixgr.link.buildPHYSignalDiagnosticSnapshot(cfg,"UL",struct(),[],struct(),table(),aug,streamAug);
assert(isequaln(streamAug,again),'test:DeferredGridAugmentationNotIdempotent');

% Trigger the production representation branch without allocating a giant
% wide table. The full H4 273-PRB, 64-RX/four-port population is retained.
shape=[3276 14 64 4]; n=prod(shape);
h=reshape(exp(1i*(0:n-1)'/127),shape); h(3,2,2,3)=0;
rx.ChannelEstimate=h;
large=sixgr.link.buildPHYSignalDiagnosticSnapshot(cfg,"UL",tx,rxWave,rx,points,context);
assert(large.Available && ~large.SourceTableComplete && ...
    ~any(large.SourceTable.Panel=="channel_estimate_grid") && ...
    large.DeferredChannelGrid.RowCount==11741184 && ...
    isequaln(large.DeferredChannelGrid.Tensor,h) && ...
    large.SourceRowCount==height(large.SourceTable)+n);
bytes=whos('large');
assert(bytes.bytes<350*1024^2,'test:DiagnosticGridMemoryExpansion', ...
    'Retain a compact tensor and bounded panels, not millions of replicated metadata rows.');
sixgr.link.PHYDiagnosticChannelGrid.validate(large.DeferredChannelGrid,large);
last=sixgr.link.PHYDiagnosticChannelGrid.rows(large.DeferredChannelGrid,64,4);
assert(height(last)==3276*14 && last.PointIndex(end)==n && ...
    isequal(complex(last.IValue,last.QValue),reshape(h(:,:,64,4),[],1)));
sixgr.util.jsonWrite(fullfile(root,'receipt.json'),struct('Passed',true, ...
    'Scope',"declared_array_serialization_regression_not_physical_qualification", ...
    'AllCSVBytesEqual',true,'FullH4GridValuesRetained',n,'SnapshotWorkspaceBytes',bytes.bytes, ...
    'ScenarioAccepted',false));
fprintf('PHY_GRID_STREAMING_PASS folder=%s values=%d snapshot_bytes=%d\n',root,n,bytes.bytes);
ok=true;
end

function [cfg,tx,rxWave,rx,points,context]=fixture()
cfg=struct('run',struct('runTag','declared_grid_export_fixture'), ...
    'outputs',struct('phySignalDiagnosticEnabled',true,'phySignalDiagnosticFullChannelGrid',true, ...
    'phySignalDiagnosticWaveformSamples',256,'phySignalDiagnosticFFTLength',256, ...
    'phySignalDiagnosticChannelPoints',64,'phySignalDiagnosticConstellationPoints',64), ...
    'channel',struct('model','CDL-C','cdlProfile','CDL-C','carrierFrequencyHz',4e9), ...
    'frame',struct('scs_kHz',30),'phy',struct('rnti',4660));
wave=exp(1i*(0:511)'/13);
tx=struct('Waveform',wave,'OFDMInfo',struct('SampleRate',122.88e6,'Nfft',16, ...
    'CyclicPrefixLengths',repmat(4,1,14),'SymbolLengths',repmat(20,1,14)), ...
    'Carrier',struct('NCellID',1,'SubcarrierSpacing',30,'NStartGrid',0));
rxWave=.8*wave;
h=reshape(exp(1i*(0:72*14*2*2-1)'/9),72,14,2,2);
h(3:5,2,1,1)=0; h(6,3,2,2)=complex(NaN,0);
rx=struct('ChannelEstimate',h,'ChannelEstimateSource','pusch_dmrs_channel_estimate', ...
    'ChannelEstimateMethod','nrChannelEstimate','PUSCHRxSymbolsForEvidence',wave(1:96), ...
    'PostEqSINR_dB',20,'PostEqSINRSource','declared_array_fixture','CRCPass',true);
points=table(real(wave(1:64)),imag(wave(1:64)),real(wave(1:64)),imag(wave(1:64)), ...
    ones(64,1),repmat("QPSK",64,1),repmat("real_lls_evidence",64,1), ...
    'VariableNames',{'ReferenceSymbolReal','ReferenceSymbolImag','EqualizedReal','EqualizedImag', ...
    'LayerIndex','Modulation','truth_status'});
context=struct('Frame',1,'Slot',15,'UEIndex',1,'RNTI',4660,'TBId','declared_array_fixture', ...
    'LayerIndex',1,'Layers',4,'Modulation','QPSK','MCSIndex',0,'ConfiguredSNR_dB',40, ...
    'ConfiguredSNRSource','declared_array_fixture','PostEqSINR_dB',20, ...
    'PostEqSINRSource','declared_array_fixture','PostEqSINRValueRole','receiver_derived', ...
    'EVM_rms',.01,'CRCPass',true,'SampleRate_Hz',122.88e6);
end
