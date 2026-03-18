function [outBits, info] = descrambleBits(inBits, nid, rnti, varargin)
%DESCRAMBLEBITS Descramble binary bits (inverse of scrambleBits).
%
%   [OUT,INFO] = sixgr.phy.scramble.descrambleBits(IN, NID, RNTI, Name,Value,...)
%
%   This uses the same PRBS sequence as scrambling (XOR), so the operation is
%   identical at the bit level.

[outBits, info] = sixgr.phy.scramble.scrambleBits(inBits, nid, rnti, varargin{:});
info.Direction = 'descramble';

end
