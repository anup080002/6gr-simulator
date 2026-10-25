function ok=testPUCCHReceivedFrequencyCorrection()
% Actual native PUCCH TX/RX with declared unit-channel branch gains, delay
% and frequency rotation. No RF stream, fading, scheduler or received DCI
% qualification. Timing priors below come from actual received Format-2.
setup6GRSimToolkit('Verbose',false);
parent=fullfile(pwd,'results','validation','pucch_received_frequency');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
catalog=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs', ...
    'control','pucch_receiver_thresholds.yaml'));
beforeRNG=rng;
records={}; nativeTX=0; receiverCalls=0;
for scs=[15 30 60]
    sourceSlot=10*scs/15+1; % Nonzero frame and non-first subframe slot.
    [cfg,f,a,tx]=localFixture(2,scs,sourceSlot,catalog,false);
    nativeTX=nativeTX+1;
    source=localBuffer(f.Carrier,tx.Waveform*[.8+.2i -.3+.9i],sourceSlot,0);
    rx=sixgr.link.receivePUCCHObservation(cfg,a,f.Context,source);
    receiverCalls=receiverCalls+1;
    assert(rx.CRCPassed && ~rx.DTX && rx.ReceiveTiming.AppliedTimingCorrectionSamples==3);
    prior=sixgr.phy.sync.ReceivedULTimingReference(a,source,rx.ReceiveTiming,cfg);
    assert(prior.SourceSignal=="PUCCH_DMRS");
    for format=[2 0]
        [cfg,f,a,tx]=localFixture(format,scs,sourceSlot+1,catalog,false);
        nativeTX=nativeTX+1;
        timingPrior=[]; if format==0, timingPrior=prior; end
        for hz=[-430 430]
            clean=tx.Waveform*[.8+.2i -.3+.9i];
            observation=localBuffer(f.Carrier,clean,sourceSlot+1,hz);
            rawHash=observation.sampleHash();
            rx=sixgr.link.receivePUCCHObservation(cfg,a,f.Context,observation,timingPrior);
            receiverCalls=receiverCalls+1;
            localAssertExecuted(rx,cfg,f,a,tx,observation,clean,hz);
            receiverCalls=receiverCalls+1; % Direct aligned control inside assertion.
            records{end+1}=struct('SCS',scs,'Format',format,'InjectedCFO_Hz',hz, ...
                'OriginalObservation',observation,'Receiver',rx); %#ok<AGROW>
            assert(observation.sampleHash()==rawHash,'Receiver must not replace the original capture.');
            % Same original samples: false injected and DL tracking metadata
            % cannot become the UL correction authority.
            bad=cfg; bad.phy.impairments.cfo_Hz=1e7;
            bad.lls6g.userContext=struct('RuntimeTRSProcessed',true, ...
                'RuntimeTRSCFOEstimateAvailable',true,'RuntimeTRSEstimatedCFO_Hz',-1e7, ...
                'RuntimeTRSMeasurementDirection','DL','RuntimeInjectedCFO_Hz',9e6);
            wrong=sixgr.link.receivePUCCHObservation(bad,a,f.Context,observation,timingPrior);
            receiverCalls=receiverCalls+1;
            localEqualReceiver(rx,wrong);
            if scs==30 && format==2 && hz==430
                off=cfg; off.phy.rx.cfoCorrectionEnabled=false;
                disabled=sixgr.link.receivePUCCHObservation(off,a,f.Context,observation);
                receiverCalls=receiverCalls+1;
                d=disabled.ReceiveFrequency;
                assert(~d.CFOCorrectionApplied && ~d.CFOEstimateAvailable && ...
                    isnan(d.CFOCorrectionApplied_Hz) && ...
                    d.AlignedInputSHA256==d.CorrectedInputSHA256 && ...
                    d.Status=="disabled_by_receiver_configuration");
                assert(isequaln(disabled.ReceiveTiming,rx.ReceiveTiming));
                samples=observation.readComplete();
                aligned=samples(3+(1:size(clean,1)),:);
                [facade,facadeInfo]=sixgr.phy.ul.PUCCH_Rx(aligned,cfg,f.Assignment,f.Context, ...
                    'Carrier',f.Carrier,'NoiseVariance',NaN,'NoiseVarianceMode','received_dmrs_estimate', ...
                    'ChannelProfile','AWGN');
                receiverCalls=receiverCalls+1;
                assert(isequal(facade.DecodedSequence1,rx.DecodedSequence1) && ...
                    facade.OFDMInfo.GridSHA256==rx.OFDMInfo.GridSHA256 && ...
                    isequaln(facadeInfo.ReceiveFrequency,facade.ReceiveFrequency) && ...
                    facade.ReceiveFrequency.CFOCorrectionApplied_Hz==rx.ReceiveFrequency.CFOCorrectionApplied_Hz);
                unsupported=cfg; unsupported.phy.impairments.cfoEstimationMethod='dmrs_two_symbol';
                localReject(@()sixgr.link.receivePUCCHObservation( ...
                    unsupported,a,f.Context,observation), ...
                    'sixgr:phy:rx:UnsupportedControlFrequencyMethod');
            end
        end
        if format==0 && scs==30
            % A missing transmitter is not a fabricated timing measurement.
            % The genuine received prior owns alignment of these actual
            % zero/noise buffers. The existing detector owns the outcome.
            for kind=["zero","noise"]
                absent=complex(zeros(size(clean)));
                if kind=="noise"
                    stream=RandStream('mt19937ar','Seed',285901);
                    absent=(randn(stream,size(clean))+1i*randn(stream,size(clean)))/sqrt(2);
                end
                o=localBuffer(f.Carrier,absent,sourceSlot+1,0);
                nullCfg=cfg;
                nullCfg.phy.impairments.cfoCPObservation=struct( ...
                    'Policy','received_coherence_window','WindowFraction',.5, ...
                    'FalseAlarmProbability',1e-6);
                actual=sixgr.link.receivePUCCHObservation(nullCfg,a,f.Context,o,prior);
                receiverCalls=receiverCalls+1;
                [aligned,~]=prior.alignCompletedObservation(nullCfg,o,sourceSlot+1);
                [threshold,~]=sixgr.phy.pucch.resolveDetectionThreshold(a,catalog.pucch);
                direct=sixgr.phy.pucch.PUCCHReceiver.receive(aligned,f.Carrier,a,f.Context, ...
                    'NoiseVariance',NaN,'NoiseVarianceMode','noncoherent_correlation', ...
                    'ChannelProfile','AWGN','DetectionThreshold',threshold,'ReceiverConfig',nullCfg, ...
                    'ReceiverInputStartSample',o.StartSample+3);
                receiverCalls=receiverCalls+1;
                assert(isequaln(actual.DecodedSequence1,direct.DecodedSequence1) && ...
                    isequaln(actual.DetectionMetric,direct.DetectionMetric) && actual.DTX==direct.DTX);
                if kind=="zero"
                    assert(~actual.ReceiveFrequency.CFOEstimateAvailable && ...
                        ~actual.ReceiveFrequency.CFOCorrectionApplied && ...
                        isnan(actual.ReceiveFrequency.EstimatedCFO_Hz));
                end
                sixgr.link.controlFrequencyEvidence(actual); % Original nested/scalar receipt consistency.
                records{end+1}=struct('Kind',kind,'OriginalObservation',o,'Receiver',actual); %#ok<AGROW>
            end
        end
    end
