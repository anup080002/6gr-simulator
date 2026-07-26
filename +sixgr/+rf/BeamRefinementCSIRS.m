classdef BeamRefinementCSIRS
%BeamRefinementCSIRS  CSI-RS based beam refinement helpers.
%
% This class provides small, toolbox-friendly utilities for creating a
% beamforming codebook from an antenna array description (as produced by
% sixgr.rf.AntennaArrayFactory).
%
% Design notes:
% - We avoid using default values in the arguments block that depend on other
%   inputs, because MATLAB validates defaults at parse time. If a computed
%   default violates validation (e.g., mustBePositive), MATLAB errors before
%   executing the function body.
% - Therefore, we use safe constant defaults (1) and derive sizes inside the
%   function based on nargin and the provided array struct.
%
% This file is intended to be ASCII-only to avoid "Invalid text character"
% errors when copying between environments.

    methods(Static)

        function W = makeCodebookFromArray(arr, nBeamsRow, nBeamsCol)
            %makeCodebookFromArray  Create a DFT codebook for a URA/ULA.
            %
            %   W = makeCodebookFromArray(arr)
            %   W = makeCodebookFromArray(arr, nBeamsRow)
            %   W = makeCodebookFromArray(arr, nBeamsRow, nBeamsCol)
            %
            % Output:
            %   W : [Nant x Nbeams] complex weights (each column unit-norm)
            %
            % The default behavior (no nBeamsRow/nBeamsCol specified) is to
            % create a "full" separable DFT codebook sized to the array
            % geometry (nRow x nCol).

            arguments
                arr (1,1) struct
                nBeamsRow (1,1) double {mustBeInteger, mustBePositive} = 1
                nBeamsCol (1,1) double {mustBeInteger, mustBePositive} = 1
            end

            % Determine array grid dimensions
            [nRow, nCol] = sixgr.rf.BeamRefinementCSIRS.localGetArrayDims(arr);

            % Derive default beams if not supplied
            if nargin == 1
                nBeamsRow = nRow;
                nBeamsCol = nCol;
            elseif nargin == 2
                nBeamsCol = nCol;
            end

            % Clamp
            nBeamsRow = max(1, min(nRow, round(nBeamsRow)));
            nBeamsCol = max(1, min(nCol, round(nBeamsCol)));

            % Build separable DFT codebook (URA: kron(col,row); ULA: nRow=1)
            WrFull = sixgr.rf.BeamRefinementCSIRS.localDFT(nRow);
            WcFull = sixgr.rf.BeamRefinementCSIRS.localDFT(nCol);

            idxR = sixgr.rf.BeamRefinementCSIRS.localPickIndices(nRow, nBeamsRow);
            idxC = sixgr.rf.BeamRefinementCSIRS.localPickIndices(nCol, nBeamsCol);

            Wr = WrFull(:, idxR);
            Wc = WcFull(:, idxC);

            W = kron(Wc, Wr); % size (nRow*nCol) x (nBeamsRow*nBeamsCol)

            % Normalize each beam to unit norm (columns)
            nrm = sqrt(sum(abs(W).^2, 1));
            nrm(nrm == 0) = 1;
            W = W ./ nrm;

            % If the array struct reports Nant, trim/pad to match Nant.
            if isfield(arr, "Nant")
                Nant = double(arr.Nant);
                if size(W,1) > Nant
                    W = W(1:Nant, :);
                elseif size(W,1) < Nant
                    W = [W; zeros(Nant-size(W,1), size(W,2))];
                    % Renormalize after padding
                    nrm = sqrt(sum(abs(W).^2, 1));
                    nrm(nrm == 0) = 1;
                    W = W ./ nrm;
                end
            end
        end

        function [wBest, idxBest, metric] = selectBestBeam(Hest, W)
            %selectBestBeam  Select best beam from codebook given channel estimate.
            %
            % Hest: [Nr x Nt] or [Nt x 1] channel estimate
            % W   : [Nt x Nbeams] codebook
            %
            % Returns:
            %   wBest   : [Nt x 1] best beam
            %   idxBest : beam index
            %   metric  : |H*w|^2 metric values

            if isempty(Hest) || isempty(W)
                wBest = [];
                idxBest = 1;
                metric = [];
                return;
            end

            % Ensure H is [Nr x Nt]
            if isvector(Hest)
                H = reshape(Hest, 1, []);
            else
                H = Hest;
            end

            Y = H * W;                 % [Nr x Nbeams]
            metric = sum(abs(Y).^2, 1); % energy across Rx dims
            [~, idxBest] = max(metric);
            wBest = W(:, idxBest);
        end

        function [wBest, resourceID, decision] = selectMeasuredResource(measurement, W, options)
            %SELECTMEASUREDRESOURCE Strict receiver-evidence beam refinement.
            arguments
                measurement (1,1) sixgr.phy.mimo.CSIMeasurementState
                W
                options.CurrentSlot (1,1) double {mustBeInteger,mustBeNonnegative}
                options.Receiver (1,1) string = "MMSE"
                options.ResourceIDs string = strings(0,1)
            end
            measurement.validateAt(options.CurrentSlot);
            if ~contains(upper(measurement.ResourceType),"CSI-RS")
                error("sixgr:mimo:BeamReportMismatch", ...
                    "P2 refinement requires a measured CSI-RS resource.");
            end
            H = double(measurement.ChannelEstimate);
            if ndims(H) == 3
                H = mean(H,3,"omitnan");
            end
            if ~ismatrix(H) || size(H,2) ~= size(W,1)
                error("sixgr:mimo:PrecoderDimensionMismatch", ...
                    "CSI-RS measurement ports do not match the beam codebook.");
            end
            [wBest,decision] = sixgr.phy.mimo.CodebookEngine.select( ...
                H,reshape(W,size(W,1),1,size(W,2)), ...
                NoiseVariance=double(measurement.NoiseVariance), ...
                InterferenceCovariance=measurement.InterferenceCovariance, ...
                Receiver=options.Receiver);
            ids = options.ResourceIDs;
            if isempty(ids)
                ids = "CSI-RS-"+string(0:size(W,2)-1);
            end
            if numel(ids) ~= size(W,2)
                error("sixgr:mimo:BeamReportMismatch", ...
                    "ResourceIDs must identify every CSI-RS beam.");
            end
            resourceID = ids(decision.SelectedIndex+1);
            decision.MeasurementID = measurement.MeasurementID;
            decision.ResourceID = resourceID;
            decision.GeometryOracleUsed = false;
            decision.SelectionSource = "measured_csirs_receiver_objective";
        end

    end

    methods(Static, Access=private)

        function [nRow, nCol] = localGetArrayDims(arr)
            % Try multiple representations in priority order.
            nRow = 1; nCol = 1;

            if isfield(arr, "nRow") && isfield(arr, "nCol")
                if ~isempty(arr.nRow) && ~isempty(arr.nCol) && arr.nRow > 0 && arr.nCol > 0
                    nRow = double(arr.nRow);
                    nCol = double(arr.nCol);
                    return;
                end
            end

            if isfield(arr, "Size") && isnumeric(arr.Size) && numel(arr.Size) >= 2
                nRow = double(arr.Size(1));
                nCol = double(arr.Size(2));
                if nRow > 0 && nCol > 0
                    return;
                end
            end

            if isfield(arr, "Array")
                try
                    % phased.URA exposes Size as [nRow nCol]
                    sz = arr.Array.Size;
                    if numel(sz) >= 2
                        nRow = double(sz(1));
                        nCol = double(sz(2));
                        if nRow > 0 && nCol > 0
                            return;
                        end
                    end
                catch
                    % ignore
                end
            end

            if isfield(arr, "Nant")
                Nant = double(arr.Nant);
                if Nant <= 0
                    nRow = 1; nCol = 1;
                    return;
                end
                % Prefer square-ish URA
                nRow = max(1, floor(sqrt(Nant)));
                nCol = max(1, floor(Nant / nRow));
                if nRow * nCol ~= Nant
                    % Fallback to ULA representation
                    nRow = 1;
                    nCol = Nant;
                end
                return;
            end
        end

        function idx = localPickIndices(N, K)
            % Pick K indices in [1..N] as evenly spaced as possible.
            if K >= N
                idx = 1:N;
                return;
            end
            if K <= 1
                idx = 1;
                return;
            end
            x = linspace(1, N, K);
            idx = unique(max(1, min(N, round(x))));
            % If unique reduced count, fill missing by adding nearest unused indices
            if numel(idx) < K
                unused = setdiff(1:N, idx);
                need = K - numel(idx);
                idx = [idx, unused(1:need)];
                idx = sort(idx);
            end
        end

        function F = localDFT(N)
            % localDFT  Unit-norm DFT matrix (coder-friendly).
            %
            % F is N x N, with columns normalized by sqrt(N).
            if N <= 1
                F = 1;
                return;
            end
            F = complex(zeros(N, N));
            invS = 1 / sqrt(N);
            for n = 1:N
                for k = 1:N
                    F(n,k) = exp(-1j * 2*pi * (n-1) * (k-1) / N) * invS;
                end
            end
        end

    end
end
