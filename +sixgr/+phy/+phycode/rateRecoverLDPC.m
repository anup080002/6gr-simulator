function [recLLR, info] = rateRecoverLDPC(inLLR, trblkLen, R, rv, modScheme, nLayers, numCB, Nref, varargin)
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
    opt = localParseOpts(varargin{:});

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

    layout = opt.CodingLayout;
    if ~isempty(layout)
        localValidateCodingLayout(layout, inLLR, trblkLen, rv, modScheme, nLayers, numCB, Nref);
        numCB = double(layout.NumCodeBlocks);
        if ~isempty(layout.Nref)
            Nref = double(layout.Nref);
        end
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
    if ~isempty(layout)
        localValidateRecoveredLLRShape(layout, recLLR);
    end

    info = struct();
    info.A = trblkLen;
    info.R = R;
    info.rv = rv;
    info.modScheme = modScheme;
    info.nLayers = nLayers;
    info.numCBUsed = numCBUsed;
    info.NrefUsed = NrefUsed;
    info.InputLLRCount = double(numel(inLLR));
    info.OutputLLRCount = double(numel(recLLR));
    info.OutputShape = uint32(size(recLLR));
    info.InputDomain = "rate_matched_codeword_llr";
    info.OutputDomain = "mother_code_llr_by_code_block";
    info.FillerLLRSemantics = "Toolbox nrRateRecoverLDPC output preserved at CodingLayout filler positions";
    info.CodingLayout = layout;
    if ~isempty(layout)
        info.PositionMap = layout.RateMatchPositionMap;
        info.CircularBufferPositionMap = layout.CircularBufferPositionMap;
        info.CodingLayoutHash = char(string(sixgr.util.structGet(layout, "CodingLayoutHash", layout.CombineSignature)));
        info.CombineSignature = char(string(layout.CombineSignature));
        info.RateMatchSignature = char(string(layout.RateMatchSignature));
        info.EPerCodeBlock = double(layout.E_r);
    end
end

function localValidateRecoveredLLRShape(layout, recLLR)
if ~ismatrix(recLLR)
    error('sixgr:phy:rateRecoverLDPC:CodingLayoutOutputMismatch', ...
        'Recovered LLR output must be a 2-D mother-code-by-codeblock matrix.');
end
expectedRows = double(layout.MotherCodeLength);
expectedCols = double(layout.NumCodeBlocks);
if size(recLLR, 1) ~= expectedRows || size(recLLR, 2) ~= expectedCols
    error('sixgr:phy:rateRecoverLDPC:CodingLayoutOutputMismatch', ...
        'Recovered LLR shape %s does not match CodingLayout mother-code shape [%d %d].', ...
        mat2str(size(recLLR)), expectedRows, expectedCols);
end
end

function opt = localParseOpts(varargin)
opt = struct("CodingLayout", []);
if isempty(varargin)
    return;
end
if mod(numel(varargin), 2) ~= 0
    error('sixgr:phy:rateRecoverLDPC:BadNameValue', ...
        'Name-value arguments must come in pairs.');
end
for i = 1:2:numel(varargin)
    key = lower(string(varargin{i}));
    switch key
        case "codinglayout"
            opt.CodingLayout = varargin{i + 1};
        otherwise
            error('sixgr:phy:rateRecoverLDPC:BadNameValue', ...
                'Unknown option %s.', char(key));
    end
end
end

function localValidateCodingLayout(layout, inLLR, trblkLen, rv, modScheme, nLayers, numCB, Nref)
if ~(isstruct(layout) && ~isempty(fieldnames(layout)))
    error('sixgr:phy:rateRecoverLDPC:BadCodingLayout', ...
        'CodingLayout must be a non-empty struct.');
end
if double(layout.TransportBlockSize) ~= double(trblkLen)
    error('sixgr:phy:rateRecoverLDPC:CodingLayoutMismatch', ...
        'CodingLayout A=%d does not match rate recovery A=%d.', ...
        double(layout.TransportBlockSize), double(trblkLen));
end
if double(layout.RV) ~= double(rv)
    error('sixgr:phy:rateRecoverLDPC:CodingLayoutMismatch', ...
        'CodingLayout RV=%d does not match rate recovery RV=%d.', ...
        double(layout.RV), double(rv));
end
if ~strcmpi(char(string(layout.Modulation)), char(string(modScheme))) || ...
        double(layout.NumLayers) ~= double(nLayers)
    error('sixgr:phy:rateRecoverLDPC:CodingLayoutMismatch', ...
        'CodingLayout modulation/layer contract does not match rate recovery inputs.');
end
if double(layout.RateMatchedBitCount) ~= numel(inLLR)
    error('sixgr:phy:rateRecoverLDPC:CodingLayoutMismatch', ...
        'CodingLayout E=%d does not match received LLR count %d.', ...
        double(layout.RateMatchedBitCount), numel(inLLR));
end
if ~isempty(numCB) && double(layout.NumCodeBlocks) ~= double(numCB)
    error('sixgr:phy:rateRecoverLDPC:CodingLayoutMismatch', ...
        'CodingLayout C=%d does not match numCB=%d.', ...
        double(layout.NumCodeBlocks), double(numCB));
end
if ~isempty(Nref) && ~isempty(layout.Nref) && double(layout.Nref) ~= double(Nref)
    error('sixgr:phy:rateRecoverLDPC:CodingLayoutMismatch', ...
        'CodingLayout Nref=%d does not match Nref=%d.', ...
        double(layout.Nref), double(Nref));
end
end
