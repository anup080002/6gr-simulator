function [outBits, info] = scrambleBits(inBits, nid, rnti, varargin)
%SCRAMBLEBITS Scramble binary bits using 5G Toolbox PRBS for a given channel.
%
%   [OUT,INFO] = sixgr.phy.scramble.scrambleBits(IN, NID, RNTI, Name,Value,...)
%
%   Inputs:
%     IN   - Column or row vector of bits (0/1) as int8/logical/double.
%     NID  - Scrambling identity (typically NIDcell).
%     RNTI - Radio Network Temporary Identifier.
%
%   Name-Value pairs:
%     "Channel"  - "PDSCH" (default) or "PUSCH"
%     "Codeword" - 0 or 1 for PDSCH (default 0). Ignored for PUSCH.
%
%   Outputs:
%     OUT  - Scrambled bits, same size and class as IN.
%     INFO - Struct with fields: Channel, NID, RNTI, Codeword, N, Cinit (if available).
%
%   Notes:
%   - For PDSCH we use nrPDSCHPRBS(nid,rnti,q,n) per 5G Toolbox reference.
%   - For PUSCH we call nrPUSCHScramble if available (otherwise error).
%
%   This utility is intentionally simple and "Coder-friendly":
%   - Avoids Unicode characters and avoids inputParser.
%   - Uses deterministic parsing of name-value pairs.

% Defaults
channel = "PDSCH";
codeword = 0;

% Basic validation
if nargin < 3
    error('scrambleBits requires inBits, nid, rnti.');
end

% Parse name-value pairs
nv = varargin;
if ~isempty(nv)
    if mod(numel(nv),2) ~= 0
        error('Name-value arguments must be provided in pairs.');
    end
    for ii = 1:2:numel(nv)
        name = lower(string(nv{ii}));
        val  = nv{ii+1};
        switch name
            case "channel"
                channel = upper(string(val));
            case {"codeword","q"}
                codeword = double(val);
            otherwise
                error('Unknown Name-Value option: %s', char(name));
        end
    end
end

% Preserve shape + class
origSize = size(inBits);
inCol = inBits(:);
n = numel(inCol);

% Convert to logical bits for XOR
inLogic = (inCol ~= 0);

% Dispatch per channel
cinit = NaN;

switch channel
    case {"PDSCH","DL-SCH"}
        q = codeword;
        if ~(isscalar(q) && (q==0 || q==1))
            error('For PDSCH, Codeword (q) must be 0 or 1.');
        end

        % 5G Toolbox PRBS for PDSCH scrambling
        % Syntax: [SEQ,CINIT] = nrPDSCHPRBS(NID,RNTI,Q,N)
        [seq, cinit] = nrPDSCHPRBS(double(nid), double(rnti), double(q), double(n));
        seq = seq(:); % ensure column logical

        outLogic = xor(inLogic, seq);

    case {"PUSCH","UL-SCH"}
        if exist('nrPUSCHScramble','file') == 2
            outTmp = nrPUSCHScramble(cast(inLogic,'like',inCol), double(nid), double(rnti));
            outTmp = outTmp(:) ~= 0;
            outLogic = outTmp;
        else
            error('nrPUSCHScramble is not available. Install/enable 5G Toolbox.');
        end

    otherwise
        error('Unsupported Channel: %s', char(channel));
end

% Cast back to original class and shape
outBits = cast(outLogic, 'like', inCol);
outBits = reshape(outBits, origSize);

% Info
info = struct();
info.Channel  = char(channel);
info.NID      = double(nid);
info.RNTI     = double(rnti);
info.Codeword = double(codeword);
info.N        = double(n);
if ~isnan(cinit)
    info.Cinit = cinit;
end

end
