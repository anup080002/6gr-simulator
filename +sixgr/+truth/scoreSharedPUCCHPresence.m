function score=scoreSharedPUCCHPresence(item,rx,epoch)
% Post-reception audit only. Never an input to decoding or feedback delivery.
% Component receipts prove emission, not arrival. Link-composite counts
% include RF/channel tails and cannot isolate PUCCH from another component.
id='sixgr:truth:InvalidPUCCHPresenceEvidence';
c=item.Context; h=c.GNBReception;
assert(string(item.ID)==string(c.ObservationID) && ...
    string(item.ID)==string(h.Assignment.Data.ObservationID) && ...
    h.Assignment.Data.RNTI==h.RNTI && h.UEIndex==item.UE && ...
    h.Assignment.Data.AbsoluteSlot0+1==c.Slot && ...
    rx.AssignmentDigest==h.Assignment.Digest && rx.ReportContextDigest==h.Context.Digest,id, ...
    'Scoring must bind the actual observation and frozen receive hypothesis.');
[physicalID,queueKey,occasionSource]=sixgr.truth.sharedPUCCHReceiverOccasionIdentity(item);
txID="ue_"+item.UE; rxID="gnb_"+h.ServingCell+"_rx";
names=string({item.Planes.ReceiverID});
t=find(names==txID+":tx"); r=find(names==rxID+":post_rf");
assert(isscalar(t) && isscalar(r),id,'Require actual TX audit and RX capture planes.');
tx=item.Planes(t).Observation; post=item.Planes(r).Observation;
assert(tx.isComplete() && post.isComplete() && tx.SampleRateHz==post.SampleRateHz && ...
    rx.ReceiverObservationStartSample==post.StartSample && ...
    rx.ReceiverObservationEndSampleExclusive==post.EndSampleExclusive && ...
    rx.ReceiverObservationSampleRateHz==post.SampleRateHz,id,'Scoring clocks must match actual RX samples.');
schema=h.Context.Data;
schema=rmfield(schema,'ReportID');
evidence=struct('Schema',"shared_PUCCH_presence_receipts/v1", ...
    'ObservationID',string(item.ID),'ConfigurationEpoch',epoch, ...
    'PhysicalOccasionID',physicalID,'QueueKey',queueKey,'OccasionIdentitySource',occasionSource, ...
    'ReceiverAssignmentDigest',string(h.Assignment.Digest),'ReceiverContextDigest',string(h.Context.Digest), ...
    'SampleRateHz',post.SampleRateHz,'TXStartSample',tx.StartSample,'TXEndSampleExclusive',tx.EndSampleExclusive, ...
    'RXStartSample',post.StartSample,'RXEndSampleExclusive',post.EndSampleExclusive, ...
    'TXSegments',{localRetainedSegments(item.Planes(t).Segments)}, ...
    'RXSegments',{localRetainedSegments(item.Planes(r).Segments)});
evidenceJSON=string(jsonencode(evidence));
score=struct('SignalPresent',NaN,'TrialType',"unknown_signal_presence", ...
    'FalseAlarmFlag',NaN,'FalseAcceptanceFlag',NaN, ...
    'PresenceScoringStatus',"unavailable_legacy_execution_receipts", ...
    'PresenceScoringSource',"post_receiver_executed_components_and_link_contributions/v1", ...
    'PresenceObservationID',string(item.ID),'PresenceConfigurationEpoch',epoch, ...
    'PresenceUEIndex',item.UE,'PresenceRNTI',h.RNTI,'PresenceServingCell',h.ServingCell, ...
    'PresencePhysicalOccasionID',physicalID, ...
    'PresenceReceiverAssignmentDigest',string(h.Assignment.Digest), ...
    'PresenceReceiverContextDigest',string(h.Context.Digest), ...
    'PresenceReceiverSchemaDigest',sixgr.phy.pucch.PUCCHUtil.hash(schema), ...
    'PresenceReceiverResourceDigest',string(h.Assignment.Resource.Digest), ...
    'PresenceEvidenceJSON',evidenceJSON, ...
    'PresenceEvidenceSHA256',sixgr.phy.pucch.PUCCHUtil.hash(evidenceJSON), ...
    'PresenceTXStartSample',tx.StartSample,'PresenceTXEndSampleExclusive',tx.EndSampleExclusive, ...
    'PresenceRXStartSample',post.StartSample,'PresenceRXEndSampleExclusive',post.EndSampleExclusive, ...
    'PresenceSampleRateHz',post.SampleRateHz,'PresenceTargetNonzeroInputSamples',NaN, ...
    'PresenceNonzeroCountUnit',"complex_sample_by_physical_chain", ...
    'PresenceReceiverBackground',"unknown",'PresenceObservationCount',1, ...
    'PresenceIndependentTrialsEstablished',false,'PresenceScoringUsedByReceiver',false);