end
% Other DM-RS PUCCH formats use the same timing-then-frequency operator.
for format=[1 3 4]
    [cfg,f,a,tx]=localFixture(format,30,23,catalog,false);
    nativeTX=nativeTX+1;
    clean=tx.Waveform*[.8+.2i -.3+.9i];
    o=localBuffer(f.Carrier,clean,23,430);
    rx=sixgr.link.receivePUCCHObservation(cfg,a,f.Context,o);
    receiverCalls=receiverCalls+1;
    localAssertExecuted(rx,cfg,f,a,tx,o,clean,430);
    receiverCalls=receiverCalls+1;
    records{end+1}=struct('Format',format,'OriginalObservation',o,'Receiver',rx); %#ok<AGROW>
end
% Standalone SR must keep its current received-sequence timing, not borrow a
% transmitted report or silently switch to the retained-pilot route.
[cfg,f,a,tx]=localFixture(0,30,27,catalog,true);
nativeTX=nativeTX+1;
clean=tx.Waveform*[.8+.2i -.3+.9i]; o=localBuffer(f.Carrier,clean,27,-430);
rx=sixgr.link.receivePUCCHObservation(cfg,a,f.Context,o);
receiverCalls=receiverCalls+1;
localAssertExecuted(rx,cfg,f,a,tx,o,clean,-430);
receiverCalls=receiverCalls+1;
assert(rx.ReceiveTiming.TimingSource=="received_configured_SR_sequence_bounded_search");
records{end+1}=struct('Kind',"standalone_SR",'OriginalObservation',o,'Receiver',rx);
quiet=localBuffer(f.Carrier,complex(zeros(size(clean))),27,0);
quietRX=sixgr.link.receivePUCCHObservation(cfg,a,f.Context,quiet);
receiverCalls=receiverCalls+1;
quietEvidence=sixgr.link.controlFrequencyEvidence(quietRX);
assert(quietEvidence.CFOCorrectionClockSource== ...
    "original_received_zero_energy_interval_not_timing_measurement" && ...
    ~quietEvidence.CFOCorrectionApplied);
