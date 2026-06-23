function ok = testPDCCHDCIRIVAndPayloadSize()
%TESTPDCCHDCIRIVANDPAYLOADSIZE Guard NR DCI RIV sizing for 100 MHz/30 kHz.

setup6GRSimToolkit("Verbose", false);

[payloadBits, details] = sixgr.phy.pdcch.dciPayloadSizeBits(273, ["1_0","0_0"]);
assert(double(payloadBits) == 44, "NSizeGrid=273 DCI 0_0/1_0 common payload must be 44 bits.");
assert(double(details.FrequencyResourceAssignmentBits) == 16, ...
    "NSizeGrid=273 frequency-resource assignment must use 16 RIV bits.");
assert(double(details.DCI00UnpaddedPayloadBits) == 36, ...
    "DCI 0_0 unpadded payload must be 36 bits for NSizeGrid=273.");
assert(double(details.DCI00PaddedPayloadBits) == 44, ...
    "DCI 0_0 must be padded to the 44-bit DCI 1_0 common size.");

cfg = struct("NSizeGrid", 273);
dl = sixgr.phy.pdcch.buildDCI10DownlinkAssignment(cfg, ...
    "PRBStart", 37, "NumPRB", 101, "MCS", 19, "HARQProcess", 7);
ul = sixgr.phy.pdcch.buildDCI00UplinkGrant(cfg, ...
    "PRBStart", 4, "NumPRB", 12, "MCS", 8, "HARQProcess", 1);
assert(numel(dl.Bits) == 44, "Encoded DCI 1_0 must be 44 bits for NSizeGrid=273.");
assert(numel(ul.Bits) == 44, "Encoded DCI 0_0 must be padded to 44 bits for NSizeGrid=273.");

dlRx = sixgr.phy.pdcch.decodeDCIPayload(dl.Bits, "1_0", cfg);
ulRx = sixgr.phy.pdcch.decodeDCIPayload(ul.Bits, "0_0", cfg);
assert(double(dlRx.Fields.frequency_resource_assignment) == sixgr.phy.pdcch.rivEncode(37, 101, 273), ...
    "DCI 1_0 frequency assignment must carry the TS 38.214 RIV.");
assert(double(dlRx.Fields.prb_start) == 37 && double(dlRx.Fields.num_prb) == 101, ...
    "DCI 1_0 RIV must round-trip to the scheduled DL PRB allocation.");
assert(double(ulRx.Fields.prb_start) == 4 && double(ulRx.Fields.num_prb) == 12, ...
    "DCI 0_0 RIV must round-trip to the scheduled UL PRB allocation.");
assert(logical(dlRx.Fields.frequency_resource_assignment_valid) && ...
    logical(ulRx.Fields.frequency_resource_assignment_valid), ...
    "Decoded RIV fields must be marked valid after round-trip.");

[payload52, details52] = sixgr.phy.pdcch.dciPayloadSizeBits(52, ["1_0","0_0"]);
assert(double(payload52) == 39 && double(details52.FrequencyResourceAssignmentBits) == 11, ...
    "NSizeGrid=52 strict mini-anchor DCI payload must derive to 39 bits, not a fixed 64-bit payload.");

ok = true;
end
