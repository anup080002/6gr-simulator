function actual=normalizeReceivedPUCCHCSI(rx,context,report)
% Receiver bits and installed schema only; no UE payload or producer identity.
for name=["ReceiverOnlyAssignment","ReceiverUsable","DTX","CRCPassed","CRCApplicable"]
    value=rx.(name);
    assert((islogical(value)||isnumeric(value)) && isreal(value) && isscalar(value) && ...
        isfinite(value) && any(value==[0 1]),'sixgr:truth:InvalidPUCCHCSIReceiverFlag', ...
        'Receiver evidence flags must be explicitly binary.');
end
assert(isa(context,'sixgr.phy.pucch.UCIReportContext') && ...
    isa(report,'sixgr.phy.mimo.CSIReportConfiguration') && report.UCIChannel=="PUCCH" && ...
    isequal(string(rx.ReportContextDigest),context.Digest) && rx.ReceiverOnlyAssignment, ...
    'sixgr:truth:MissingIndependentPUCCHCSIContext','Use the bound independent PUCCH receiver.');
assert(context.CSIPart1Bits==report.part1BitCount() && ...
    context.CSIPart2Bits==report.part2BitCount(), ...
    'sixgr:truth:CSIReceiveConfigurationMismatch','Installed CSI lengths must match the receive schema.');
parts={rx.DecodedFields.CSIPart1,rx.DecodedFields.CSIPart2};
for k=1:2
    b=parts{k};
    assert((isnumeric(b)||islogical(b)) && isreal(b) && ...
        (isvector(b)||isempty(b)) && all(isfinite(b(:))) && all(b(:)==0|b(:)==1), ...
        'sixgr:truth:InvalidReceivedCSIBit','Validate receiver bits before conversion.');
    parts{k}=int8(b(:));
end
crc=NaN; if rx.CRCApplicable, crc=double(rx.CRCPassed); end
actual=struct('ReceiverContextDigest',context.Digest,'CSIReportConfigID',report.ReportConfigID, ...
    'CSIConfigurationEpoch',report.Epoch,'DecodeOk',false,'CRCPass',crc, ...
    'DecodedPart1',parts{1},'DecodedPart2',parts{2},'Fields',struct(), ...
    'Source',"actual_independent_PUCCH_receiver_no_usable_CSI");
if ~(rx.ReceiverUsable && ~rx.DTX && rx.CRCPassed && ...
        numel(parts{1})==context.CSIPart1Bits && numel(parts{2})==context.CSIPart2Bits)
    return;
end
try
    actual.Fields=report.decode(parts{1},parts{2});
catch cause
    % Reserved received values are failed wire decoding, not a configuration
    % rescue. All other errors still propagate unchanged.
    if ~any(string(cause.identifier)==["sixgr:mimo:InvalidRI", ...
            "sixgr:mimo:InvalidCRI","sixgr:mimo:InvalidCSIPadding"])
        rethrow(cause);
    end
    actual.Source="received_PUCCH_CSI_reserved_value_"+string(cause.identifier);
    return;
end
actual.DecodeOk=true;
actual.Source="actual_received_PUCCH_CSI_fields_and_installed_schema";
end
