function row=scoreIndependentPUCCHReceiverEpisode(context,rx,tx,execution)
% Offline scoring AFTER receiver execution; references never enter the RX.
% One waveform is one event. HARQ bits/candidates are NOT independent trials.
% Different valid TX/RX field layouts are outcomes, not repairable prefixes.
arguments
    context (1,1) sixgr.phy.pucch.UCIReportContext
    rx (1,1) struct
    tx struct
    execution (1,1) struct
end
id='sixgr:link:InvalidPUCCHEpisodeScoring';
required=["EpisodeID","Scope","SignalPresent","TransmitterExecuted", ...
    "DesiredChannelExecuted","ReceiverContextDigest","ReceiverAssignmentDigest"];
assert(all(isfield(execution,required)),id,'Execution identity is required.');
for name=["SignalPresent","TransmitterExecuted","DesiredChannelExecuted"]
    value=execution.(name);
    assert(islogical(value) && isscalar(value),id,'Execution flags must be logical scalars.');
end
present=execution.SignalPresent;
assert(present==~isempty(tx) && present==execution.TransmitterExecuted && ...
    present==execution.DesiredChannelExecuted && (isempty(tx)||isscalar(tx)),id, ...
    'Absent-transmitter scoring cannot consume a hidden transmitter reference.');
assert(execution.Scope=="installed_single_occasion_independent_reset_not_continuous_runtime" && ...
    execution.ReceiverContextDigest==context.Digest && ...
    rx.ReportContextDigest==context.Digest && ...
    rx.AssignmentDigest==execution.ReceiverAssignmentDigest,id, ...
    'Score only the frozen receive hypothesis that actually executed.');
names=["HARQACK","SR","CSIPart1","CSIPart2"];
owners=["HARQ_ACK","SR","CSI_PART1","CSI_PART2"];
counts=[context.HARQACKBits context.SRBits context.CSIPart1Bits context.CSIPart2Bits];
decoded=cell(1,4);
for k=1:4
    assert(isfield(rx.DecodedFields,names(k)),id,'Missing decoded field %s.',names(k));
    value=rx.DecodedFields.(names(k));
    assert((isnumeric(value)||islogical(value)) && isreal(value) && ...
        (isempty(value)||isvector(value)) && all(isfinite(value(:))) && ...
        all(value(:)==0|value(:)==1),id,'Decoded fields must contain actual binary values.');
    decoded{k}=int8(value(:));
end
harq=sixgr.phy.pucch.harqObservationEvidence(context,rx);
complete=all(cellfun(@numel,decoded)==counts);
accepted=logical(rx.ReceiverUsable && ~rx.DTX && ...
    (~rx.CRCApplicable || rx.CRCPassed) && complete);
falseDetection=NaN; falseAcceptance=NaN; falseACK=NaN;
falseACKBits=NaN; falseNACKBits=NaN; missedHARQ=NaN;
layoutMatch=NaN; exact=NaN; uciError=NaN;
if present
    sixgr.phy.pucch.validateTransmitUCILayout(tx.Report,tx.Serialization);
    layout=tx.Serialization.Layout;
    expected=cell(1,4);
    for k=1:4
        expected{k}=int8(layout.BitValue(string(layout.BitOwner)==owners(k)));
        expected{k}=expected{k}(:);
    end
    layoutMatch=double(all(cellfun(@numel,expected)==counts));
    exact=double(all(cellfun(@isequal,decoded,expected)));
    uciError=double(~(accepted && exact));
    if counts(1)>0 && numel(expected{1})==counts(1)
        missedHARQ=double(~harq.HARQObservationValid);
        % A DTX/CRC erasure produces no actionable false ACK. Keep it in
        % the episode denominator; it is NOT a zero-bit decoding error.
        falseACK=0;
        if harq.HARQObservationValid
            falseACKBits=double(nnz(decoded{1}==1 & expected{1}==0));
            falseNACKBits=double(nnz(decoded{1}==0 & expected{1}==1));
            falseACK=double(falseACKBits>0);
        end
    end
else
    falseDetection=double(~rx.DTX);
    falseAcceptance=double(accepted);
    if counts(1)>0
        falseACKBits=0;
        if harq.HARQObservationValid
            falseACKBits=harq.ObservedHARQACKBitCount;
        end
        falseACK=double(falseACKBits>0);
    end
end
row=table(string(execution.EpisodeID),present,string(execution.Scope), ...
    string(execution.ReceiverAssignmentDigest),string(context.Digest), ...
    "independent_receiver_waveform",1,false, ...
    double(rx.DetectionMetric),double(rx.DetectionThreshold),logical(rx.DTX), ...
    logical(rx.CRCApplicable),logical(rx.CRCPassed),accepted, ...
    counts(1),harq.HARQObservationValid,layoutMatch,exact,uciError, ...
    falseDetection,falseAcceptance,falseACK,falseACKBits,falseNACKBits,missedHARQ,false, ...
    'VariableNames',{'EpisodeID','SignalPresent','Scope','ReceiverAssignmentDigest', ...
    'ReceiverContextDigest','EvidenceUnit','IndependentWaveformCount', ...
    'HARQBitsAreIndependentTrials','DetectionMetric','DetectionThreshold','DTX', ...
    'CRCApplicable','CRCPassed','UCIReceptionAccepted','ExpectedHARQBits', ...
    'HARQObservationValid','TXRXFieldLengthsMatch','ExactDecodedFields', ...
    'CompleteUCIErrorEpisode','FalseDetectionEpisode','FalseAcceptanceEpisode', ...
    'FalseACKEpisode','FalseACKBitCount','FalseNACKBitCount','MissedHARQEpisode', ...
    'StatisticallyQualified'});
end
