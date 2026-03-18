function blkcrc = attachCRC(blk, poly, mask)
%ATTACHCRC Attach CRC bits to a transport/code block using 5G Toolbox.
%
%   blkcrc = sixgr.phy.tb.attachCRC(blk, poly) appends CRC bits defined by
%   the CRC polynomial selector poly to the input bit vector blk.
%
%   blkcrc = sixgr.phy.tb.attachCRC(blk, poly, mask) additionally applies
%   CRC masking as supported by nrCRCEncode (for example, masking with RNTI
%   for some control channels).
%
%   Inputs:
%     blk  - Column vector of bits (0/1). Data types: double, int8, logical.
%     poly - CRC polynomial selector. Examples: '24A','24B','24C','16','11','6'.
%     mask - Optional CRC mask (scalar or vector). If omitted, no masking.
%
%   Output:
%     blkcrc - Column vector blk with CRC appended.

    if nargin < 2 || isempty(poly)
        poly = '24A';
    end
    if isstring(poly)
        poly = char(poly);
    end

    blk = blk(:);

    if nargin < 3 || isempty(mask)
        blkcrc = nrCRCEncode(blk, poly);
    else
        blkcrc = nrCRCEncode(blk, poly, mask);
    end
end
