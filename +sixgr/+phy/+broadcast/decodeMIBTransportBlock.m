function mib = decodeMIBTransportBlock(trblk)
%DECODEMIBTRANSPORTBLOCK Decode the supported MIB fields from BCH TB bits.
%
% The input is the 24-bit BCH transport block recovered by nrBCHDecode. The
% MIB pdcch-ConfigSIB1 octet is carried in bits 14..21 of this block for
% the MATLAB/3GPP BCCH-BCH encoding used by nrWavegenSSBurstConfig.

bits = int8(trblk(:)) ~= 0;
if numel(bits) < 24
    error("sixgr:phy:broadcast:MIBTransportBlockTooShort", ...
        "Recovered BCH transport block must contain at least 24 bits.");
end
bits = bits(1:24);
semantic = sixgr.phy.ia.MIBSemanticValidator.decodeBits(bits(2:24));

pdcchConfigSIB1 = localReadUInt(bits, 14, 8);
split = sixgr.phy.broadcast.splitPDCCHConfigSIB1(pdcchConfigSIB1, ...
    "Source", "decoded_bch_transport_block_bits_14_21");

mib = split;
mib.TransportBlockNumBits = double(numel(bits));
mib.TransportBlockHex = sixgr.rrc.asn1.bitsToHex(int8(bits(:)));
mib.TransportBlockHash = sixgr.rrc.asn1.sha256Hex(uint8(bits(:)));
mib.PDCCHConfigSIB1BitStart = 14;
mib.PDCCHConfigSIB1BitEnd = 21;
mib.PDCCHConfigSIB1BitString = localBitsToString(bits(14:21));
mib.DMRSTypeAPosition = 2 + double(bits(13));
mib.DMRSTypeAPositionBitIndex = 13;
mib.CellBarredBit = double(bits(22));
mib.IntraFreqReselectionBit = double(bits(23));
mib.SpareBit = double(bits(24));
mib.SystemFrameNumberMSB6 = semantic.SystemFrameNumberMSB6;
mib.SystemFrameNumberMSB6Bits = semantic.SFNBits;
mib.SubCarrierSpacingCommon = semantic.SubCarrierSpacingCommon;
mib.SubCarrierSpacingCommonBit = semantic.SCSBit;
mib.SSBSubcarrierOffset = semantic.SSBSubcarrierOffset;
mib.SSBSubcarrierOffsetBits = semantic.KSSBBits;
mib.CellBarred = semantic.CellBarred;
mib.IntraFreqReselection = semantic.IntraFreqReselection;
mib.MIBInformationBits23 = semantic.MIBInformationBits23;
mib.MIBInformationBits = semantic.InformationBits;
mib.MIBSemanticSHA256 = semantic.SemanticSHA256;
mib.SemanticValidationStatus = semantic.SemanticValidationStatus;
mib.Semantic = semantic;
mib.Decoder = "sixgr.phy.broadcast.decodeMIBTransportBlock";
end

function value = localReadUInt(bits, pos, width)
value = 0;
for k = 1:width
    value = value * 2 + double(bits(pos + k - 1));
end
end

function txt = localBitsToString(bits)
chars = repmat('0', 1, numel(bits));
chars(logical(bits(:).')) = '1';
txt = string(chars);
end
