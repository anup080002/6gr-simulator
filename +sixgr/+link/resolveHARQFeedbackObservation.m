function [known,ack,source]=resolveHARQFeedbackObservation(feedback,legacyFields)
% Respect the receiver's explicit scalar-HARQ validity contract first.
% CSI/control CRC and codebook-level outcomes cannot rescue an invalid or
% inapplicable ACK. Legacy direct-link data-decode callers remain distinct.
arguments
    feedback (1,1) struct
    legacyFields (1,:) string
end
known=false; ack=false; source="";
if isfield(feedback,'AckObservedValid')
    valid=feedback.AckObservedValid;
    localBinary(valid,'AckObservedValid');
    source="AckObservedValid";
    if ~valid, return; end
    assert(isfield(feedback,'AckObserved'), ...
        'sixgr:link:InvalidHARQFeedbackObservation', ...
        'A valid HARQ observation requires its actual AckObserved value.');
    localBinary(feedback.AckObserved,'AckObserved');
    known=true; ack=logical(feedback.AckObserved); source="AckObserved";
    return;
end
% Existing standalone data-link callers do not carry an explicit UCI
% validity contract. This compatibility is not received-control evidence.
for field=legacyFields
    value=sixgr.util.structGet(feedback,field,[]);
    if (isnumeric(value)||islogical(value)) && isreal(value) && ...
            isscalar(value) && isfinite(value) && any(value==[0 1])
        known=true; ack=logical(value); source=field;
        return;
    end
end
end

function localBinary(value,name)
assert((isnumeric(value)||islogical(value)) && isreal(value) && ...
    isscalar(value) && isfinite(value) && any(value==[0 1]), ...
    'sixgr:link:InvalidHARQFeedbackObservation', ...
    '%s must be an explicit scalar binary receiver decision.',name);
end