assert(isequaln(rng,beforeRNG),'Receiver correction must not draw global randomness.');
scope=struct('OriginalNativeTransmitters',nativeTX,'ReceiverCalls',receiverCalls, ...
    'RFExecuted',false,'FadingExecuted',false,'SharedOwnerExecuted',false, ...
    'ReceivedSchedulingControlExecuted',false,'IndependentOscillatorResidualQualified',false);
save(fullfile(folder,'original_pucch_frequency_receipts.mat'),'records','scope','-v7.3');
fprintf('PUCCH_RECEIVED_FREQUENCY_PASS native_tx=%d receiver_calls=%d folder=%s\n',nativeTX,receiverCalls,folder);
ok=true;
end

function [cfg,f,a,tx]=localFixture(format,scs,slot0,catalog,sr)
args={}; if sr, args={'PayloadType','SR'}; end
bits=int8(1); if format>=2, bits=int8(mod((0:19).',2)); end
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,bits,'SCS',scs,args{:});
f.Carrier.NFrame=floor(slot0/f.Carrier.SlotsPerFrame);
f.Carrier.NSlot=mod(slot0,f.Carrier.SlotsPerFrame);
data=f.Report.Data; data.TargetSlot=slot0+1;
if sr
    data.SchedulingRequestReports=sixgr.phy.pucch.SchedulingRequestState.atSlot( ...
        data.SchedulingRequestReports,slot0);
end
f.Report=sixgr.phy.pucch.UCIReport(data);
frame=f.FrameState; frame.PDSCHEndSlot=slot0; frame.TargetSlot=slot0+1;
f.Assignment=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI(f.Report,f.UEContext,frame);
f.Context=sixgr.phy.pucch.UCIReportContext.fromReport(f.Report);
a=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
    'ObservationID',"pucch_frequency_"+format+"_"+slot0,'ResourceID',f.Assignment.Resource.ID, ...
    'RNTI',321,'AbsoluteSlot0',slot0,'Source','declared_component_receiver_resource', ...
    'TimingSource','received_pilot_or_prior_clock'),f.RRCContext,f.Context);
cfg=struct('phy',struct('carrier',struct('NSizeGrid',f.Carrier.NSizeGrid, ...
    'NStartGrid',f.Carrier.NStartGrid,'NCellID',f.Carrier.NCellID, ...
    'SubcarrierSpacing',scs,'CyclicPrefix',f.Carrier.CyclicPrefix), ...
    'pucch',struct('enable',true,'receiverDetectionThresholds',catalog.pucch), ...
    'pusch',struct('RNTI',321),'frame',struct('DefaultIdentity',struct('ScheduledCCID',0,'ULBWPID',0)), ...
    'synchronization',struct('maxReceivedULTimingAgeSlots',4), ...
    'rx',struct('cfoCorrectionEnabled',true), ...
    'impairments',struct('cfoEstimationMethod','cyclic_prefix', ...
        'cfoCPObservation',struct('Policy','full_prefix'))), ...
    'frequency',struct('centerFrequencyHz',2.35e9),'channel',struct('model','AWGN'), ...
    'SharedULTimingContext',struct('Source','declared_component_TAG','TAGID',0));
tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
end

function o=localBuffer(carrier,samples,slot0,hz)
info=nrOFDMInfo(carrier);
first=sixgr.phy.frame.slotStartSample(carrier,slot0,info.SampleRate);
samples=[complex(zeros(3,size(samples,2)));samples;complex(zeros(5,size(samples,2)))];
samples=samples.*exp(2i*pi*hz/info.SampleRate*(0:size(samples,1)-1).');
o=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(samples,1),info.SampleRate,size(samples,2));
o.append(sixgr.phy.waveform.WaveformChunk(samples,first),info.SampleRate);
end

