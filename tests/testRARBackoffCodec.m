function ok=testRARBackoffCodec()
% Independent octet positions, multiple RAPIDs, BI-only and padding.
cfg=raStrictAnchorConfig(); ra=sixgr.mac.ra.RAConfig(cfg);
grant=sixgr.mac.ra.buildRARULGrant(ra);
first=sixgr.mac.ra.encodeMACRAR('RAPID',mod(ra.PreambleIndex+1,64),'ULGrant',grant);
own=sixgr.mac.ra.encodeMACRAR('RAPID',ra.PreambleIndex,'TimingAdvanceCommand',19,'ULGrant',grant);
values=[5 10 20 30 40 60 80 120 160 240 320 480 960 1920];
for index=0:13
    packet=sixgr.mac.ra.encodeMACRAR('RAPID',ra.PreambleIndex,'ULGrant',grant,'BackoffIndicator',index);
    assert(packet.Bytes(1)==uint8(128+index) && packet.Bytes(2)==uint8(64+ra.PreambleIndex));
    out=sixgr.mac.ra.decodeMACRAR(packet.Bits,ra);
    assert(out.BackoffIndicatorPresent && out.BackoffParameter_ms==values(index+1));
    biOnly=sixgr.mac.ra.decodeMACRAR(uint8(index),ra);
    assert(isempty(biOnly.Responses) && isnan(biOnly.RAPID) && biOnly.BackoffParameter_ms==values(index+1));
end
% BI=2, E=1 on the first RAPID, then own RAPID and implicit TB padding.
other=first.Bytes; other(1)=bitor(other(1),uint8(128));
bytes=[uint8(130);other;own.Bytes;uint8([7;91;0])];
out=sixgr.mac.ra.decodeMACRAR(bytes,ra);
assert(out.BackoffParameter_ms==20 && numel(out.Responses)==2 && ...
    out.RAPID==ra.PreambleIndex && out.TimingAdvanceCommand==19 && out.PaddingOctets==3);
out=sixgr.mac.ra.decodeMACRAR(own.Bytes,ra);
assert(~out.BackoffIndicatorPresent && out.BackoffParameter_ms==0);
for index=[14 15]
    localReject(@()sixgr.mac.ra.decodeMACRAR(uint8(index),ra),'sixgr:mac:ra:ReservedBackoffIndicator');
end
localReject(@()sixgr.mac.ra.decodeMACRAR(uint8(128),ra),'sixgr:mac:ra:UnsupportedMACRARSubheader');
localReject(@()sixgr.mac.ra.decodeMACRAR(uint8(16),ra),'sixgr:mac:ra:InvalidMACRARField');
ok=true; disp('RAR_BACKOFF_CODEC_PASS: actual BI octets, all 14 values, BI-only, multiple RAPIDs, padding and reserved fields.');
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testRARBackoffCodec:MissingRejection','Expected %s.',id);
end
