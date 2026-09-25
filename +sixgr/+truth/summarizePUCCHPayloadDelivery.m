function out=summarizePUCCHPayloadDelivery(T)
% Payload-delivery population is transmitted payloads, never compared bits.
% A missing decoded payload is a delivery failure, not a measured bit error.
out=struct('Available',false,'TransmittedBits',NaN,'DeliveredBits',NaN, ...
    'PayloadCount',NaN,'FailedPayloadCount',NaN,'BitWeightedDeliveryRatio',NaN, ...
    'PayloadErrorRate',NaN,'Status',"unavailable_transmit_and_receive_evidence");
required=["ExpectedBitCount","PUCCHTransmissionPrepared","UCIContentMatch", ...
    "DTXFlag","DetectionUsable","DetectionAttempted","Crash"];
if ~istable(T) || isempty(T) || ~all(ismember(required,string(T.Properties.VariableNames)))
    return;
end
prepared=double(T.PUCCHTransmissionPrepared);
bits=double(T.ExpectedBitCount);
match=double(T.UCIContentMatch);
dtx=double(T.DTXFlag); usable=double(T.DetectionUsable);
if any(~ismember(prepared,[0 1]))
    out.Status="unavailable_incomplete_transmission_population";
    return;
end
sent=prepared==1;
if any(sent & (~isfinite(bits) | bits<0 | bits~=fix(bits)))
    out.Status="unavailable_transmitted_payload_width";
    return;
end
% Negative SR and receiver-only occasions have no transmitted payload.
eligible=sent & bits>0;
if ~any(eligible)
    out.Status="no_transmitted_payloads";
    return;
end
knownMatch=ismember(match,[0 1]);
knownDetection=ismember(dtx,[0 1]) & ismember(usable,[0 1]) & ...
    double(T.DetectionAttempted)==1 & double(T.Crash)==0;
% Erasure or an unusable detection is a known delivery failure even if the
% absent payload has no bit-comparison outcome.
knownOutcome=knownDetection & ((dtx==1 | usable==0) | knownMatch);
if any(eligible & ~knownOutcome)
    out.Status="unavailable_incomplete_payload_outcomes";
    return;
end
delivered=eligible & dtx==0 & usable==1 & match==1;
out.TransmittedBits=sum(bits(eligible));
out.DeliveredBits=sum(bits(delivered));
out.PayloadCount=nnz(eligible);
out.FailedPayloadCount=nnz(eligible & ~delivered);
out.BitWeightedDeliveryRatio=out.DeliveredBits/out.TransmittedBits;
out.PayloadErrorRate=out.FailedPayloadCount/out.PayloadCount;
out.Available=true;
out.Status="complete_transmitted_payload_population_including_erasures";
end
