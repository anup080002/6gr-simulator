function ok=testPUCCHStandaloneSRTimingAuthority()
% Actual 273-PRB/30-kHz waveform, declared unit channel/single receive chain.
% Proves receiver clock ownership, not H4 array or statistical qualification.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
root=fullfile(pwd,'results','lls','sr_timing_authority_component', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
cfg=sixgr.lls6g.buildInternalConfig(source,root);
cfg.outputs.rawIQCaptureEnabled=true; cfg.outputs.saveRawWaveforms=true;
cfg.phy.pusch.RNTI=321;
cfg.SharedULTimingContext=struct('Source',"declared_component_TAG",'TAGID',0);
cfg.channel.model='AWGN'; cfg.channel.tdlProfile=''; cfg.channel.cdlProfile='';
cfg.phy.synchronization.maxReceivedULTimingAgeSlots=4;
% Retain a genuine received Format-2 DM-RS reference at absolute slot zero.
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,[], 'NSizeGrid',273,'SCS',30);
cfg.phy.carrier=struct('NSizeGrid',273,'NStartGrid',0,'SubcarrierSpacing',30, ...
    'NCellID',f.Carrier.NCellID,'CyclicPrefix',f.Carrier.CyclicPrefix);
a=assignment(f,f.Context,0);
wave=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
o=buffer(f.Carrier,wave.Waveform,0);
rx=sixgr.link.receivePUCCHObservation(cfg,a,f.Context,o);
assert(rx.ReceiverUsable && ~rx.DTX && rx.CRCPassed);
prior=sixgr.phy.sync.ReceivedULTimingReference(a,o,rx.ReceiveTiming,cfg);
assert(prior.SourceSignal=="PUCCH_DMRS");

% Positive standalone SR has a receiver-known sequence, independently of
% whether a recent, expired, or no prior clock happens to be retained.
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(0,int8(1),'NSizeGrid',273,'SCS',30);
context=sixgr.phy.pucch.UCIReportContext(struct( ...
    'ReportID',"independent_configured_SR",'ConfigurationEpoch',f.RRCContext.ConfigurationEpoch, ...
    'Sequence1Length',1,'Sequence2Length',0,'HARQACKBits',0,'SRBits',1, ...
    'CSIPart1Bits',0,'CSIPart2Bits',0,'PriorityIndex',0));
