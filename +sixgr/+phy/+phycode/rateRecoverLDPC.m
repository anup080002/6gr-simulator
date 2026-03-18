function [recLLR, info] = rateRecoverLDPC(inLLR, trblkLen, R, rv, modScheme, nLayers, numCB, Nref)
%rateRecoverLDPC LDPC rate recovery (5G Toolbox wrapper).
%
%   [recLLR, info] = sixgr.phy.phycode.rateRecoverLDPC(inLLR, trblkLen, R, rv, modScheme, nLayers)
%   [recLLR, info] = sixgr.phy.phycode.rateRecoverLDPC(..., numCB)
%   [recLLR, info] = sixgr.phy.phycode.rateRecoverLDPC(..., numCB, Nref)
%
%   Wraps nrRateRecoverLDPC (5G Toolbox).
%
%   Inputs:
%     inLLR     : E-by-1 soft bits (LLR) corresponding to the received codeword.
%     trblkLen  : Transport block length (A) in bits (before CRC).
%     R         : Target code rate (0 < R <= 1).
%     rv        : Redundancy version (0..3).
%     modScheme : Modulation string, e.g. "QPSK","16QAM","64QAM","256QAM",
%                 "1024QAM", or "pi/2-BPSK".
%     nLayers   : Number of layers.
%     numCB     : (Optional) Number of code blocks (C).
%     Nref      : (Optional) Total soft buffer size Nref (bits).
%
%   Outputs:
%     recLLR : N-by-C recovered soft bits suitable for nrLDPCDecode.
%     info   : Metadata (A, R, rv, modScheme, nLayers, numCBUsed, NrefUsed).
%
%   Notes:
%     - Filler bit positions are set to Inf by nrRateRecoverLDPC. This is
%       expected by nrLDPCDecode.
%
%   See also nrRateRecoverLDPC, sixgr.phy.phycode.ldpcDecode

    if nargin < 6
        error('sixgr:phy:rateRecoverLDPC:InvalidInput', ...
            'inLLR,trblkLen,R,rv,modScheme,nLayers are required.');
    end
    if nargin < 7
        numCB = [];
    end
    if nargin < 8
        Nref = [];
    end

    if exist('nrRateRecoverLDPC','file') ~= 2
        error('sixgr:Missing5GToolbox', ...
            'nrRateRecoverLDPC not found. Install/enable 5G Toolbox.');
    end

    % Normalize shape: allow vector only
    if ~isvector(inLLR)
        error('sixgr:phy:rateRecoverLDPC:InvalidInput', 'inLLR must be a vector of soft bits.');
    end
    inLLR = inLLR(:);

    validateattributes(trblkLen, {'numeric'}, {'scalar','finite','integer','positive'}, mfilename, 'trblkLen', 2);
    validateattributes(R, {'numeric'}, {'scalar','finite','>',0,'<=',1}, mfilename, 'R', 3);
    validateattributes(rv, {'numeric'}, {'scalar','finite','integer','>=',0,'<=',3}, mfilename, 'rv', 4);
    validateattributes(nLayers, {'numeric'}, {'scalar','finite','integer','positive'}, mfilename, 'nLayers', 6);

    if isstring(modScheme), modScheme = char(modScheme); end

    % Normalize LLR type
    if ~isa(inLLR,'double') && ~isa(inLLR,'single')
        inLLR = double(inLLR);
    end

    if isempty(numCB) && isempty(Nref)
        recLLR = nrRateRecoverLDPC(inLLR, trblkLen, R, rv, modScheme, nLayers);
        numCBUsed = [];
        NrefUsed = [];
    elseif ~isempty(numCB) && isempty(Nref)
        validateattributes(numCB, {'numeric'}, {'scalar','finite','integer','positive'}, mfilename, 'numCB', 7);
        recLLR = nrRateRecoverLDPC(inLLR, trblkLen, R, rv, modScheme, nLayers, numCB);
        numCBUsed = numCB;
        NrefUsed = [];
    else
        if isempty(numCB)
            error('sixgr:phy:rateRecoverLDPC:InvalidInput', ...
                'If Nref is provided, numCB must also be provided.');
        end
        validateattributes(numCB, {'numeric'}, {'scalar','finite','integer','positive'}, mfilename, 'numCB', 7);
        validateattributes(Nref, {'numeric'}, {'scalar','finite','integer','positive'}, mfilename, 'Nref', 8);
        recLLR = nrRateRecoverLDPC(inLLR, trblkLen, R, rv, modScheme, nLayers, numCB, Nref);
        numCBUsed = numCB;
        NrefUsed = Nref;
    end

    info = struct();
    info.A = trblkLen;
    info.R = R;
    info.rv = rv;
    info.modScheme = modScheme;
    info.nLayers = nLayers;
    info.numCBUsed = numCBUsed;
    info.NrefUsed = NrefUsed;
end