[complete,emitted]=localTX(item.Planes(t).Segments,tx,txID,string(item.ID),epoch,id);
if ~complete, return; end
[complete,background]=localRX(item.Planes(r).Segments,post,rxID,epoch,id);
if ~complete, return; end
score.SignalPresent=double(emitted>0);
score.PresenceTargetNonzeroInputSamples=emitted;
score.PresenceReceiverBackground=background;
score.PresenceScoringStatus="observed_executed_component_presence";
if emitted>0
    % A transmitted target in a deep null remains H1.
    score.TrialType="signal_present";
else
    score.TrialType="target_absent_with_background";
    if background=="all_link_contributions_exactly_zero"
        score.TrialType="no_signal_before_receiver_noise_and_RF";
    elseif background=="nonzero_covering_interval_exact_capture_location_unknown"
        score.TrialType="target_absent_receiver_background_unknown";
    end
    assert(isfield(rx,'DetectionOutcome') && ...
        any(string(rx.DetectionOutcome)==["detected","dtx","unavailable"]),id, ...
        'Use the executed presence decision, not CRC or transmitter knowledge.');
    if any(string(rx.DetectionOutcome)==["detected","dtx"])
        score.FalseAlarmFlag=double(string(rx.DetectionOutcome)=="detected");
        names=["HARQACK","SR","CSIPart1","CSIPart2"];
        counts=[h.Context.HARQACKBits h.Context.SRBits h.Context.CSIPart1Bits h.Context.CSIPart2Bits];
        complete=true;
        for k=1:4
            assert(isfield(rx.DecodedFields,names(k)),id,'Retain actual decoded fields.');
            bits=rx.DecodedFields.(names(k));
            assert((isnumeric(bits)||islogical(bits)) && isreal(bits) && ...
                (isempty(bits)||isvector(bits)) && all(isfinite(bits(:))) && all(bits(:)==0|bits(:)==1), ...
                id,'Retain binary receiver outputs, not intended payload bits.');
            complete=complete && numel(bits)==counts(k);
        end
        score.FalseAcceptanceFlag=double(rx.ReceiverUsable && ~rx.DTX && ...
            (~rx.CRCApplicable || rx.CRCPassed) && complete);
    end
end
end

function retained=localRetainedSegments(segments)
% Metadata only: never pin channel tensors or copy waveform samples into CSV.
retained=cell(size(segments));
for k=1:numel(segments)
    s=segments{k}; e=s.Execution;
    entry=struct('StartSample',s.StartSample,'EndSampleExclusive',s.EndSampleExclusive);
    for name=["StartSample","EndSampleExclusive","ConfigurationEpoch","SampleRateHz", ...
            "ExecutedContributors","SignalContributions"]
        if isfield(e,name), entry.(name)=e.(name); end
    end
    if isfield(e,'Links')
        entry.Links=struct('ID',{},'TX',{},'RX',{});
        for link=reshape(e.Links,1,[])
            entry.Links(end+1)=struct('ID',link.ID,'TX',link.TX,'RX',link.RX); %#ok<AGROW>
        end
    end
    if isfield(e,'RX'), entry.ReceiverIDs=string({e.RX.ID}); end
    retained{k}=entry;
end
end