for slot0=[1 5]
    carrier=f.Carrier; carrier.NSlot=slot0;
    data=f.Report.Data; data.TargetSlot=slot0+1;
    data.HARQACKReport=struct([]); data.SchedulingRequestReports=struct('Bits',int8(1));
    report=sixgr.phy.pucch.UCIReport(data);
    frame=f.FrameState; frame.PDSCHEndSlot=slot0; frame.TargetSlot=slot0+1;
    tx=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI(report,f.UEContext,frame);
    wave=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,tx,report);
    a=assignment(f,context,slot0);
    for kind=["positive","quiet","noise"]
        samples=wave.Waveform;
        if kind=="quiet", samples(:)=0;
        elseif kind=="noise"
            stream=RandStream('mt19937ar','Seed',23071+slot0);
            samples=complex(randn(stream,size(samples)),randn(stream,size(samples)))/sqrt(2);
        end
        o=buffer(carrier,samples,slot0);
        without=sixgr.link.receivePUCCHObservation(cfg,a,context,o);
        received=sixgr.link.receivePUCCHObservation(cfg,a,context,o,prior);
        for field=["DecodedSequence1","DecodedSequence2","DetectionMetric","DTX","ReceiverUsable"]
            assert(isequaln(received.(field),without.(field)), ...
                'An optional prior must not change independent standalone-SR reception.');
        end
        assert(received.ReceiveTiming.PriorClockProvided && ~received.ReceiveTiming.PriorClockApplied && ...
            ~received.ReceiveTiming.OracleTimingUsed && ~received.ReceiveTiming.ReceiverZeroPaddingUsed);
        if kind~="quiet"
            assert(received.ReceiveTiming.TimingSource=="received_configured_SR_sequence_bounded_search");
        end
        if kind=="positive"
            assert(received.ReceiverUsable && ~received.DTX && received.DecodedFields.SR==1);
        elseif kind=="quiet"
            assert(received.DTX && ~received.ReceiverUsable && ...
                received.ReceiveTiming.TimingSource=="unavailable_zero_received_energy" && ...
                isnan(received.ReceiveTiming.AppliedTimingCorrectionSamples));
        end
        if slot0==5
            % Exercise the production capture/replay consumer as well as RX.
            % These are explicitly unit-channel component buffers, not a
            % multi-cell/shared-array execution or qualified instrument IQ.
            txSamples=complex(zeros(size(wave.Waveform)));
            if kind=="positive", txSamples=wave.Waveform; end
            txObservation=buffer(carrier,txSamples,slot0);
            planes=struct('ReceiverID',{"gnb_1_rx:pre_rf","gnb_1_rx:post_rf","ue_1:tx"}, ...
                'Observation',{o,o,txObservation});
            h=struct('Assignment',a,'Context',context,'ServingCell',1,'UEIndex',1);
            capturePath=sixgr.truth.exportIndependentPUCCHObservation( ...
                fullfile(root,kind),cfg,h,planes,received,o,prior);
            saved=readCapture(capturePath); c=saved.capture;
            replay=sixgr.phy.waveform.WaveformObservationBuffer(c.StartSample,c.EndSampleExclusive, ...
                c.SampleRateHz,size(c.ReceiverInputSamples,2));
            replay.append(sixgr.phy.waveform.WaveformChunk(c.ReceiverInputSamples,c.StartSample),c.SampleRateHz);
            again=sixgr.link.receivePUCCHObservation(c.Config,c.Assignment,c.Context,replay,c.ReceiverTimingPrior);
            assert(isequaln(again.DecodedSequence1,received.DecodedSequence1) && ...
                again.DTX==received.DTX && ~c.QualificationPassed);
        end
    end
end
% Do not turn the SR correction into a fallback for unknown HARQ bits.
harq=assignment(f,f.Context,5);
reject(@()sixgr.link.receivePUCCHObservation(cfg,harq,f.Context,o,prior), ...
    'sixgr:phy:sync:StaleULTimingReference');
reject(@()sixgr.link.receivePUCCHObservation(cfg,harq,f.Context,o), ...
    'sixgr:phy:pucch:PUCCHTimingReferenceRequired');
reject(@()sixgr.link.receivePUCCHObservation(cfg,a,context,o,struct()), ...
    'sixgr:link:InvalidPUCCHTimingPrior');
fprintf('PUCCH_STANDALONE_SR_TIMING_AUTHORITY_PASS cases=6 stale_HARQ_guard_retained=1 no_statistical_qualification=1\n');
ok=true;
end

function a=assignment(f,context,slot0)
a=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
    'ObservationID',context.ReportID+"_"+slot0,'ResourceID',f.Assignment.Resource.ID, ...
    'RNTI',321,'AbsoluteSlot0',slot0,'Source',"declared_independent_receive_obligation", ...
    'TimingSource',"receiver_acquired_samples"),f.RRCContext,context);
end
function o=buffer(carrier,samples,slot0)
info=nrOFDMInfo(carrier);
first=sixgr.phy.frame.slotStartSample(carrier,slot0,info.SampleRate);
samples=[complex(zeros(3,size(samples,2)));samples;complex(zeros(5,size(samples,2)))];
o=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(samples,1),info.SampleRate,size(samples,2));
o.append(sixgr.phy.waveform.WaveformChunk(samples,first),info.SampleRate);
end
function reject(fn,id)
try, fn(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s, got %s: %s',id,ex.identifier,ex.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
function saved=readCapture(target)
% Windows HDF5 rejects some valid absolute paths longer than MAX_PATH.
% Verify an unchanged short readback; never overwrite the retained capture.
readback=string(tempname())+".mat";
cleanup=onCleanup(@()delete(readback)); %#ok<NASGU>
copyfile(target,readback);
assert(sixgr.util.sha256File(target)==sixgr.util.sha256File(readback));
saved=load(readback,'capture');
end
