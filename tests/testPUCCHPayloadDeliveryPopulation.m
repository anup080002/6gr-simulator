function ok=testPUCCHPayloadDeliveryPopulation()
% Erasures remain in delivery denominators, not bit-error denominators.
T=table([4;14;3;0;15],[1;1;1;1;0],[1;NaN;0;NaN;NaN], ...
    [0;1;0;0;1],[1;1;1;1;1], ...
    'VariableNames',{'ExpectedBitCount','PUCCHTransmissionPrepared', ...
    'UCIContentMatch','DTXFlag','DetectionUsable'});
T.DetectionAttempted=ones(height(T),1); T.Crash=zeros(height(T),1);
a=sixgr.truth.summarizePUCCHPayloadDelivery(T);
assert(a.Available && a.TransmittedBits==21 && a.DeliveredBits==4);
assert(a.PayloadCount==3 && a.FailedPayloadCount==2);
assert(a.BitWeightedDeliveryRatio==4/21 && a.PayloadErrorRate==2/3);
% CRC success cannot repair a wrong payload or substitute for absent truth.
T.CRCPass=ones(height(T),1);
b=sixgr.truth.summarizePUCCHPayloadDelivery(T);
assert(isequal(a,b));
T.Crash(2)=1;
b=sixgr.truth.summarizePUCCHPayloadDelivery(T); assert(~b.Available);
T.Crash(2)=0; T.DetectionAttempted(2)=0;
b=sixgr.truth.summarizePUCCHPayloadDelivery(T); assert(~b.Available);
T.DetectionAttempted(2)=1;
T.UCIContentMatch(1)=NaN;
b=sixgr.truth.summarizePUCCHPayloadDelivery(T); assert(~b.Available);
T.UCIContentMatch(1)=1; T.PUCCHTransmissionPrepared(5)=NaN;
b=sixgr.truth.summarizePUCCHPayloadDelivery(T); assert(~b.Available);
T.PUCCHTransmissionPrepared(:)=0;
b=sixgr.truth.summarizePUCCHPayloadDelivery(T);
assert(~b.Available && isnan(b.BitWeightedDeliveryRatio));
fprintf('PUCCH_PAYLOAD_DELIVERY_POPULATION_PASS sent=21 delivered=4 erased_payload_retained\n');
ok=true;
end
