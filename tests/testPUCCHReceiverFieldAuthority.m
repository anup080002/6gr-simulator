function ok=testPUCCHReceiverFieldAuthority()
% Declared decoder-output fixtures, not PHY or shared HARQ qualification.
fields=struct('HARQACK',int8([1;0]),'SR',int8(1), ...
    'CSIPart1',int8([0;1]),'CSIPart2',int8([1;0]));
rx=struct('DecodedSequence1',int8([1;0;1;0;1]), ...
    'DecodedSequence2',int8([1;0;0]),'DecodedFields',fields);
t=struct('Receiver',rx,'ReceiverFields',fields,'ReceiverExpectedBitCount',8, ...
    'ReceiverExpectedHARQBitCount',2,'ReceiverExpectedSRBitCount',1, ...
    'ReceiverExpectedCSIPart1BitCount',2,'ReceiverExpectedCSIPart2BitCount',2);
[a,valid]=sixgr.truth.extractPUCCHReceiverFields(t);
assert(valid && isequal(a.HARQACKBits,int8([1;0])) && ...
    isequal(a.CSIPart2Bits,int8([1;0])) && isequal(a.PaddingBits,int8(0)));
% Contradictory TX/scoring metadata cannot redefine received field ownership.
t.ExpectedBits=int8(1); t.ExpectedBitCount=1;
t.Transmitter=struct('Serialization',struct('Layout','deliberately unusable TX layout'));
t.DecodedBits=int8(0); % This scoring alias is not the canonical RX object.
[b,valid]=sixgr.truth.extractPUCCHReceiverFields(t);
assert(valid && isequaln(a,b));
bad=t; bad.ReceiverFields.HARQACK=int8([0;0]);
localReject(bad,'sixgr:truth:InconsistentPUCCHReceiverFields');
bad=t; bad.Receiver.DecodedSequence1(1)=0;
localReject(bad,'sixgr:truth:InconsistentPUCCHReceiverFields');
bad=t; bad.Receiver.DecodedSequence1=double(bad.Receiver.DecodedSequence1);
bad.Receiver.DecodedSequence1(1)=0.25;
localReject(bad,'sixgr:truth:InvalidReceivedHARQBit');
bad=rmfield(t,'ReceiverExpectedHARQBitCount');
localReject(bad,'sixgr:truth:MissingPUCCHReceiverFields');
empty=int8(zeros(0,1));
bad=t; bad.Receiver.DecodedSequence1=empty; bad.Receiver.DecodedSequence2=empty;
bad.ReceiverFields=struct('HARQACK',empty,'SR',empty,'CSIPart1',empty,'CSIPart2',empty);
bad.Receiver.DecodedFields=bad.ReceiverFields;
[b,valid]=sixgr.truth.extractPUCCHReceiverFields(bad);
assert(~valid && isempty(b.InformationBits));
% Short CSI sequence retains received information but is not a complete layout.
bad=t; bad.Receiver.DecodedSequence2=int8(1);
bad.ReceiverFields.CSIPart2=int8(1); bad.Receiver.DecodedFields=bad.ReceiverFields;
[b,valid]=sixgr.truth.extractPUCCHReceiverFields(bad);
assert(~valid && isequal(b.CSIPart2Bits,int8(1)));
ok=true;
end

function localReject(t,id)
try
    sixgr.truth.extractPUCCHReceiverFields(t);
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s',id,ME.identifier);
    return;
end
error('test:MissingReceiverFieldRejection','Expected %s.',id);
end
