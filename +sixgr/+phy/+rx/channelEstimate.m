function [Hest, nVar, info] = channelEstimate(carrier, rxGrid, refInd, refSym, varargin)
%CHANNELESTIMATE Generic channel estimation wrapper (DMRS/CSI-RS based).
%
%   [Hest, nVar, info] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, refInd, refSym, ...)
%
%   This wraps 5G Toolbox nrChannelEstimate and standardizes outputs.
%
%   Inputs
%     carrier : nrCarrierConfig
%     rxGrid  : K-by-L-by-R received resource grid
%     refInd  : reference signal indices (DMRS/CSI-RS), as produced by
%               nrPDSCHDMRSIndices/nrPUSCHDMRSIndices/nrCSIRSIndices, etc.
%     refSym  : reference symbols, as produced by corresponding generators
%
%   Name-value pairs are forwarded to nrChannelEstimate (e.g.:
%     "CDMLengths", "AveragingWindow", "Interpolation", ...).
%
%   Outputs
%     Hest : K-by-L-by-R-by-P channel estimate
%     nVar : estimated noise variance (scalar) if returned by the engine
%     info : metadata struct

    if nargin < 4
        error("sixgr:phy:channelEstimate:InvalidInput", ...
            "carrier, rxGrid, refInd, refSym are required.");
    end
    if isempty(refInd) || isempty(refSym)
        error("sixgr:phy:channelEstimate:InvalidReference", ...
            "refInd/refSym must be non-empty.");
    end

    useFastMex = false;
    fwd = varargin;
    if ~isempty(varargin)
        keep = true(size(varargin));
        i = 1;
        while i <= numel(varargin)-1
            k = varargin{i};
            if (ischar(k) || isstring(k)) && strcmpi(string(k), "UseFastMex")
                useFastMex = logical(varargin{i+1});
                keep(i:i+1) = false;
                i = i + 2;
                continue;
            end
            i = i + 2;
        end
        fwd = varargin(keep);
    end

    if useFastMex && (exist("sixgr_channel_est_ls_kernel_mex","file") == 3 || exist("sixgr_channel_est_ls_kernel","file") == 2)
        try
            rxRef = nrExtractResources(refInd, rxGrid);
            if ~isvector(rxRef)
                rxRef = rxRef(:,1);
            end
            refV = refSym(:);
            if ~isvector(refV)
                refV = refV(:,1);
            end
            if exist("sixgr_channel_est_ls_kernel_mex","file") == 3
                [hScalar, nVar] = sixgr_channel_est_ls_kernel_mex(rxRef(:), refV(:));
                engine = "sixgr_channel_est_ls_kernel_mex";
            else
                [hScalar, nVar] = sixgr_channel_est_ls_kernel(rxRef(:), refV(:));
                engine = "sixgr_channel_est_ls_kernel";
            end
            Hest = cast(ones(size(rxGrid)), "like", rxGrid) .* cast(hScalar, "like", rxGrid);
            info = struct();
            info.EngineUsed = engine;
            info.RxGridSize = size(rxGrid);
            info.HestSize = size(Hest);
            info.NoiseVar = nVar;
            return;
        catch
            % Fallback to full nrChannelEstimate path.
        end
    end

    engine = "nrChannelEstimate";
    try
        % Most common signature: [Hest, nVar] = nrChannelEstimate(carrier, rxGrid, refInd, refSym, ...)
        [Hest, nVar] = nrChannelEstimate(carrier, rxGrid, refInd, refSym, fwd{:});
    catch ME
        error("sixgr:phy:channelEstimate:Failed", ...
            "nrChannelEstimate failed: %s", ME.message);
    end

    info = struct();
    info.EngineUsed = engine;
    info.RxGridSize = size(rxGrid);
    info.HestSize = size(Hest);
    info.NoiseVar = nVar;
end
