function ok=testSharedRFEndpointMetadata()
% Real, bounded TX/RX RF processing plus metadata-negative tests. This is
% not a full scenario, an impairment qualification or a testAll launcher.
setup6GRSimToolkit('Verbose',false);
cfg=struct();
cfg.rf.rx.cfo_Hz=400; cfg.rf.tx.cfo_Hz=-125;
cfg.rf.rx.timingOffsetSamples=2; cfg.rf.tx.timingOffsetSamples=1;
cfg.rf.adc.enable=true; cfg.rf.adcBits=12; cfg.rf.adc.fullScale=1;
cfg.rf.frontend.dac=struct('enabled',true,'profile_id','shared_metadata_test', ...
    'version','1','bits',12,'full_scale',1,'convention','signed_midrise', ...
    'dither_enabled',false,'dither_rms',0,'aperture_jitter_seconds',0);
fs=122.88e6; first=100;
x=complex([.2*ones(8,2);2*ones(24,2)],.1*ones(32,2));
for direction=["DL","UL"]
    for side=["TX","RX"]
        stream=sixgr.rf.runtime.RFImpairmentStream(cfg,lower(side),direction,fs,2,first,1,false);
        segments=cell(2,1); y=zeros(size(x),'like',x); offset=0;
        for k=1:2
            stop=[8 32]; stop=stop(k);
            result=stream.apply(sixgr.phy.waveform.WaveformChunk(x(offset+1:stop,:),first+offset),1);
            y(offset+1:stop,:)=result.Waveform;
            owner=struct('ID',"owner",'Replay',result.Replay);
            unrelated=struct('ID',"other_ue",'Replay',struct('CFOApplied',NaN));
            execution=struct('StartSample',first+offset,'EndSampleExclusive',first+stop);
            execution.(side)=[unrelated owner]; % Never take the first UE.
            segments{k}=struct('Execution',execution);
            offset=stop;
        end
        plane=localPlane(y,first,fs,segments,side);
        clock=stream.NextSampleIndex;
        [summary,audit]=sixgr.truth.summarizeSharedRFEndpoint(plane,side);
        assert(stream.NextSampleIndex==clock && audit.AdditionalRFExecutions==0 && ...
            ~audit.ReceiverEstimatorInput && audit.NodeID=="owner");
        assert(summary.CFOApplied && summary.TimingOffsetApplied && summary.RFStrictOk);
        assert(summary.InjectedCFO_Hz==result.Replay.InjectedCFO_Hz && ...
            summary.InjectedTimingOffset_samples==result.Replay.InjectedTimingOffset_samples);
        assert(summary.ADCBits==12 && summary.DACBits==12);
        assert(~isfield(summary,'RFInputPower') && ~isfield(summary,'RFOutputPower') && ...
            ~isfield(summary,'RFInputWaveformSHA256') && ~isfield(summary,'RFOutputWaveformSHA256') && ...
            ~isfield(summary,'PhaseNoiseRMS_rad') && ~isfield(summary,'IQImbalanceImageRejection_dB'), ...
            'Do not promote segment powers/hashes/diagnostics into capture measurements.');
        prefix="ADC"; inactive="DAC";
        if side=="TX", prefix="DAC"; inactive="ADC"; end
        clipped=0; total=0;
        for k=1:2
            r=segments{k}.Execution.(side)(2).Replay;
            clipped=clipped+r.(prefix+"ClippedSampleCount");
            total=total+r.(prefix+"ClippingSampleCount");
        end
        assert(total==numel(x) && summary.(prefix+"QuantizationExecuted") && ...
            summary.(prefix+"ClippedSampleCount")==clipped && ...
            summary.(prefix+"ClippingSampleCount")==total && ...
            summary.(prefix+"ClippingRatio")==clipped/total && ...
            summary.(prefix+"ClippingStatus")=="measured");
        assert(summary.(inactive+"ClippingStatus")=="not_executed" && ...
            isnan(summary.(inactive+"ClippingRatio")));

        cropped=localPlane(y(2:end-1,:),first+1,fs,segments,side);
        [partial,partialAudit]=sixgr.truth.summarizeSharedRFEndpoint(cropped,side);
        assert(partial.CFOApplied && ~partialAudit.WholeExecutionSegmentsOnly && ...
            isnan(partial.(prefix+"ClippingRatio")) && ...
            isnan(partial.(prefix+"ClippedSampleCount")) && ...
            partial.(prefix+"ClippingStatus")== ...
            "unavailable_partial_execution_segment_requires_sample_masks");

        missing=plane;
        missing.Segments{1}.Execution.(side)(2).Replay= ...
            rmfield(missing.Segments{1}.Execution.(side)(2).Replay,'CFOApplied');
        [absent,absentAudit]=sixgr.truth.summarizeSharedRFEndpoint(missing,side);
        assert(~isfield(absent,'CFOApplied') && ismember("CFOApplied",absentAudit.MissingFields), ...
            'An absent executed flag must not become a false disabled value.');
        varying=plane;
        varying.Segments{2}.Execution.(side)(2).Replay.InjectedCFO_Hz=600;
        [variable,variableAudit]=sixgr.truth.summarizeSharedRFEndpoint(varying,side);
        assert(~isfield(variable,'InjectedCFO_Hz') && ...
            ismember("InjectedCFO_Hz",variableAudit.TimeVaryingFields), ...
            'Do not average different RF epochs or select the last configured CFO.');
        failed=plane; failed.Segments{2}.Execution.(side)(2).Replay.RFStrictOk=false;
        failure=sixgr.truth.summarizeSharedRFEndpoint(failed,side);
        assert(~failure.RFStrictOk && ...
            failure.RFExecutionStatus=="executed_retained_sample_stream_validation_failed");

        bad=plane; bad.Segments{2}.Execution.(side)(2).Replay.CFOApplied=NaN;
        localError(@()sixgr.truth.summarizeSharedRFEndpoint(bad,side),'sixgr:truth:InvalidRFEndpointFlag');
        bad=plane; bad.Segments{2}.Execution.(side)(2).Replay.(prefix+"ClippedSampleCount")=total+1;
        localError(@()sixgr.truth.summarizeSharedRFEndpoint(bad,side),'sixgr:truth:InvalidRFConverterPopulation');
        bad=plane; bad.Segments{2}.Execution.(side)(2).Replay.(prefix+"ClippingPopulation")="different_population";
        mixed=sixgr.truth.summarizeSharedRFEndpoint(bad,side);
        assert(isnan(mixed.(prefix+"ClippingRatio")) && ...
            mixed.(prefix+"ClippingStatus")=="unavailable_mixed_converter_population");
        bad=plane; bad.Segments{2}.Execution.(side)(2).Replay.(prefix+"QuantizationExecuted")=false;
        mixed=sixgr.truth.summarizeSharedRFEndpoint(bad,side);
        assert(isnan(mixed.(prefix+"ClippingRatio")) && ...
            mixed.(prefix+"ClippingStatus")=="unavailable_converter_not_executed_over_entire_observation");
        bad=plane; bad.Segments{2}.Execution.(side)(1).ID="owner";
        localError(@()sixgr.truth.summarizeSharedRFEndpoint(bad,side),'sixgr:truth:RFEndpointIdentityMismatch');
        bad=plane; bad.Segments{2}.Execution.StartSample=first+9;
        localError(@()sixgr.truth.summarizeSharedRFEndpoint(bad,side),'sixgr:truth:RFEndpointCoverageGap');
        bad=plane; bad.Segments{2}.Execution.StartSample=first+7;
        localError(@()sixgr.truth.summarizeSharedRFEndpoint(bad,side),'sixgr:truth:RFEndpointCoverageGap');
        bad=plane; bad.Segments=flipud(bad.Segments);
        localError(@()sixgr.truth.summarizeSharedRFEndpoint(bad,side),'sixgr:truth:RFEndpointCoverageGap');
    end
end
ok=true;
disp('SHARED_RF_ENDPOINT_METADATA_PASS: actual TX/RX execution, exact population scope, no fabricated disabled flags.');
end

function plane=localPlane(wave,first,fs,segments,side)
observation=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(wave,1),fs,size(wave,2));
observation.append(sixgr.phy.waveform.WaveformChunk(wave,first),fs);
suffix=":post_rf"; if side=="TX", suffix=":tx"; end
plane=struct('ReceiverID',"owner"+suffix,'Observation',observation,'Segments',{segments});
end

function localError(action,id)
try
    action();
catch cause
    assert(string(cause.identifier)==id,'Expected %s, received %s.',id,cause.identifier);
    return;
end
error('sixgr:test:ExpectedError','Expected %s.',id);
end
