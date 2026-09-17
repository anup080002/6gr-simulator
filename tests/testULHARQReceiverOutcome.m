function ok=testULHARQReceiverOutcome()
% Declared decoder outcomes, not RF, CRC-collision frequency or link success.
bits=int8([0;1;1;0]); other=1-bits;
for currentPass=[false true]
    current=struct('Ok',currentPass,'TransportBlock',bits);
    baseline=sixgr.link.resolveULHARQReceiverOutcome(current,[]);
    assert(baseline.CurrentDecodeOK==currentPass && ...
        baseline.CombinedDecodeOK==currentPass && ...
        isequal(baseline.DecodedTransportBlockBits,bits) && ~baseline.SelectedCombinedDecode);
    % Contradictory TX/scoring metadata must not alter the receiver decision.
    current.TransportBlockBits=other; current.ExpectedBits=other;
    current.ReferenceContentMatch=false; current.BitErrors=numel(bits);
    assert(isequaln(baseline,sixgr.link.resolveULHARQReceiverOutcome(current,[])));
end
current=struct('Ok',false,'TransportBlock',bits);
for combinedPass=[false true]
    combined=struct('CRCPass',combinedPass,'TransportBlock',other);
    out=sixgr.link.resolveULHARQReceiverOutcome(current,combined);
    expected=bits; if combinedPass, expected=other; end
    assert(~out.CurrentDecodeOK && out.CombinedDecodeOK==combinedPass && ...
        out.SelectedCombinedDecode==combinedPass && isequal(out.DecodedTransportBlockBits,expected));
    combined.ExpectedBits=bits; combined.ReferenceContentMatch=false;
    assert(isequaln(out,sixgr.link.resolveULHARQReceiverOutcome(current,combined)));
end
bad=current; bad.Ok=NaN;
localReject(@()sixgr.link.resolveULHARQReceiverOutcome(bad,[]),'sixgr:link:ULReceiverVerdictRequired');
bad=current; bad.TransportBlock=[NaN;1];
localReject(@()sixgr.link.resolveULHARQReceiverOutcome(bad,[]),'sixgr:link:ULDecodedBitsRequired');
bad=struct('CRCPass',true,'TransportBlock',bits(1:3));
localReject(@()sixgr.link.resolveULHARQReceiverOutcome(current,bad),'sixgr:link:ULDecodedTBSMismatch');
bad=struct('CRCPass',NaN,'TransportBlock',bits);
localReject(@()sixgr.link.resolveULHARQReceiverOutcome(current,bad),'sixgr:link:ULCombinedVerdictRequired');
current.Ok=true;
bad=struct('CRCPass',false,'TransportBlock',bits);
localReject(@()sixgr.link.resolveULHARQReceiverOutcome(current,bad),'sixgr:link:ULCombinedVerdictRequired');
ok=true;
fprintf('UL_HARQ_RECEIVER_OUTCOME_PASS declared_decoder_contract=1 RF=0\n');
end

function localReject(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s.',id,cause.identifier);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
