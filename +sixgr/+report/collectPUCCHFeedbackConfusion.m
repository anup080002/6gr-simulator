function out=collectPUCCHFeedbackConfusion(T,mode)
% Post-receiver scoring. A receiver DTX verdict is NEVER transmitted absence.
% This consumes scoreSharedPUCCHPresence's original receipt; no RF executes.
arguments
    T table
    mode (1,1) string {mustBeMember(mode,["DTX_TO_ACK","NACK_TO_ACK"])}
end
out=struct('Mode',mode,'Status',"NOT_EXERCISED",'Reason',"no_independent_eligible_episodes", ...
    'Numerator',0,'Denominator',0,'Rate',NaN,'ExcludedRows',0, ...
    'Population',"physical_receive_episodes",'StatisticallyQualified',false, ...
    'EvidenceSource',"original_shared_PUCCH_presence_receipts/v1", ...
    'EligibleRowIndices',zeros(0,1),'ErrorIndicators',false(0,1));
seen=strings(0,1);
for k=1:height(T)
    r=table2struct(T(k,:));
    [usable,key]=presence(r);
    if ~usable, out.ExcludedRows=out.ExcludedRows+1; continue; end
    assert(~any(seen==key),'sixgr:report:DuplicateFeedbackEpisode', ...
        'Do not count a physical observation twice.');
    seen(end+1,1)=key; %#ok<AGROW>
    ack=number(r,'ObservedHARQACKBitCount');
    if ~isfinite(ack)||ack<0||ack~=fix(ack)
        out.ExcludedRows=out.ExcludedRows+1; continue;
    end
    if mode=="DTX_TO_ACK"
        eligible=number(r,'SignalPresent')==0;
        errorEvent=ack>0;
    else
        % Legacy scalar ExpectedAck cannot represent a multi-bit codebook.
        eligible=number(r,'SignalPresent')==1 && ...
            number(r,'ReceiverExpectedHARQBitCount')==1 && number(r,'ExpectedAck')==0;
        errorEvent=ack==1;
    end
    if eligible
        out.Denominator=out.Denominator+1;
        out.Numerator=out.Numerator+double(errorEvent);
        out.EligibleRowIndices(end+1,1)=k;
        out.ErrorIndicators(end+1,1)=logical(errorEvent);
    end
end
if out.Denominator>0
    out.Status="PASS"; out.Reason="original_population_accounted_not_zero_error_requirement";
    out.Rate=out.Numerator/out.Denominator;
end
end

function [ok,key]=presence(r)
ok=false; key="";
req=["PresenceScoringStatus","PresenceEvidenceJSON","PresenceEvidenceSHA256", ...
    "PresenceObservationID","PresenceReceiverAssignmentDigest", ...
    "PresenceReceiverContextDigest","PresenceConfigurationEpoch", ...
    "PresenceRXStartSample","PresenceRXEndSampleExclusive","PresenceSampleRateHz", ...
    "PresenceScoringUsedByReceiver","SignalPresent","UEIndex","RNTI", ...
    "ReceiverAssignmentDigest","ReceiverContextDigest","ObservationStartSample", ...
    "ObservationEndSampleExclusive","ObservationSampleRateHz","PhysicalPUCCHOccasionId"];
if ~all(isfield(r,cellstr(req))), return; end
if string(r.PresenceScoringStatus)~="observed_executed_component_presence", return; end
id='sixgr:report:FeedbackPresenceAuthorityMismatch';
raw=string(r.PresenceEvidenceJSON);
assert(isscalar(raw)&&~ismissing(raw)&&strlength(raw)>0,id,'Retain original presence evidence.');
assert(sixgr.phy.pucch.PUCCHUtil.hash(raw)==string(r.PresenceEvidenceSHA256),id, ...
    'Presence receipt bytes changed.');
e=jsondecode(raw);
assert(number(r,'UEIndex')==number(r,'PresenceUEIndex') && ...
    number(r,'RNTI')==number(r,'PresenceRNTI') && ...
    number(r,'ObservationStartSample')==number(r,'PresenceRXStartSample') && ...
    number(r,'ObservationEndSampleExclusive')==number(r,'PresenceRXEndSampleExclusive') && ...
    number(r,'ObservationSampleRateHz')==number(r,'PresenceSampleRateHz') && ...
    string(r.ReceiverAssignmentDigest)==string(r.PresenceReceiverAssignmentDigest) && ...
    string(r.ReceiverContextDigest)==string(r.PresenceReceiverContextDigest) && ...
    string(r.PhysicalPUCCHOccasionId)==string(e.PhysicalOccasionID),id, ...
    'Presence proof belongs to a different completed receiver episode.');
