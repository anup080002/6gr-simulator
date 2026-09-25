function ok=testPDCCHChannelEstimateCapture()
% Real receiver Hest capture across full/prefix input and RX dimensions.
% Codec observations below are not main-scheduler or detector qualification.
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
out=fullfile(pwd,'results','lls','pdcch_channel_estimate_capture', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
cfg=sixgr.lls6g.buildInternalConfig(s,out);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,11);
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeSlotStartTime_s',0.010);
bits=int8(mod((0:cfg.phy.pdcch.configuredPayloadBits-1).',2));
p=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',bits,'RNTI',1);
x=p.TransmitSamples;
assert(size(x,2)==1,'Fixture requires one logical PDCCH TX port.');
stream=RandStream('mt19937ar','Seed',9321);
% Two independently observable receive dimensions with different complex gains.
y=x*[1 exp(1i*pi/3)*0.7];
y=y+sqrt(mean(abs(x).^2)/1e4/2)*(randn(stream,size(y))+1i*randn(stream,size(y)));
allRows=table();
for prefix=[false true]
    n=size(y,1); if prefix, n=p.MinimumReceiveSamples; end
    buffer=sixgr.phy.waveform.WaveformObservationBuffer(p.RuntimeStartSample, ...
        p.RuntimeStartSample+n,p.SampleRateHz,2);
    buffer.append(sixgr.phy.waveform.WaveformChunk(y(1:n,:),p.RuntimeStartSample),p.SampleRateHz);
    [rx,info]=sixgr.link.completePDCCHReception(p,buffer);
    assert(rx.Ok && isequal(rx.DCIBits,bits));
    T=sixgr.link.buildPDCCHChannelEstimateTable(rx);
    assert(~isempty(T) && isequal(unique(T.RxPortIndex0),[0;1]));
    assert(all(T.SymbolIndex0<info.DemodulatedSymbols));
    h=rx.ChannelEstimate; K=size(h,1); L=size(h,2); R=size(h,3);
    idx=T.SubcarrierIndex0+1+K*T.SymbolIndex0+K*L*T.RxPortIndex0+K*L*R*T.ReferencePortIndex0;
    assert(isequal(complex(T.HReal,T.HImag),h(idx)));
    % The measured phase difference must survive the capture, not collapse RX ports.
    h1=mean(complex(T.HReal(T.RxPortIndex0==0),T.HImag(T.RxPortIndex0==0)));
    h2=mean(complex(T.HReal(T.RxPortIndex0==1),T.HImag(T.RxPortIndex0==1)));
    assert(abs(angle(h2/h1)-pi/3)<0.1 && abs(abs(h2/h1)-0.7)<0.1);
    failed=rx; failed.Ok=false;
    failedT=sixgr.link.buildPDCCHChannelEstimateTable(failed);
    assert(~any(failedT.ReceiverAccepted) && isequal(failedT.HReal,T.HReal));
    nRows=height(T);
    T.AbsoluteSlot0=repmat(10,nRows,1);
    T.UEIndex=ones(nRows,1); T.ServingCell=ones(nRows,1);
    T.SNR_dB=repmat(40,nRows,1);
    T.ObservationStartSample=repmat(buffer.StartSample,nRows,1);
    T.ObservationEndSampleExclusive=T.ObservationStartSample+n;
    T.GrantDirection=repmat("DL",nRows,1);
    if isempty(allRows), allRows=T; else, allRows=[allRows;T]; end %#ok<AGROW>
end
art=sixgr.report.exportPDCCHChannelEstimates(out,allRows,true);
csv=readtable(art.CSVPath,'TextType','string');
assert(height(csv)==height(allRows));
assert(max(abs(csv.HReal-allRows.HReal))<1e-12 && max(abs(csv.HImag-allRows.HImag))<1e-12);
assert(numel(art.ImagePaths)==1 && isfile(art.ImagePaths(1)));
bad=allRows; bad.Magnitude(1)=bad.Magnitude(1)+1;
try
    sixgr.report.exportPDCCHChannelEstimates(out,bad,false);
    error('TEST:ExpectedError','Expected inconsistent complex evidence rejection.');
catch ex
    assert(strcmp(ex.identifier,'sixgr:report:InvalidPDCCHChannelEvidence'));
end
assert(testPDCCHRuntimeReceptionIntegrity());
ok=true;
fprintf('PDCCH_CHANNEL_ESTIMATE_CAPTURE_PASS rows=%d output=%s\n',height(allRows),out);
end
