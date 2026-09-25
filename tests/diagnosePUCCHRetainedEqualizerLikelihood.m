function rows=diagnosePUCCHRetainedEqualizerLikelihood(runFolder,outputRoot)
% Actual retained EQ observations, not waveform re-execution/qualification.
% Production receiver policy is untouched. TX bits are only error-scoring data.
assert(~isfolder(outputRoot),'test:EvidenceExists','Preserve earlier replay evidence.');
p=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs','validation', ...
    'pucch_short_uci_null_math.yaml'));
policy=struct('algorithm',string(p.candidate_word_algorithm), ...
    'minimumPosterior',p.candidate_word_minimum_posterior);
trialPath=fullfile(runFolder,'air_interface','csv','pucch_trials.csv');
options=detectImportOptions(trialPath,'TextType','string');
options=setvartype(options,'UCIExpectedBitVector','string');
trials=readtable(trialPath,options);
captures=dir(fullfile(runFolder,'**','pucch_rx_*.mat'));
assert(~isempty(trials) && ~isempty(captures),'test:MissingRetainedPUCCH','Actual receiver observations required.');
mkdir(outputRoot); rows=table();
for k=1:height(trials)
    digest=string(trials.ReceiverContextDigest(k));
    hit=find(endsWith(string({captures.name}),"_"+digest+".mat"));
    assert(isscalar(hit),'test:AmbiguousRetainedPUCCH','Require one capture for the receive context.');
    path=fullfile(captures(hit).folder,captures(hit).name);
    captureHash=sixgr.util.sha256File(path);
    readPath=path;
    if ispc && strlength(string(path))>=248
        % MATLAB's HDF5 backend cannot open some otherwise valid long paths.
        % Preserve a byte-identical short-path copy, never regenerate samples.
        readPath=fullfile(outputRoot,sprintf('capture_%03d.mat',k));
        assert(strlength(sixgr.util.canonicalPath(readPath))<248 && ~isfile(readPath), ...
            'test:ShortReplayPathRequired','Choose a short new diagnostic output directory.');
        [copied,message]=copyfile(path,readPath);
        assert(copied,'test:CaptureCopyFailed','%s',message);
        assert(sixgr.util.sha256File(readPath)==captureHash, ...
            'test:CaptureCopyMismatch','Replay copy must contain the identical captured bytes.');
    end
    loaded=load(readPath,'capture'); c=loaded.capture; rx=c.ReceivedResult;
    assert(isa(c.Assignment,'sixgr.phy.pucch.PUCCHReceptionAssignment') && ...
        c.Assignment.Format==2 && c.Context.Digest==digest && ...
        c.Assignment.ReportContextDigest==digest && rx.ReportContextDigest==digest, ...
        'test:RetainedPUCCHIdentityMismatch','Do not infer the resource from transmitted data.');
    carrier=sixgr.phy.grid.makeCarrier(c.Config);
    slot=double(c.Assignment.Data.AbsoluteSlot0);
    carrier.NSlot=mod(slot,double(carrier.SlotsPerFrame));
    carrier.NFrame=floor(slot/double(carrier.SlotsPerFrame));
    resource=c.Assignment.Resource.toolboxConfig();
    count=c.Context.Sequence1Length+c.Context.Sequence2Length;
    assert(count>=3 && count<=11,'test:RetainedShortUCIRequired', ...
        'This conditional short-codeword replay covers 3--11 information bits.');
    result=rx.EqualizerInfo.EqualizerResult;
    [oldSoft,~,metric]=nrPUCCHDecode(carrier,resource,count,result.EqualizedSymbols, ...
        rx.DecodeNoiseInterferenceVariance,'DetectionThreshold',rx.DetectionThreshold);
    old=sixgr.phy.pucch.UCIDecoder.decode(oldSoft{1},count);
    assert(isequal(old.Bits,[rx.DecodedSequence1;rx.DecodedSequence2]) && ...
        abs(metric-rx.DetectionMetric)<1e-12, ...
        'test:RetainedPUCCHReplayMismatch','First reproduce the actual retained decoder and detector.');
    [llr,demapEvidence]=sixgr.phy.pucch.demapFormat2EqualizerOutput(carrier,resource,result);
    corrected=sixgr.phy.pucch.UCIDecoder.decode(llr,count);
    previous=sixgr.phy.ul.pusch.shortUCICodewordConfidence(oldSoft{1},old.Bits,count,"QPSK",policy);
    confidence=sixgr.phy.ul.pusch.shortUCICodewordConfidence(llr,corrected.Bits,count,"QPSK",policy);
    assert(~corrected.CRCApplicable && ~confidence.SignalPresenceQualified && ...
        ~demapEvidence.TransmittedBitsUsed && ~demapEvidence.SignalPresenceDecisionMade);
    % Inspect pilot-only presence independently of UCI confidence. Repeat
    % the actual bounded timing search, and count every examined lag.
    dmrs=sixgr.phy.pucch.PUCCHDMRS.generate(carrier,c.Assignment.Resource);
    window=rx.ReceiveTiming.SearchWindowSamples;
    [aligned,timing]=sixgr.phy.sync.alignULReferenceObservation( ...
        carrier,c.ReceiverInputSamples,dmrs.Indices,dmrs.Symbols,window);
    assert(timing.TimingOffsetSamples==rx.ReceiveTiming.TimingOffsetSamples, ...
        'test:RetainedPilotTimingMismatch','Retained samples must reproduce acquired timing.');
    grid=sixgr.phy.waveform.ofdmDemodulate(carrier,aligned);
    presence=sixgr.phy.pucch.detectFormat2DMRSPresence( ...
        carrier,resource,grid,p.target_model_probability,diff(window)+1);
    % Transmitted audit enters only after all receiver calculations above.
    expected=char(string(trials.UCIExpectedBitVector(k)));
    assert(numel(expected)==count && all(ismember(expected,'01')));
    expected=int8(expected(:)-'0');
    row=table(trials.Slot(k),count,numel(result.EqualizedSymbols), ...
        string(char(double(old.Bits(:).')+'0')),nnz(old.Bits~=expected), ...
        previous.SelectedPosterior,previous.Accepted, ...
        string(char(double(corrected.Bits(:).')+'0')),nnz(corrected.Bits~=expected), ...
        confidence.SelectedPosterior,confidence.Accepted,true,captureHash, ...
        'VariableNames',{'Slot','PayloadBits','SymbolCount','IndependentDecodedBits','BitErrors', ...
        'ConditionalWordPosterior','CandidateWordAccepted','EqualizerAwareDecodedBits', ...
        'EqualizerAwareBitErrors','EqualizerAwareConditionalWordPosterior', ...
        'EqualizerAwareCandidateWordAccepted','DecoderAndMetricReplayMatch','CaptureSHA256'});
    row.CandidatePilotCorrelation=presence.Correlation;
    row.CandidatePilotCorrelationThreshold=presence.CorrelationThreshold;
    row.CandidatePilotSearchFalseAlarmBound=presence.SearchFalseAlarmBound;
    row.CandidatePilotHypothesisCount=presence.HypothesisCount;
    row.CandidatePilotDetected=presence.Detected;
    row.CandidatePilotNoiseModelEstablished=false;
    rows=[rows;row]; %#ok<AGROW>
    writetable(rows,fullfile(outputRoot,'receiver_symbol_analysis.csv'));
end
sixgr.util.jsonWrite(fullfile(outputRoot,'scope.json'),struct( ...
    'Scope',"retained_receiver_equalizer_redecode_not_new_waveform_execution", ...
    'SourceRun',string(runFolder),'MATLABVersion',version,'TrialCount',height(rows), ...
    'CandidatePolicyInstalled',false,'DetectorQualified',false,'ThresholdTuned',false, ...
    'PilotPresenceScope',"conditional_white_noise_model_diagnostic_not_runtime_acceptance", ...
    'PilotNoiseModelEstablishedByReplay',false, ...
    'PolicySHA256',sixgr.util.sha256File(fullfile('simulator','configs','validation', ...
        'pucch_short_uci_null_math.yaml'))));
disp(rows);
fprintf('PUCCH_RETAINED_EQUALIZER_REDECODE_COMPLETE cases=%d qualification=0 runtime_changed=0\n',height(rows));
end