function [complete,count]=localTX(segments,observation,txID,targetID,epoch,id)
complete=false; count=0; cursor=observation.StartSample;
for k=1:numel(segments)
    s=segments{k}; e=s.Execution;
    if ~all(isfield(e,{'ExecutedContributors','ConfigurationEpoch','SampleRateHz'})), return; end
    [lo,hi]=localBounds(s,observation,cursor,epoch,id);
    cursor=hi;
    roster=e.ExecutedContributors;
    assert(numel(unique(string({roster.TransmitterID})))==numel(roster),id,'Duplicate executed transmitter.');
    hit=find(string({roster.TransmitterID})==txID);
    assert(isscalar(hit),id,'The complete physical roster must contain the monitored UE.');
    entry=roster(hit); receipt=entry.Receipt;
    assert(receipt.Schema=="consumed_waveform_components/v1" && receipt.CompleteContributorList && ...
        receipt.StartSample==s.StartSample && receipt.EndSampleExclusive==s.EndSampleExclusive && ...
        receipt.SampleRateHz==observation.SampleRateHz && ...
        entry.CommittedThroughSample>=s.EndSampleExclusive,id,'Uncommitted/incomplete contributor evidence.');
    components=receipt.Components;
    assert(numel(unique(string({components.ComponentID})))==numel(components),id,'Duplicate component receipt.');
    for component=reshape(components,1,[])
        assert(component.StartSample>=s.StartSample && component.EndSampleExclusive<=s.EndSampleExclusive && ...
            component.StartSample<component.EndSampleExclusive && ...
            isfinite(component.NonzeroSampleCount) && component.NonzeroSampleCount>=0 && ...
            component.NonzeroSampleCount==fix(component.NonzeroSampleCount) && ...
            strlength(string(component.OriginalSampleSHA256))>0,id,'Invalid component consumption record.');
        if string(component.ComponentID)~=targetID, continue; end
        % Do not proportionally assign a segment count to a partial window.
        assert(component.StartSample>=lo && component.EndSampleExclusive<=hi,id, ...
            'Target component extent must lie within its registered TX audit capture.');
        count=count+component.NonzeroSampleCount;
    end
end
assert(cursor==observation.EndSampleExclusive,id,'Missing contributor interval at capture end.');
complete=true;
end

function [complete,background]=localRX(segments,observation,rxID,epoch,id)
complete=false; background="all_link_contributions_exactly_zero";
knownBackground=false; uncertainBackground=false;
cursor=observation.StartSample;
for k=1:numel(segments)
    s=segments{k}; e=s.Execution;
    if ~all(isfield(e,{'SignalContributions','ConfigurationEpoch','SampleRateHz','RX','Links'})), return; end
    [lo,hi]=localBounds(s,observation,cursor,epoch,id); cursor=hi;
    assert(nnz(string({e.RX.ID})==rxID)==1,id,'The actual receiver must have executed.');
    links=e.Links; contributions=e.SignalContributions;
    assert(numel(contributions)==numel(links) && ...
        numel(unique(string({contributions.LinkID})))==numel(contributions),id, ...
        'Retain the full physically executed link roster, including zero contributions.');
    for p=reshape(contributions,1,[])
        hit=find(string({links.ID})==string(p.LinkID));
        assert(isscalar(hit) && p.TX==links(hit).TX && p.RX==links(hit).RX && ...
            p.Source=="actual_link_after_TX_RF_channel_loss_before_noise_RX_RF" && ...
            isfinite(p.NonzeroSampleCount) && p.NonzeroSampleCount>=0 && ...
            p.NonzeroSampleCount==fix(p.NonzeroSampleCount) && ...
            isfinite(p.SampleCount) && p.SampleCount>0 && p.SampleCount==fix(p.SampleCount) && ...
            p.NonzeroSampleCount<=p.SampleCount,id,'Invalid executed link contribution.');
        if string(p.RX)~=rxID || p.NonzeroSampleCount==0, continue; end
        if lo~=s.StartSample || hi~=s.EndSampleExclusive
            % Zero on a covering interval proves zero on its subset. A
            % nonzero covering interval does not locate its nonzero samples.
            uncertainBackground=true;
        else
            knownBackground=true;
        end
    end
end
assert(cursor==observation.EndSampleExclusive,id,'Missing link contribution interval at capture end.');
if knownBackground
    background="nonzero_link_contribution_in_capture";
elseif uncertainBackground
    background="nonzero_covering_interval_exact_capture_location_unknown";
end
complete=true;
end

function [lo,hi]=localBounds(s,observation,cursor,epoch,id)
e=s.Execution;
assert(s.StartSample==e.StartSample && s.EndSampleExclusive==e.EndSampleExclusive && ...
    e.ConfigurationEpoch==epoch && e.SampleRateHz==observation.SampleRateHz && ...
    isfinite(s.StartSample) && isfinite(s.EndSampleExclusive) && ...
    s.StartSample<s.EndSampleExclusive,id,'Wrong execution clock or epoch.');
lo=max(s.StartSample,observation.StartSample); hi=min(s.EndSampleExclusive,observation.EndSampleExclusive);
assert(lo==cursor && hi>lo,id,'Receipt intervals must cover the capture exactly once without gaps.');
end
