function Hsnap = channelEstimateSnapshots(Hest, varargin)
%CHANNELESTIMATESNAPSHOTS Preserve spatial channel energy across REs.
%
% Hsnap = sixgr.mimo.channelEstimateSnapshots(Hest) converts an NR channel
% estimate arranged as K-by-L-by-Nrx[-by-Ntx] into an
% Nrx-by-Ntx-by-Nsnapshot tensor.  It deliberately does not coherently
% average complex channel coefficients across frequency or time: doing so
% can cancel valid multipath phase rotations and corrupt RI/PMI/beam
% metrics.  A logical K-by-L PilotMask may restrict snapshots to OFDM
% symbols carrying the measured reference signal while retaining all REs
% on those symbols.

arguments
    Hest {mustBeNumeric}
end
arguments (Repeating)
    varargin
end

p = inputParser;
p.FunctionName = "sixgr.mimo.channelEstimateSnapshots";
addParameter(p, "PilotMask", []);
parse(p, varargin{:});

if isempty(Hest)
    Hsnap = [];
    return;
end
if ndims(Hest) > 4
    error("sixgr:mimo:InvalidChannelEstimateDimensions", ...
        "Hest must be K-by-L, K-by-L-by-Nrx, or K-by-L-by-Nrx-by-Ntx.");
end

H = double(Hest);
K = size(H, 1);
L = size(H, 2);
pilotMask = p.Results.PilotMask;
if isempty(pilotMask)
    symbolSet = 1:L;
else
    if ~(islogical(pilotMask) && isequal(size(pilotMask), [K L]))
        error("sixgr:mimo:InvalidChannelEstimatePilotMask", ...
            "PilotMask must be a logical K-by-L matrix matching Hest.");
    end
    symbolSet = find(any(pilotMask, 1));
    if isempty(symbolSet)
        Hsnap = [];
        return;
    end
end

if ndims(H) >= 4
    nRx = size(H, 3);
    nTx = size(H, 4);
elseif ndims(H) == 3
    nRx = size(H, 3);
    nTx = 1;
else
    nRx = 1;
    nTx = 1;
end

Hsnap = complex(zeros(nRx, nTx, K * numel(symbolSet)));
writeIndex = 0;
for symbolIndex = symbolSet
    for subcarrierIndex = 1:K
        if ndims(H) >= 4
            snapshot = reshape(H(subcarrierIndex, symbolIndex, :, :), nRx, nTx);
        elseif ndims(H) == 3
            snapshot = reshape(H(subcarrierIndex, symbolIndex, :), nRx, 1);
        else
            snapshot = H(subcarrierIndex, symbolIndex);
        end
        finiteMask = isfinite(real(snapshot)) & isfinite(imag(snapshot));
        if all(finiteMask(:))
            writeIndex = writeIndex + 1;
            Hsnap(:, :, writeIndex) = snapshot;
        end
    end
end
Hsnap = Hsnap(:, :, 1:writeIndex);
if writeIndex == 0
    Hsnap = [];
end
end
