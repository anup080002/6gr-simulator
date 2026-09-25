function rows=diagnosePUCCHReceivedClockReuse(runFolder,outputRoot)
% Replay actual PUCCH IQ using causally completed, measured SRS clocks.
% This does not install a policy or qualify a detector. No TX timing is used.
assert(~isfolder(outputRoot),'test:EvidenceExists','Preserve earlier observations.');
mkdir(outputRoot);
p=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs','validation', ...
    'pucch_short_uci_null_math.yaml'));
wordPolicy=struct('algorithm',string(p.candidate_word_algorithm), ...
    'minimumPosterior',p.candidate_word_minimum_posterior);
history={}; srs=dir(fullfile(runFolder,'**','srs_ue_1_tx_*.mat'));
for k=1:numel(srs)
    c=readCapture(srs(k),outputRoot,"srs_"+k);
    buffer=makeBuffer(c.RXAfterDigitalGainCompensation,c.RXStartSample,c.RXEndSampleExclusive,c.SampleRateHz);
    reference=sixgr.truth.retainReceivedSRSTimingReference(c.Prepared,buffer,c.ReceivedResult);
    if ~isempty(reference), history{end+1}=reference; end %#ok<AGROW>
end
assert(~isempty(history),'test:ReceivedSRSClockUnavailable','Require real received SRS timing evidence.');
[~,order]=sort(cellfun(@(r)r.AvailableAtSample,history)); history=history(order);
state=struct('ReceivedULTimingHistory',{{history}});
path=fullfile(runFolder,'air_interface','csv','pucch_trials.csv');
options=detectImportOptions(path,'TextType','string');
options=setvartype(options,'UCIExpectedBitVector','string');
trials=readtable(path,options);
captures=dir(fullfile(runFolder,'**','pucch_rx_*.mat')); rows=table();
for k=1:height(trials)
    hit=find(endsWith(string({captures.name}),"_"+string(trials.ReceiverContextDigest(k))+".mat"));
    assert(isscalar(hit),'test:AmbiguousCapture','Match the independent receiver context.');
    c=readCapture(captures(hit),outputRoot,"pucch_"+k);
    carrier=sixgr.phy.grid.makeCarrier(c.Config); slot0=double(c.Assignment.Data.AbsoluteSlot0);
    carrier.NFrame=floor(slot0/double(carrier.SlotsPerFrame));
    carrier.NSlot=mod(slot0,double(carrier.SlotsPerFrame));
    nominal=sixgr.phy.frame.slotStartSample(carrier,slot0,c.SampleRateHz);
    buffer=makeBuffer(c.ReceiverInputSamples,c.StartSample,c.EndSampleExclusive,c.SampleRateHz);
    reference=sixgr.truth.selectReceivedULTimingReference(state,1,c.EndSampleExclusive,nominal);
    count=c.Context.Sequence1Length+c.Context.Sequence2Length;
    resource=c.Assignment.Resource.toolboxConfig();
    originalTiming=c.ReceivedResult.ReceiveTiming;
    originalSamples=c.ReceiverInputSamples(originalTiming.AppliedTimingCorrectionSamples+ ...
        (1:originalTiming.DemodulatedSampleCount),:);
    originalGrid=sixgr.phy.waveform.ofdmDemodulate(carrier,originalSamples);
    originalJoint=sixgr.phy.pucch.decodeFormat2FlatShortUCI(carrier,resource,originalGrid, ...
        count,p.target_model_probability,diff(originalTiming.SearchWindowSamples)+1);
    originalWhitened=sixgr.phy.pucch.detectFormat2EqualizedWhiteNoisePresence( ...
        carrier,resource,c.ReceivedResult.EqualizerInfo.EqualizerResult, ...
        count,p.target_model_probability,diff(originalTiming.SearchWindowSamples)+1);
    row=struct('Slot',slot0+1,'PriorAvailable',~isempty(reference), ...
        'OriginalOffsetSamples',c.ReceivedResult.ReceiveTiming.AppliedTimingCorrectionSamples, ...
        'PriorOffsetSamples',NaN,'PriorAgeSlots',NaN,'ReferenceAvailableAtSample',NaN, ...
        'OriginalBitErrors',NaN,'RetimedBitErrors',NaN,'RetimedGainAwareBitErrors',NaN, ...
        'RetimedConditionalWordPosterior',NaN,'RetimedPilotCorrelation',NaN, ...
        'RetimedPilotThreshold',NaN,'RetimedPilotDetected',NaN, ...
        'OriginalJointBitErrors',NaN,'OriginalJointPresenceDetected',originalJoint.JointPresenceDecision.Detected, ...
        'OriginalJointWordPosterior',originalJoint.ConditionalWordPosterior, ...
        'RetimedJointBitErrors',NaN,'RetimedJointPresenceDetected',NaN,'RetimedJointWordPosterior',NaN, ...
        'OriginalWhitenedPresenceDetected',originalWhitened.Detected, ...
        'OriginalWhitenedCorrelation',originalWhitened.Correlation, ...
        'OriginalWhitenedThreshold',originalWhitened.CorrelationThreshold, ...
        'OriginalWhitenedSearchBound',originalWhitened.SearchFalseAlarmBound, ...
        'RetimedWhitenedPresenceDetected',NaN,'RetimedWhitenedCorrelation',NaN, ...
        'RetimedWhitenedThreshold',NaN,'RetimedWhitenedSearchBound',NaN, ...
        'CandidatePilotNoiseModelEstablished',false,'CandidatePolicyInstalled',false);
    if ~isempty(reference)
        [aligned,timing]=reference.alignCompletedObservation(c.Config,buffer,slot0);
        assert(reference.AvailableAtSample<=buffer.StartSample && ...
            ~timing.OracleTimingUsed && ~timing.ReceiverZeroPaddingUsed, ...
            'test:IndependentPriorRequired','This comparison requires a prior-slot received clock.');
        [threshold,~]=sixgr.phy.pucch.resolveDetectionThreshold( ...
            c.Assignment,c.Config.phy.pucch.receiverDetectionThresholds);
        rx=sixgr.phy.pucch.PUCCHReceiver.receive(aligned,carrier,c.Assignment,c.Context, ...
            'NoiseVariance',NaN,'NoiseVarianceMode','received_dmrs_estimate', ...
            'ChannelProfile',sixgr.channel.resolveConcreteProfile(c.Config),'DetectionThreshold',threshold);
        [llr,evidence]=sixgr.phy.pucch.demapFormat2EqualizerOutput( ...
            carrier,resource,rx.EqualizerInfo.EqualizerResult);
        decoded=sixgr.phy.pucch.UCIDecoder.decode(llr,count);
        confidence=sixgr.phy.ul.pusch.shortUCICodewordConfidence(llr,decoded.Bits,count,"QPSK",wordPolicy);
        grid=sixgr.phy.waveform.ofdmDemodulate(carrier,aligned);
        % One independently placed FFT: no current PUCCH timing search.
        presence=sixgr.phy.pucch.detectFormat2DMRSPresence(carrier,resource,grid,p.target_model_probability,1);
        joint=sixgr.phy.pucch.decodeFormat2FlatShortUCI(carrier,resource,grid, ...
            count,p.target_model_probability,1);
        whitened=sixgr.phy.pucch.detectFormat2EqualizedWhiteNoisePresence( ...
            carrier,resource,rx.EqualizerInfo.EqualizerResult, ...
            count,p.target_model_probability,1);
        assert(~evidence.TransmittedBitsUsed && ~confidence.SignalPresenceQualified);
        % TX audit is consulted only after timing, demapping and decisions.
        expected=int8(char(trials.UCIExpectedBitVector(k)).'-'0');
        old=[c.ReceivedResult.DecodedSequence1;c.ReceivedResult.DecodedSequence2];
        retimed=[rx.DecodedSequence1;rx.DecodedSequence2];
        assert(numel(expected)==count && numel(old)==count && numel(retimed)==count);
        row.OriginalBitErrors=nnz(old~=expected); row.RetimedBitErrors=nnz(retimed~=expected);
        row.RetimedGainAwareBitErrors=nnz(decoded.Bits~=expected);
        row.RetimedConditionalWordPosterior=confidence.SelectedPosterior;
        row.PriorOffsetSamples=timing.AppliedTimingCorrectionSamples;
        row.PriorAgeSlots=timing.ReferenceAgeSlots;
        row.ReferenceAvailableAtSample=reference.AvailableAtSample;
        row.RetimedPilotCorrelation=presence.Correlation;
        row.RetimedPilotThreshold=presence.CorrelationThreshold;
        row.RetimedPilotDetected=double(presence.Detected);
        row.RetimedJointBitErrors=nnz(joint.Bits~=expected);
        row.RetimedJointPresenceDetected=double(joint.JointPresenceDecision.Detected);
        row.RetimedJointWordPosterior=joint.ConditionalWordPosterior;
        row.RetimedWhitenedPresenceDetected=double(whitened.Detected);
        row.RetimedWhitenedCorrelation=whitened.Correlation;
        row.RetimedWhitenedThreshold=whitened.CorrelationThreshold;
        row.RetimedWhitenedSearchBound=whitened.SearchFalseAlarmBound;
    end
    % Every inference is finished before the retained TX scoring bits enter.
    expected=int8(char(trials.UCIExpectedBitVector(k)).'-'0');
    row.OriginalJointBitErrors=nnz(originalJoint.Bits~=expected);
    rows=[rows;struct2table(row)]; %#ok<AGROW>
    writetable(rows,fullfile(outputRoot,'received_clock_comparison.csv'));
end
sixgr.util.jsonWrite(fullfile(outputRoot,'scope.json'),struct( ...
    'SourceRun',string(runFolder),'Scope',"actual_received_IQ_retiming_component_not_runtime_acceptance", ...
    'MATLABVersion',version,'TransmittedTimingUsed',false,'SamplesRegenerated',false, ...
    'ThresholdTuned',false,'DetectorQualified',false,'CandidatePolicyInstalled',false, ...
    'JointDecoderSHA256',sixgr.util.sha256File(which('sixgr.phy.pucch.decodeFormat2FlatShortUCI')), ...
    'WhitenedPresenceSHA256',sixgr.util.sha256File(which('sixgr.phy.pucch.detectFormat2EqualizedWhiteNoisePresence')), ...
    'PolicySHA256',sixgr.util.sha256File(fullfile('simulator','configs','validation','pucch_short_uci_null_math.yaml'))));
disp(rows);
fprintf('PUCCH_RECEIVED_CLOCK_REPLAY_COMPLETE rows=%d usable_priors=%d qualification=0\n',height(rows),nnz(rows.PriorAvailable));
end
function c=readCapture(entry,outputRoot,name)
source=fullfile(entry.folder,entry.name); hash=sixgr.util.sha256File(source);
target=fullfile(outputRoot,name+".mat");
assert(~isfile(target)); [ok,message]=copyfile(source,target); assert(ok,'%s',message);
assert(sixgr.util.sha256File(target)==hash,'test:CaptureChanged','Preserve exact recorded bytes.');
x=load(target,'capture'); c=x.capture;
end
function buffer=makeBuffer(samples,first,last,fs)
buffer=sixgr.phy.waveform.WaveformObservationBuffer(first,last,fs,size(samples,2));
buffer.append(sixgr.phy.waveform.WaveformChunk(samples,first),fs);
end
