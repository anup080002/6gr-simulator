function ok=testResearchIQExport()
% Exact four-port coded IQ versus the previous scaling/quantization contract.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
c=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'tests','fixtures','research_fixed_ports.yaml'));
s=c.toStruct(); state=rng; cleanup=onCleanup(@()rng(state)); %#ok<NASGU>
rng(s.simulation.random_seed,'twister');
tag="iq_export_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
root=fullfile(pwd,'results','component_validation',tag); mkdir(root);
for direction=["DL","UL"]
    if direction=="DL", slot=0; else, slot=4; end
    a=sixgr.phy.research.SharedChannelLink.allocation(s,slot,direction);
    tb=int8(randi([0 1],a.TransportBlockSize,1));
    tx=sixgr.phy.research.SharedChannelLink.transmit(s,slot,tb,direction);
    variance=s.research_awgn_mimo.reference_data_re_power/10^(40/10)/tx.OFDM.SampleToGridNoiseVarianceGain;
    noisy=tx.Waveform+sqrt(variance/2)*(randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
    rx=sixgr.phy.research.SharedChannelLink.receive(s,slot,noisy,direction);
    assert(rx.CRCPass && isequal(rx.TransportBlock,tb));
    for point=["TX","RX"]
        if point=="TX", wave=tx.Waveform; else, wave=noisy; end
        rows=sixgr.phy.research.exportLabIQ(root,wave,a.SampleRateHz, ...
            s.frequency.center_frequency_hz,direction,point,true);
        legacyScale=max(abs([real(wave(:));imag(wave(:))]));
        assert(numel(rows)==4 && all([rows.CommonEndpointFullScale]==legacyScale));
        saved=load(rows(1).RawMAT);
        assert(isequal(saved.Waveform,wave) && saved.SampleRateHz==a.SampleRateHz);
        assert(saved.CenterFrequencyHz==s.frequency.center_frequency_hz && saved.CapturePoint==point);
        expectedRawHash=localReferenceHash(rows(1).RawMAT);
        for port=1:4
            assert(rows(port).RawSHA256==expectedRawHash && ~rows(port).InstrumentImportVerified);
            normalized=wave(:,port)/legacyScale;
            expected=int16(round([real(normalized),imag(normalized)]*32767));
            fid=fopen(rows(port).WIQFile,'r','ieee-le'); assert(fid>=0);
            closeFile=onCleanup(@()fclose(fid)); actual=fread(fid,[2 Inf],'*int16').'; clear closeFile
            assert(isequal(actual,expected));
            assert(rows(port).WIQSHA256==localReferenceHash(rows(port).WIQFile));
            assert(rows(port).VSAMATSHA256==localReferenceHash(rows(port).VSAMATFile));
            vsa=load(rows(port).VSAMATFile);
            assert(isequal(vsa.Y,single(normalized)) && vsa.XDelta==1/a.SampleRateHz);
            assert(vsa.InputCenter==s.frequency.center_frequency_hz && vsa.InputZoom==1 && vsa.XDomain==2);
            assert(rows(port).ClippedComponents==0 && rows(port).QuantizationMaxError<=0.5/32767+eps);
        end
        fprintf('RESEARCH_IQ_EXPORT_ENDPOINT_PASS direction=%s point=%s ports=4 samples=%d exact_WIQ=1 exact_VSA=1\n', ...
            direction,point,size(wave,1));
    end
end
out=run_6g_phy_lls_single(fullfile(pwd,'tests','fixtures','research_four_port_iq.yaml'),root,'clocked');
assert(out.ResultOk && all(out.TrialTable.CRCPass & out.TrialTable.TBExact));
sources=jsondecode(fileread(fullfile(out.RunFolder,'meta','executed_source_hashes.json')));
exporter=string(which('sixgr.phy.research.exportLabIQ'));
sourceIndex=find(string({sources.Path})==exporter);
assert(isscalar(sourceIndex) && string(sources(sourceIndex).SHA256)==sixgr.util.sha256File(exporter));
% Long paths contain many underscores; do not let delimiter inference turn
% this documented comma-separated artifact into an unrelated table schema.
receipt=readtable(fullfile(out.RunFolder,'waveform','iq_manifest.csv'), ...
    'TextType','string','Delimiter',',','ReadVariableNames',true);
assert(height(receipt)==16 && all(receipt.SampleCount==737280));
assert(all(receipt.ClippedComponents==0) && all(receipt.QuantizationMaxError<=0.5/32767+eps));
clock=readtable(fullfile(out.RunFolder,'air_interface','csv','timeline.csv'), ...
    'TextType','string','Delimiter',',','ReadVariableNames',true);
for direction=["DL","UL"]
    raw=load(fullfile(out.RunFolder,'waveform',lower(direction+"_TX"),'raw_iq.mat'));
    assert(isequal(size(raw.Waveform),[737280 4]));
    for k=1:height(clock)
        if ~logical(clock.(direction+"Active")(k))
            assert(all(raw.Waveform(clock.StartSample(k)+1:clock.StopSampleExclusive(k),:)==0,'all'));
        end
    end
    received=load(fullfile(out.RunFolder,'waveform',lower(direction+"_RX"),'raw_iq.mat'));
    assert(isequal(size(received.Waveform),size(raw.Waveform)) && ~isequal(received.Waveform,raw.Waveform));
end
ok=true;
fprintf('RESEARCH_IQ_EXPORT_PASS folder=%s instrument_import_verified=0 full_band_campaign=0\n',root);
end

function value=localReferenceHash(path)
% Independent reference used only on these small test artifacts.
fid=fopen(path,'r'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
value=string(sixgr.util.sha256Hex(fread(fid,Inf,'*uint8')));
end
