function ok=testCapturedChannelDiagnosticView()
% Deterministic tensor fixture; no claimed physical/campaign measurements.
x=reshape(complex(sin(1:60000),cos(1:60000)),500,3,8,5);
t=(0:499).'/122.88e6;
v=sixgr.truth.buildCapturedChannelDiagnosticView({x(1:113,:,:,:),x(114:end,:,:,:)}, ...
    {t(1:113),t(114:end)},128,1200);
indices=v.RuntimeChannelPathGainTimeIndices0Based+1;
assert(numel(indices)==10 && indices(1)==1 && indices(end)==500);
assert(isequal(v.RuntimeChannelPathGains,x(indices,:,:,:)));
assert(isequal(v.RuntimeChannelDopplerPathGains,reshape(x(:,:,1,1),500,3)));
assert(isequal(v.RuntimeChannelDopplerSampleTimes_s,t));
assert(v.RuntimeChannelPathGainsSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(x));
assert(v.RuntimeChannelPathGainElementCount==numel(x) && ...
    isequal(v.RuntimeChannelPathGainDimensions,size(x)));
assert(~v.RuntimeChannelDiagnosticHashEvidence.FullConcatenationAllocated);
small=x(1:4,:,:,:);
v=sixgr.truth.buildCapturedChannelDiagnosticView({small},{t(1:4)});
assert(isequal(v.RuntimeChannelPathGains,small));
% Exercise the spatial dimensions that triggered the 100-MHz export OOM,
% with a short deterministic time axis rather than allocating the original
% multi-gigabyte archive. Every path/64-TXRU/four-RX value is retained at
% each preview time; the Doppler trace must keep the full-rate clock.
fullArray=reshape(complex(sin(1:92160),cos(1:92160)),15,24,64,4);
fullTimes=(0:14).'/122.88e6;
v=sixgr.truth.buildCapturedChannelDiagnosticView( ...
    {fullArray(1:6,:,:,:),fullArray(7:end,:,:,:)}, ...
    {fullTimes(1:6),fullTimes(7:end)});
indices=v.RuntimeChannelPathGainTimeIndices0Based+1;
assert(isequal(size(v.RuntimeChannelPathGains),[5,24,64,4]) && ...
    numel(v.RuntimeChannelPathGains)<=32768);
assert(isequal(v.RuntimeChannelPathGains,fullArray(indices,:,:,:)) && ...
    isequal(v.RuntimeChannelDopplerPathGains,reshape(fullArray(:,:,1,1),15,24)) && ...
    isequal(v.RuntimeChannelDopplerSampleTimes_s,fullTimes));
assert(v.RuntimeChannelPathGainsSHA256== ...
    sixgr.phy.waveform.WaveformHash.runtimeArray(fullArray) && ...
    ~v.RuntimeChannelDiagnosticHashEvidence.FullConcatenationAllocated);
ok=true;
disp('CAPTURED_CHANNEL_DIAGNOSTIC_VIEW_PASS');
end
