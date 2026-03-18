function [rmBits, info] = rateMatchLDPC(codedCB, outLen, rv, modScheme, nLayers, Nref)
%rateMatchLDPC LDPC rate matching (5G Toolbox wrapper).
%
%   [rmBits, info] = sixgr.phy.phycode.rateMatchLDPC(codedCB, outLen, rv, modScheme, nLayers)
%   [rmBits, info] = sixgr.phy.phycode.rateMatchLDPC(..., Nref)
%
%   Wraps nrRateMatchLDPC (5G Toolbox). Used by both PDSCH and PUSCH chains.
%
%   Inputs:
%     codedCB   : N-by-C encoded code blocks (from nrLDPCEncode).
%     outLen    : Output length (E) after rate matching (scalar, bits).
%     rv        : Redundancy version (0..3).
%     modScheme : Modulation string, e.g. "QPSK","16QAM","64QAM","256QAM",
%                 "1024QAM", or "pi/2-BPSK" (uplink).
%     nLayers   : Number of layers.
%     Nref      : (Optional) Total soft buffer size Nref (bits).
%
%   Outputs:
%     rmBits : outLen-by-1 rate-matched bit stream.
%     info   : Metadata (E, rv, modScheme, nLayers, NrefUsed).
%
%   See also nrRateMatchLDPC

    if nargin < 5
        error('sixgr:phy:rateMatchLDPC:InvalidInput', ...
            'codedCB,outLen,rv,modScheme,nLayers are required.');
    end
    if nargin < 6
        Nref = [];
    end

    if exist('nrRateMatchLDPC','file') ~= 2
        error('sixgr:Missing5GToolbox', ...
            'nrRateMatchLDPC not found. Install/enable 5G Toolbox.');
    end

    validateattributes(outLen, {'numeric'}, {'scalar','finite','integer','positive'}, mfilename, 'outLen', 2);
    validateattributes(rv, {'numeric'}, {'scalar','finite','integer','>=',0,'<=',3}, mfilename, 'rv', 3);
    validateattributes(nLayers, {'numeric'}, {'scalar','finite','integer','positive'}, mfilename, 'nLayers', 5);

    if isstring(modScheme), modScheme = char(modScheme); end

    % Normalize codedCB type for toolbox
    if islogical(codedCB)
        codedCB = int8(codedCB);
    elseif ~isa(codedCB,'double') && ~isa(codedCB,'int8')
        codedCB = double(codedCB);
    end

    if isempty(Nref)
        rmBits = nrRateMatchLDPC(codedCB, outLen, rv, modScheme, nLayers);
        NrefUsed = [];
    else
        validateattributes(Nref, {'numeric'}, {'scalar','finite','integer','positive'}, mfilename, 'Nref', 6);
        rmBits = nrRateMatchLDPC(codedCB, outLen, rv, modScheme, nLayers, Nref);
        NrefUsed = Nref;
    end

    info = struct();
    info.E = outLen;
    info.rv = rv;
    info.modScheme = modScheme;
    info.nLayers = nLayers;
    info.NrefUsed = NrefUsed;
end