assert(string(e.Schema)=="shared_PUCCH_presence_receipts/v1" && ...
    isfield(e,'TXSegments')&&~isempty(e.TXSegments)&& ...
    isfield(e,'RXSegments')&&~isempty(e.RXSegments),id,'Require actual TX and RX receipt populations.');
for pair=["ObservationID","PresenceObservationID"; ...
        "ReceiverAssignmentDigest","PresenceReceiverAssignmentDigest"; ...
        "ReceiverContextDigest","PresenceReceiverContextDigest"].'
    assert(string(e.(pair(1)))==string(r.(pair(2))),id,'Receiver identity differs from presence receipt.');
end
for pair=["ConfigurationEpoch","PresenceConfigurationEpoch"; ...
        "RXStartSample","PresenceRXStartSample"; ...
        "RXEndSampleExclusive","PresenceRXEndSampleExclusive"; ...
        "SampleRateHz","PresenceSampleRateHz"].'
    assert(isfinite(number(r,pair(2)))&&double(e.(pair(1)))==number(r,pair(2)),id, ...
        'Capture clock differs from original presence receipt.');
end
assert(number(r,'PresenceScoringUsedByReceiver')==0 && ...
    any(number(r,'SignalPresent')==[0 1]),id,'Require independent finite presence scoring.');
% Bind presence to the original emitted target population, not rx.DTX.
count=number(r,'PresenceTargetNonzeroInputSamples');
assert(isfinite(count)&&count>=0&&count==fix(count)&& ...
    number(r,'SignalPresent')==double(count>0),id,'Presence and consumed target count disagree.');
segments=e.TXSegments; if iscell(segments), segments=[segments{:}]; end
cursor=double(e.TXStartSample); originalCount=0;
for s=reshape(segments,1,[])
    lo=max(s.StartSample,e.TXStartSample); hi=min(s.EndSampleExclusive,e.TXEndSampleExclusive);
    assert(lo==cursor && hi>lo && ...
        s.ConfigurationEpoch==e.ConfigurationEpoch && s.SampleRateHz==e.SampleRateHz,id, ...
        'Require contiguous original TX audit coverage.');
    roster=s.ExecutedContributors;
    target="ue_"+string(number(r,'PresenceUEIndex'));
    hit=find(string({roster.TransmitterID})==target);
    assert(isscalar(hit),id,'Original roster must contain exactly one target transmitter.');
    receipt=roster(hit).Receipt;
    assert(string(receipt.Schema)=="consumed_waveform_components/v1" && ...
        receipt.CompleteContributorList && receipt.StartSample==s.StartSample && ...
        receipt.EndSampleExclusive==s.EndSampleExclusive && ...
        roster(hit).CommittedThroughSample>=s.EndSampleExclusive,id,'Incomplete target consumption receipt.');
    for c=reshape(receipt.Components,1,[])
        if string(c.ComponentID)==string(e.ObservationID)
            assert(c.StartSample>=lo&&c.EndSampleExclusive<=hi && ...
                c.NonzeroSampleCount>=0&&c.NonzeroSampleCount==fix(c.NonzeroSampleCount) && ...
                strlength(string(c.OriginalSampleSHA256))==64,id,'Invalid original target component.');
            originalCount=originalCount+c.NonzeroSampleCount;
        end
    end
    cursor=hi;
end
assert(cursor==e.TXEndSampleExclusive && originalCount==count,id, ...
    'Published presence must equal the complete original consumed target population.');
key=string(e.ObservationID)+"|"+string(e.ConfigurationEpoch)+"|"+string(e.ReceiverAssignmentDigest);
ok=true;
end

function x=number(r,name)
x=NaN;
if isfield(r,name)
    v=r.(name);
    if (isnumeric(v)||islogical(v))&&isreal(v)&&isscalar(v), x=double(v); end
end
end
