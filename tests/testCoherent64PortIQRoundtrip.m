function ok=testCoherent64PortIQRoundtrip()
% Full-file digital imports, not an RF instrument capability certificate.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'results','lls','iq64_roundtrip',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
t=(0:1023).'; carrier=exp(1j*(2*pi*t/17+.1*sin(t/11)));
weights=(1:64)/64.*exp(1j*(0:63)*.13);
weights(8)=weights(4); % Deliberately identical beam ports must stay identical.
waveform=carrier*weights;
capture=struct('Waveform',waveform,'SampleRateHz',122.88e6, ...
    'CapturePoint',"post_power_and_tx_rf_pre_channel", ...
    'WaveformAuthority',"digital_fixture_not_runtime_or_hardware", ...
    'ArtifactScope',"complete_deterministic_fixture_record");
out=sixgr.truth.exportRuntimeTxIQCapture(root,capture, ...
    struct('channel',struct('fc_Hz',4e9)),"DL");
m=out.ManifestTable;
assert(m.PortCount==64 && m.SampleCount==1024 && ...
    m.PlaybackRepeatPolicy=="operator_selected_no_implicit_repeat");
scale=m.CommonNormalizationFullScale;
canonical=readtable(out.CanonicalCSVPath);
stored=load(out.MATPath,'waveform');
assert(isequal(stored.waveform,waveform));
expectedHashes=split(string(m.KeysightInt16SHA256),'|');
for port=1:64
    expected=waveform(:,port)/scale;
    csv=readmatrix(out.KeysightCSVPaths(port)); actual=complex(csv(:,1),csv(:,2));
    assert(max(abs(actual-expected))<2e-14);
    re=canonical.(sprintf('I_Port%d',port)); im=canonical.(sprintf('Q_Port%d',port));
    assert(max(abs(complex(re,im)-waveform(:,port)))<2e-14);
    fid=fopen(out.KeysightInt16Paths(port),'rb','ieee-le'); assert(fid>=0);
    values=fread(fid,[2 Inf],'int16=>double'); fclose(fid);
    assert(size(values,2)==1024);
    quantized=complex(values(1,:).',values(2,:).')/32767;
    assert(max(abs(quantized-expected))<=sqrt(2)/(2*32767)+eps);
    hash=string(sixgr.util.sha256File(out.KeysightInt16Paths(port)));
    assert(strcmpi(hash,expectedHashes(port)));
    vsa=load(out.KeysightVSAMATPaths(port));
    assert(max(abs(double(vsa.Y)-expected))<=2*eps('single') && ...
        vsa.XDelta==1/capture.SampleRateHz && vsa.InputCenter==4e9);
end
assert(expectedHashes(4)==expectedHashes(8) && expectedHashes(1)~=expectedHashes(64));
assert(m.PhysicalInstrumentValidationStatus=="not_executed_requires_physical_instrument");
ok=true;
end