function localAssertExecuted(rx,cfg,f,a,tx,o,clean,hz)
e=rx.ReceiveFrequency;
assert(rx.ReceiverUsable && ~rx.DTX && rx.CRCPassed && ...
    isequal(rx.DecodedSequence1,tx.Serialization.Sequence1.Bits) && ...
    isequal(rx.DecodedSequence2,tx.Serialization.Sequence2.Bits));
assert(rx.ReceiveTiming.AppliedTimingCorrectionSamples==3 && ...
    ~rx.ReceiveTiming.OracleTimingUsed && ~rx.ReceiveTiming.ReceiverZeroPaddingUsed);
assert(e.CFOEstimateAvailable && e.CFOCorrectionApplied && ...
    abs(e.EstimatedCFO_Hz-hz)<1e-7 && e.CFOCorrectionApplied_Hz==e.EstimatedCFO_Hz && ...
    e.CFOCorrectionSampleOrigin==0 && e.AlignedStartSample==o.StartSample+3 && ...
    e.CFOCorrectionAbsoluteSampleOrigin==o.StartSample+3 && ...
    e.ObservationSampleSHA256==o.sampleHash());
assert(e.CFOObservation.ClockSource=="canonical_captured_slot" && ...
    e.ResidualCFOReusesAcquisitionObservation && ...
    e.ResidualCFOEstimateRole=="same_observation_estimator_consistency_not_independent_residual" && ...
    abs(e.ResidualCFOEstimatorConsistency_Hz)<1e-7);
raw=o.readComplete(); aligned=raw(3+(1:size(clean,1)),:);
expected=aligned.*exp(-2i*pi*e.CFOCorrectionApplied_Hz/o.SampleRateHz*(0:size(aligned,1)-1).');
assert(e.AlignedInputSampleSHA256==sixgr.phy.waveform.WaveformHash.numeric(aligned) && ...
    e.CorrectedSampleSHA256==sixgr.phy.waveform.WaveformHash.numeric(expected) && ...
    rx.OFDMInfo.WaveformSHA256==sixgr.phy.waveform.WaveformHash.numeric(expected));
% Separate native FFT is a test reference, not another practical receiver.
actualGrid=nrOFDMDemodulate(f.Carrier,expected,'CyclicPrefixFraction',.5);
cleanGrid=nrOFDMDemodulate(f.Carrier,clean,'CyclicPrefixFraction',.5);
reference=cleanGrid.*exp(2i*pi*hz/o.SampleRateHz*3);
assert(norm(actualGrid(:)-reference(:))/norm(reference(:))<1e-10 && ...
    rx.OFDMInfo.GridSHA256==sixgr.phy.waveform.WaveformHash.numeric(actualGrid));
% Direct aligned reception has the same applied operator and detector. This
% also catches correction before AND after timing or a second rotation.
[threshold,~]=sixgr.phy.pucch.resolveDetectionThreshold(a,cfg.phy.pucch.receiverDetectionThresholds);
mode='received_dmrs_estimate'; if a.Format==0, mode='noncoherent_correlation'; end
direct=sixgr.phy.pucch.PUCCHReceiver.receive(aligned,f.Carrier,a,f.Context, ...
    'NoiseVariance',NaN,'NoiseVarianceMode',mode,'ChannelProfile','AWGN', ...
    'DetectionThreshold',threshold,'ReceiverConfig',cfg,'ReceiverInputStartSample',o.StartSample+3);
assert(isequaln(rx.DecodedSequence1,direct.DecodedSequence1) && ...
    isequaln(rx.DetectionMetric,direct.DetectionMetric) && rx.DTX==direct.DTX && ...
    rx.OFDMInfo.GridSHA256==direct.OFDMInfo.GridSHA256);
end

function localEqualReceiver(a,b)
for field=["ReceiveTiming","ReceiveFrequency","DecodedSequence1","DecodedSequence2", ...
        "DetectionMetric","DTX","CRCPassed","ChannelEstimate"]
    assert(isequaln(a.(field),b.(field)),'Injected/DL metadata changed original UL receiver field %s.',field);
end
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
