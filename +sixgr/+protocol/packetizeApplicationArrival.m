function [packetBits,meta]=packetizeApplicationArrival(offeredBits,protocol,direction)
% Packetize original offered bytes; never lower traffic to manufacture delivery.
validateattributes(offeredBits,{'numeric'},{'scalar','finite','integer','nonnegative'});
assert(mod(offeredBits,8)==0,'sixgr:protocol:NonByteAlignedApplicationPayload', ...
    'Protocol traffic arrivals must contain whole original bytes.');
sessions=sixgr.util.structGet(protocol,'traffic.sessions',struct([]));
if iscell(sessions), sessions=[sessions{:}]; end
selected=arrayfun(@(s) any(upper(string(s.direction))==[upper(string(direction)),"BIDIR"]),sessions);
assert(sum(selected)==1,'sixgr:protocol:AmbiguousTrafficPacketization', ...
    'This offered-arrival owner requires exactly one matching protocol traffic session.');
session=sessions(selected);
bytes=double(sixgr.util.structGet(session,'packet_bytes',NaN));
% One configured SDAP header occupies one byte of the 9000-byte PDCP SDU.
assert(isscalar(bytes) && isfinite(bytes) && bytes==fix(bytes) && bytes>=1 && bytes<=8999, ...
    'sixgr:protocol:InvalidApplicationPacketSize', ...
    'Explicit traffic.sessions.packet_bytes must be1..8999 with a one-byte SDAP header.');
remaining=double(offeredBits)/8;
packetBits=repmat(8*bytes,1,floor(remaining/bytes));
if mod(remaining,bytes)>0, packetBits(end+1)=8*mod(remaining,bytes); end
assert(sum(packetBits)==offeredBits,'sixgr:protocol:PacketizationConservation', ...
    'Packetization must preserve every original offered bit.');
sessionID=double(sixgr.util.structGet(session,'pdu_session_id', ...
    sixgr.util.structGet(protocol,'sdap.pdu_session_id',NaN)));
meta=struct('FlowID',string(session.flow_id),'QFI',double(session.qfi),'PduSessionID',sessionID, ...
    'Source',"configured_packet_bytes_exact_original_arrival_conservation");
end
