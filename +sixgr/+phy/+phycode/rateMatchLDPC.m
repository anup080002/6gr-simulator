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
        positionMap = localRateMatchPositionMap(codedCB, outLen, rv, modScheme, nLayers, []);
    else
        validateattributes(Nref, {'numeric'}, {'scalar','finite','integer','positive'}, mfilename, 'Nref', 6);
        rmBits = nrRateMatchLDPC(codedCB, outLen, rv, modScheme, nLayers, Nref);
        NrefUsed = Nref;
        positionMap = localRateMatchPositionMap(codedCB, outLen, rv, modScheme, nLayers, Nref);
    end

    info = struct();
    info.E = outLen;
    info.rv = rv;
    info.modScheme = modScheme;
    info.nLayers = nLayers;
    info.NrefUsed = NrefUsed;
    info.MotherCodeShape = uint32(size(codedCB));
    info.PositionMap = positionMap;
    info.CircularBufferPositionMap = positionMap;
    info.EPerCodeBlock = localEPerCodeBlock(positionMap, size(codedCB, 2));
    info.Accounting = localAccounting(codedCB, positionMap, NrefUsed);
end

function positionMap = localRateMatchPositionMap(codedCB, outLen, rv, modScheme, nLayers, Nref)
codedShape = size(codedCB);
labels = reshape((1:prod(codedShape)).', codedShape);
% NULL/filler positions affect selection, not only transmitted values.
% The labels must use precisely the mask used by the real bit rate matcher.
labels(codedCB < 0) = -1;
if isempty(Nref)
    matched = nrRateMatchLDPC(labels, outLen, rv, modScheme, nLayers);
else
    matched = nrRateMatchLDPC(labels, outLen, rv, modScheme, nLayers, Nref);
end
matched = double(matched(:));
[rowIdx, cbIdx] = ind2sub(codedShape, matched);
positionMap = struct();
positionMap.OutputBitIndex = uint32((1:numel(matched)).');
positionMap.MotherCodeLinearIndex = uint32(matched);
positionMap.MotherCodeBitIndex = uint32(rowIdx(:));
positionMap.CodeBlockIndex = uint16(cbIdx(:));
positionMap.MotherCodeShape = uint32(codedShape);
positionMap.ContractVersion = "LDPCSelection/v2";
end

function a = localAccounting(codedCB, map, Nref)
[N,C] = size(codedCB);
Ncb=N; if ~isempty(Nref), Ncb=min(N,double(Nref)); end
a=struct('ContractVersion',"LDPCSelectionAccounting/v2", ...
    'Source',"actual_nrRateMatchLDPC_selection_with_filler_mask", ...
    'EncoderOutputPositions',repmat(N,1,C), ...
    'BufferPositions',repmat(Ncb,1,C), ...
    'BufferFillerPositions',sum(codedCB(1:Ncb,:)<0,1), ...
    'EligibleBufferPositions',sum(codedCB(1:Ncb,:)>=0,1), ...
    'SelectedPositions',zeros(1,C),'UniqueSelectedPositions',zeros(1,C), ...
    'RepeatedSelections',zeros(1,C),'UnselectedEligiblePositions',zeros(1,C));
for c=1:C
    idx=double(map.MotherCodeBitIndex(map.CodeBlockIndex==c));
    a.SelectedPositions(c)=numel(idx);
    a.UniqueSelectedPositions(c)=numel(unique(idx));
end
a.RepeatedSelections=a.SelectedPositions-a.UniqueSelectedPositions;
a.UnselectedEligiblePositions=a.EligibleBufferPositions-a.UniqueSelectedPositions;
assert(all(a.UnselectedEligiblePositions>=0),'sixgr:phy:InvalidLDPCSelectionAccounting', ...
    'Selected positions exceed the eligible circular buffer.');
end

function e = localEPerCodeBlock(positionMap, C)
e = zeros(1, C);
cb = double(positionMap.CodeBlockIndex(:));
for c = 1:C
    e(c) = nnz(cb == c);
end
end
