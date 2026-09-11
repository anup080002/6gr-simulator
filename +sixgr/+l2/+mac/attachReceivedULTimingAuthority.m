function grant=attachReceivedULTimingAuthority(grant,ue)
% Per-UE received initial TAG, before freezing PUSCH or DL HARQ-ACK timing.
% Retransmissions bind the current received authority, not the old attempt's
% TA. Missing shared-stream authority is not replaced by a configured zero.
required=sixgr.util.structGet(ue,'SharedULTimingRequired',false);
assert((islogical(required)||isnumeric(required)) && isscalar(required) && ...
    any(double(required)==[0 1]),'sixgr:l2:mac:InvalidReceivedULTiming', ...
    'SharedULTimingRequired must be an explicit boolean.');
context=sixgr.util.structGet(ue,'SharedULTimingContext',struct());
assert(isstruct(context) && isscalar(context), ...
    'sixgr:l2:mac:InvalidReceivedULTiming','A received TAG context must be scalar.');
if isempty(fieldnames(context))
    assert(~required,'sixgr:l2:mac:MissingReceivedULTiming', ...
        'Shared-stream scheduling requires this UE''s received timing authority.');
    return;
end
assert(isfield(ue,'RNTI') && isfield(grant,'RNTI') && ue.RNTI==grant.RNTI, ...
    'sixgr:l2:mac:ReceivedULTimingOwnerMismatch','A grant must use its own UE''s TAG.');
assert(all(isfield(context,{'DLReference','ReceivedRARTiming','Offset'})), ...
    'sixgr:l2:mac:InvalidReceivedULTiming','Retain the received DL clock, RAR and common offset.');
ta=context.ReceivedRARTiming; offset=context.Offset; ref=context.DLReference;
fs=ref.SampleRateHz;
expected=sixgr.phy.ra.resolveRARTimingAdvance(ta.Command,ta.FirstULSCSkHz,fs);
assert(isequaln(ta,expected),'sixgr:link:ConnectedULTimingAuthorityMismatch', ...
    'Received RAR conversion cannot be replaced by scheduler policy.');
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',offset.IEPresent, ...
    'TimingAdvanceOffset',offset.ReceivedIE);
expectedOffset=sixgr.phy.frame.resolveULTimingAdvanceOffset(common,offset.FrequencyRange);
assert(isequaln(offset,expectedOffset),'sixgr:link:ConnectedULOffsetAuthorityMismatch', ...
    'Use the decoded common-offset authority, not a duplex-mode guess.');
grant.SharedULTimingContext=context;
grant.TimingAdvanceTicks=int64(ta.NTA_Tc)+offset.NTAOffset_Tc;
grant.TimingAdvanceSource="received_initial_TAG_RAR_and_common_offset";
grant.TimingAdvanceOwnerRNTI=ue.RNTI;
end
