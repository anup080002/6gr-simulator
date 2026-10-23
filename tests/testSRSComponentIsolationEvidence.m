function ok=testSRSComponentIsolationEvidence()
% Declared channel-dependency contract, actual component composition. This
% is not an SRS receiver, channel execution, or accuracy qualification.
setup6GRSimToolkit('Verbose',false);
[trace,request]=fixture([0 8]);
p=sixgr.truth.proveSRSComponentIsolation(trace,request);
assert(p.Available&&~p.AllHistorySRSOnlyRequired&&all(p.TargetDependencyPerFFTWindow));
assert(~isempty(p.ConsumedContributorReceipts)&&p.AdditionalChannelExecutions==0);
% Exact half-open boundary: channel memory3 + PA memory2 + timing4 means
% FFT[40,48) depends on component[31,44). Prior signal ending31 is safe.
[trace,request]=fixture([0 31]);
p=sixgr.truth.proveSRSComponentIsolation(trace,request); assert(p.Available);
[trace,request]=fixture([0 32]);
p=sixgr.truth.proveSRSComponentIsolation(trace,request);
assert(~p.Available&&p.Status=="unavailable_non_target_component_in_finite_dependency");
assert(any(arrayfun(@(c)c.ComponentID=="earlier_access",p.Contamination)));
[trace,request]=fixture([0 8]);
bad=request; bad.ComponentSHA256="changed-original";
reject(@()sixgr.truth.proveSRSComponentIsolation(trace,bad));
bad=request; bad.ReceiverID="different_rx";
reject(@()sixgr.truth.proveSRSComponentIsolation(trace,bad));
bad=request; bad.ConfigurationEpoch=8;
reject(@()sixgr.truth.proveSRSComponentIsolation(trace,bad));
bad=trace; bad{3}.Execution.TX.Replay.RFInputWaveformSHA256="not-composite";
reject(@()sixgr.truth.proveSRSComponentIsolation(bad,request));
bad=trace; bad{3}.Execution.ExecutedContributors.Receipt.CompleteContributorList=false;
reject(@()sixgr.truth.proveSRSComponentIsolation(bad,request));
bad=trace; bad{3}.Execution.TX.Replay.TXSignalDependency.ZeroPreserving=false;
reject(@()sixgr.truth.proveSRSComponentIsolation(bad,request));
bad=trace; bad{3}.Execution.Links.Replay.ChannelSignalDependency.HistoryInitializationSource="elapsed_idle_time";
reject(@()sixgr.truth.proveSRSComponentIsolation(bad,request));
bad=trace; bad(2)=[];
reject(@()sixgr.truth.proveSRSComponentIsolation(bad,request));
bad=trace; bad{3}.Execution.ExecutedContributors.Receipt.Components(1).NonzeroTimeSampleCount=100;
reject(@()sixgr.truth.proveSRSComponentIsolation(bad,request));
bad=request; bad.FFTIntervals=[60 64];
p=sixgr.truth.proveSRSComponentIsolation(trace,bad);
assert(~p.Available&&p.Status=="unavailable_no_target_signal_dependency");
fprintf('SRS_COMPONENT_ISOLATION_CONTRACT_PASS finite_prior_signal=1 exact_boundaries=1 physical_accuracy=0\n');
ok=true;
end

function [trace,request]=fixture(prior)
fs=1000; epoch=7;
composer=sixgr.phy.waveform.WaveformStreamComposer(fs,2,0);
old=complex(ones(diff(prior),2)); target=complex(ones(16,2),ones(16,2));
composer.enqueue("earlier_access",sixgr.phy.waveform.WaveformChunk(old,prior(1)),fs);
component=sixgr.phy.waveform.WaveformChunk(target,32);
composer.enqueue("SRS",component,fs);
request=struct('TransmitterID',"ue",'ReceiverID',"gnb_rx",'LinkID',"serving", ...
    'ComponentID',"SRS",'ComponentSHA256',component.SHA256, ...
    'SampleRateHz',fs,'ConfigurationEpoch',epoch,'FFTIntervals',[40 48]);
trace=cell(4,1); first=0;
for k=1:4
    stop=k*16; [chunk,receipt]=composer.readThrough(stop);
    common=struct('Available',true,'StartSample',first,'EndSampleExclusive',stop, ...
        'SampleRateHz',fs,'ConfigurationEpoch',epoch,'MemorySamples',3);
    channel=common;
    channel.ContractVersion="sixgr.channel.executed_signal_dependency/v1";
    channel.InputHistoryStartSample=0; channel.ZeroInputHistoryAtOrigin=true;
    channel.HistoryInitializationSource="original_fresh_zero_warmup";
    channel.FilterSHA256="declared-FIR-support";
    channel.NativeInitializationSHA256="declared-component-test-only";
    rf=common; rf.ContractVersion="sixgr.rf.executed_tx_signal_dependency/v1";
    rf.MemorySamples=2; rf.DelaySamples=4; rf.HistoryOriginSample=0;
    rf.ZeroPreserving=true; rf.ZeroInputHistoryAtOrigin=true; rf.AdditiveTXOutput=false;
    rf.OriginalInputChunkSHA256=chunk.SHA256;
    rf.RFInputWaveformSHA256="declared-RF-different-hash-convention";
    e=struct('Source',"composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf", ...
        'ApproximationMode',"none",'StartSample',first,'EndSampleExclusive',stop, ...
        'SampleRateHz',fs,'ConfigurationEpoch',epoch, ...
        'Links',struct('ID',"serving",'TX',"ue",'RX',"gnb_rx", ...
            'Replay',struct('ChannelSignalDependency',channel)), ...
        'TX',struct('ID',"ue",'Replay',struct('TXSignalDependency',rf, ...
            'RFInputWaveformSHA256',rf.RFInputWaveformSHA256)), ...
        'ExecutedContributors',struct('TransmitterID',"ue", ...
            'CommittedThroughSample',stop,'Receipt',receipt));
    trace{k}=struct('StartSample',first,'EndSampleExclusive',stop,'Execution',e);
    first=stop;
end
end

function reject(fn)
try, fn(); catch cause
    assert(string(cause.identifier)=="sixgr:truth:SRSIsolationEvidence", ...
        'Unexpected rejection owner: %s',cause.identifier);
    return;
end
error('test:SRSIsolationMissingGuard','Malformed isolation evidence was accepted.');
end
