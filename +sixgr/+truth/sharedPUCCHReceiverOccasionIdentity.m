function [physicalID,queueKey,source]=sharedPUCCHReceiverOccasionIdentity(item)
% Resolve the receiver-row namespace from its frozen production owner.
% A scheduling queue key is not the emitted-feedback physical occasion ID.
id='sixgr:truth:PUCCHReceiverOccasionIdentity';
c=item.Context;
assert(isfield(c,'ObservationID') && isfield(c,'Key') && ...
    localText(c.ObservationID)==localText(item.ID),id, ...
    'Retain the registered observation identity through completion.');
queueKey=localText(c.Key);
hasReception=isfield(c,'GNBReception');
if hasReception
    h=c.GNBReception;
    assert(isfield(h,'Mapping') && h.UEIndex==item.UE && ...
        h.Assignment.Data.ObservationID==string(item.ID) && ...
        h.Assignment.Data.RNTI==h.RNTI && ...
        h.Assignment.Data.AbsoluteSlot0+1==c.Slot,id, ...
        'Retain the independently installed receiver observation and owner.');
    configured=isempty(h.Mapping);
else
    configured=false;
end
if configured
    % These explicit completion producers publish the registered queue key.
    % Do not use this branch to rescue a missing emitted-feedback identity.
    csi=isfield(h,'CSIReportCalendar') && istable(h.CSIReportCalendar) && ...
        ~isempty(h.CSIReportCalendar);
    sr=isfield(h,'SRReportCalendar') && istable(h.SRReportCalendar) && ...
        ~isempty(h.SRReportCalendar);
    assert(csi || sr,id,'An empty HARQ mapping requires its installed CSI/SR calendar.');
    physicalID=queueKey;
    source="configured_CSI_SR_receiver_queue_owned_occasion";
elseif string(item.Kind)=="PUCCHReceiveOnly"
    assert(hasReception && ~isempty(h.Mapping) && ~isfield(c,'Prepared'),id, ...
        'Scheduled receive-only identity requires its independent HARQ mapping.');
    physicalID=queueKey;
    source="scheduled_HARQ_receive_only_queue_owned_occasion";
else
    assert(string(item.Kind)=="PUCCH" && isfield(c,'PhysicalOccasionId') && ...
        isfield(c,'FeedbackRows') && istable(c.FeedbackRows) && ~isempty(c.FeedbackRows),id, ...
        'Emitted feedback requires its physical occasion ID frozen at preparation.');
    physicalID=localText(c.PhysicalOccasionId);
    rows=c.FeedbackRows;
    required=["ScheduledAbsoluteSlot","UEIndex","RNTI","ServingCell", ...
        "ComponentCarrier","ActiveULBWP"];
    assert(all(ismember(required,string(rows.Properties.VariableNames))),id, ...
        'Retain complete frozen feedback occasion coordinates.');
    values=double(rows{:,cellstr(required)});
    assert(all(isfinite(values),'all') && all(values==fix(values),'all') && ...
        all(values==values(1,:),'all') && values(1,1)==c.Slot && values(1,2)==item.UE && ...
        all(sixgr.truth.CoupledTruthRuntime.sharedPUCCHOccasionKey(rows)==queueKey),id, ...
        'The queue key, UE and physical occasion must describe the same frozen feedback rows.');
    expected=string(sprintf('pucchoccasion:due=%d:ue=%d:rnti=%d:cell=%d:cc=%d:ulbwp=%d',values(1,:)));
    assert(physicalID==expected,id,'Do not substitute a queue key or another physical occasion.');
    if hasReception
        assert(h.RNTI==values(1,3) && h.ServingCell==values(1,4),id, ...
            'The emitted feedback and independent receiver must name the same UE/cell.');
    end
    source="prepared_feedback_physical_occasion_with_distinct_queue_key";
end
end

function value=localText(value)
value=string(value);
assert(isscalar(value) && ~ismissing(value) && strlength(strtrim(value))>0, ...
    'sixgr:truth:PUCCHReceiverOccasionIdentity','Require an explicit nonempty identity.');
end
