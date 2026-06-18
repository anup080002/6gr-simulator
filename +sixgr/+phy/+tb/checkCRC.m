function [blk, ok, err] = checkCRC(blkcrc, poly, mask)
%CHECKCRC CRC decode and check using 5G Toolbox.
%
%   [blk, ok, err] = sixgr.phy.tb.checkCRC(blkcrc, poly) removes CRC bits
%   defined by poly from blkcrc and returns ok = true when CRC passes.
%
%   [blk, ok, err] = sixgr.phy.tb.checkCRC(blkcrc, poly, mask) additionally
%   applies CRC unmasking as supported by nrCRCDecode.
%
%   Inputs:
%     blkcrc - Column vector of bits (0/1) containing appended CRC.
%     poly   - CRC polynomial selector. Examples: '24A','24B','24C','16','11','6'.
%     mask   - Optional CRC mask (scalar or vector). If omitted, no masking.
%
%   Outputs:
%     blk - Recovered data bits (CRC removed).
%     ok  - Logical scalar, true when CRC passes.
%     err - CRC error value returned by nrCRCDecode.

    if nargin < 2 || isempty(poly)
        poly = '24A';
    end
    if isstring(poly)
        poly = char(poly);
    end

    blkcrc = blkcrc(:);

    if nargin < 3 || isempty(mask)
        [blk, err] = nrCRCDecode(blkcrc, poly);
    else
        [blk, err] = nrCRCDecode(blkcrc, poly, mask);
    end

    err = any(double(err(:)) ~= 0);
    ok = ~logical(err);
end
