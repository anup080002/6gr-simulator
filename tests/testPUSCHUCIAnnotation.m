function ok=testPUSCHUCIAnnotation()
% Declared metadata fixtures, not a PHY or detector qualification.
uci=struct('Applied',true,'Source',"declared_receiver_metadata", ...
    'HARQACKBitCount',2,'CSI1BitCount',3,'CSI2BitCount',NaN,'ConfiguredGrantUCIBitCount',0, ...
    'DecodedHARQACKBits',int8([1;0]),'DecodedCSIPart1Bits',int8([1;1;1]), ...
    'DecodedCSIPart2Bits',int8([]),'DecodedConfiguredGrantUCIBits',int8([]), ...
    'UCIReceiverEvidence',struct('FixtureOnly',true),'Status',"decoded_usable",'Reason',"", ...
    'ReceiverContextDigest',"declared_context",'PartialReception',true, ...
    'CSIPart1Usable',false,'CSIRejectionIdentifier',"sixgr:mimo:InvalidCRI", ...
    'ULSCHMappingResolved',false);
before=uci;
rx=sixgr.phy.ul.pusch.annotateUCIReceiverEvidence(struct('Ok',false),uci);
assert(isequaln(uci,before) && ~rx.Ok && rx.HARQACKBitCount==2);
assert(strcmp(rx.HARQACKDecodeStatus,'decoded_usable') && isequal(rx.DecodedHARQACKBits,int8([1;0])));
assert(rx.PartialReception && ~rx.CSIPart1Usable && isnan(rx.CSI2BitCount));
assert(~rx.UCIReferenceScoringAvailable && rx.UCIReceiveContextDigest=="declared_context");
assert(~any(isfield(rx,{'CRCError','CRCPass','TBCRCPass','HARQACKContentMatch','ExpectedHARQACKBits'})));
assert(isequaln(rx.UCIReceiverEvidence,uci.UCIReceiverEvidence));
% Metadata marked unusable stays unusable; this adapter does not decode.
bad=uci; bad.Status="decoded_unusable"; bad.Reason="actual_decoder_rejection";
out=sixgr.phy.ul.pusch.annotateUCIReceiverEvidence(struct(),bad);
assert(strcmp(out.HARQACKDecodeStatus,'decoded_unusable') && strcmp(out.HARQACKDecodeReason,'actual_decoder_rejection'));
bad=uci; bad.DecodedHARQACKBits=[1;.5];
localReject(@()sixgr.phy.ul.pusch.annotateUCIReceiverEvidence(struct(),bad), ...
    'sixgr:pusch:InvalidUCIAnnotationBits');
localReject(@()sixgr.phy.ul.pusch.annotateUCIReceiverEvidence(struct('HARQACKContentMatch',true),uci), ...
    'sixgr:pusch:ConflictingUCIAnnotationAuthority');
localReject(@()sixgr.phy.ul.pusch.annotateUCIReceiverEvidence(struct(),rmfield(uci,'Status')), ...
    'sixgr:pusch:IncompleteUCIAnnotation');
% Retain the explicit legacy scoring adapter's fields without inventing them
% for the independent receiver. Scoring does not replace decode status.
legacy=uci; legacy.CSI2BitCount=0; legacy.PartialReception=false;
legacy.ExpectedHARQACKBits=int8([0;1]); legacy.ExpectedCSIPart1Bits=int8([0;0;0]);
legacy.ExpectedCSIPart2Bits=int8([]); legacy.ExpectedConfiguredGrantUCIBits=int8([]);
legacy.ContentMatch=false; legacy.CSI1ContentMatch=false;
legacy.CSI2ContentMatch=true; legacy.ConfiguredGrantUCIContentMatch=true;
out=sixgr.phy.ul.pusch.annotateUCIReceiverEvidence(struct(),legacy);
assert(~out.HARQACKContentMatch && ~out.CSI1ContentMatch && out.CSI2ContentMatch);
assert(isequal(out.DecodedHARQACKBits,legacy.DecodedHARQACKBits) && ...
    isequal(out.ExpectedHARQACKBits,legacy.ExpectedHARQACKBits));
ok=true; fprintf('PUSCH_UCI_ANNOTATION_PASS: declared metadata, no PHY qualification.\n');
end

function localReject(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, observed %s',id,cause.identifier);
    return;
end
error('sixgr:test:ExpectedRejection','Expected %s',id);
end
