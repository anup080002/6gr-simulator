function [codedCB, info] = ldpcEncode(cbBits, bgn)
%ldpcEncode LDPC encode code block segments (5G Toolbox wrapper).
%
%   [codedCB, info] = sixgr.phy.phycode.ldpcEncode(cbBits, bgn)
%
%   This is a thin, stable wrapper around nrLDPCEncode (5G Toolbox). It is
%   intended to be reused by both PDSCH and PUSCH processing chains.
%
%   Inputs:
%     cbBits : K-by-C numeric/logical matrix of bits (0/1). Filler bits are
%              allowed and must be represented by -1 (as used by TS 38.212).
%     bgn    : Base graph number (1 or 2).
%
%   Outputs:
%     codedCB : N-by-C encoded code blocks (filler positions may be -1).
%     info    : Struct with metadata (bgn, K, N, numCB).
%
%   See also nrLDPCEncode, sixgr.phy.tb.segmentLDPC

    % Basic validation (keep MATLAB Coder friendly)
    if nargin < 2
        error('sixgr:phy:ldpcEncode:InvalidInput','cbBits and bgn are required.');
    end
    validateattributes(bgn, {'numeric'}, {'scalar','finite','integer'}, mfilename, 'bgn', 2);
    if ~(bgn==1 || bgn==2)
        error('sixgr:phy:ldpcEncode:InvalidBGN','bgn must be 1 or 2.');
    end

    if exist('nrLDPCEncode','file') ~= 2
        error('sixgr:Missing5GToolbox', ...
            'nrLDPCEncode not found. Install/enable 5G Toolbox.');
    end

    % Normalize shape: allow vector input for single CB
    if isvector(cbBits)
        cbBits = cbBits(:);
    end

    % Normalize datatype (nrLDPCEncode accepts double or int8)
    if islogical(cbBits)
        cbBits = int8(cbBits);
    elseif ~isa(cbBits,'double') && ~isa(cbBits,'int8')
        cbBits = double(cbBits);
    end

    codedCB = nrLDPCEncode(cbBits, bgn);

    info = struct();
    info.bgn = bgn;
    info.K = size(cbBits, 1);
    info.numCB = size(cbBits, 2);
    info.N = size(codedCB, 1);
end
