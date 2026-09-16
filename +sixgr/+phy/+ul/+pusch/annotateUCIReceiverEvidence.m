function rx=annotateUCIReceiverEvidence(rx,uci)
% One UCI output contract for complete and partial PUSCH reception.
% Copies actual decoder metadata; never supplies a TB CRC or guesses a bit.
assert(isstruct(rx) && isscalar(rx) && isstruct(uci) && isscalar(uci), ...
    'sixgr:pusch:InvalidUCIAnnotation','Use scalar receiver and UCI results.');
required={'Applied','Source','HARQACKBitCount','CSI1BitCount','CSI2BitCount', ...
    'ConfiguredGrantUCIBitCount','DecodedHARQACKBits','DecodedCSIPart1Bits', ...
    'DecodedCSIPart2Bits','DecodedConfiguredGrantUCIBits','UCIReceiverEvidence','Status','Reason'};
assert(all(isfield(uci,required)),'sixgr:pusch:IncompleteUCIAnnotation', ...
    'Preserve the complete actual UCI adapter result, including decode status.');
rx.UCIOnPUSCHApplied=logical(uci.Applied);
rx.UCIOnPUSCHSource=char(string(uci.Source));
rx.UCIOnPUSCHEvidenceSource="";
if rx.UCIOnPUSCHApplied
    rx.UCIOnPUSCHEvidenceSource="same_waveform_pusch_rx_uci_demultiplexer";
end
for name=["HARQACKBitCount","CSI1BitCount","CSI2BitCount","ConfiguredGrantUCIBitCount"]
    rx.(name)=double(uci.(name));
end
for name=["DecodedHARQACKBits","DecodedCSIPart1Bits","DecodedCSIPart2Bits","DecodedConfiguredGrantUCIBits"]
    bits=uci.(name);
    assert((isnumeric(bits)||islogical(bits)) && isreal(bits) && ...
        (isvector(bits)||isempty(bits)) && all(isfinite(bits(:))) && all(bits(:)==0|bits(:)==1), ...
        'sixgr:pusch:InvalidUCIAnnotationBits','Validate decoded bits before integer conversion.');
    rx.(name)=int8(bits(:));
end
rx.UCIReceiverEvidence=uci.UCIReceiverEvidence;
rx.HARQACKDecodeStatus=char(string(uci.Status));
rx.HARQACKDecodeReason=char(string(uci.Reason));
scoring=["ExpectedHARQACKBits","ExpectedCSIPart1Bits","ExpectedCSIPart2Bits", ...
    "ExpectedConfiguredGrantUCIBits","HARQACKContentMatch","CSI1ContentMatch", ...
    "CSI2ContentMatch","ConfiguredGrantUCIContentMatch"];
if isfield(uci,'ContentMatch')
    for name=scoring(1:4)
        rx.(name)=int8(uci.(name)(:));
    end
    rx.HARQACKContentMatch=logical(uci.ContentMatch);
    for name=scoring(6:8)
        rx.(name)=logical(uci.(name));
    end
else
    assert(isfield(uci,'ReceiverContextDigest') && ...
        ~any(isfield(rx,scoring)) && ~any(isfield(uci,scoring)), ...
        'sixgr:pusch:ConflictingUCIAnnotationAuthority', ...
        'Independent receive metadata cannot inherit TX-reference scoring fields.');
    rx.UCIReferenceScoringAvailable=false;
    rx.UCIReceiveContextDigest=uci.ReceiverContextDigest;
end
for name=["PartialReception","CSIPart1Usable","CSIRejectionIdentifier","ULSCHMappingResolved", ...
        "CSIPresenceResolved","CSIReportDetected","CSIPresenceEvidence"]
    if isfield(uci,name), rx.(name)=uci.(name); end
end
end
