classdef BeamformingSRSReciprocity
%BEAMFORMINGSRSRECIPROCITY Reciprocity-based DL precoding from UL SRS channel estimates.
%
% This module follows the workflow demonstrated in MathWorks examples:
% - Configure UL SRS, estimate UL channel at gNB
% - Use TDD reciprocity to derive downlink precoder for PDSCH transmission
%
% Design goals:
% - Reuse 5G Toolbox estimation functions (nrSRS/nrSRSIndices/nrChannelEstimate)
% - Keep a small, clean API for the rest of the simulator
% - Provide a robust fallback when channel estimate is already available
%
% NOTE: This is not a full NR procedure implementation. It is a beamformer
% building block used by Link-level and Hybrid simulation.

    methods(Static)

        function out = fromSRS(carrier, srsCfg, rxGrid, opts)
            %FROM SRS Estimate channel from SRS and compute DL precoder.
            %
            % Inputs:
            %   carrier : nrCarrierConfig (or struct with numerology fields)
            %   srsCfg  : nrSRSConfig
            %   rxGrid  : received resource grid [K x L x Nr] (or [K x L x Nr x Nt])
            %
            % Name-Value:
            %   nLayers   : number of DL layers (default 1)
            %   method    : "SVD" (default) or "MRT"
            %   cdmLengths: pass-through to nrChannelEstimate (optional)
            %
            % Output struct fields:
            %   W         : [Ntx_gNB x nLayers] precoder weights (unit-norm columns)
            %   Hbar      : averaged UL channel estimate [Nr_gNB x Nt_UE]
            %   Hdl       : reciprocity DL channel [Nr_UE x Ntx_gNB]
            %   NoiseVar  : noise variance estimate (if provided by nrChannelEstimate)
            %   RefInd/RefSym/Hest : reference and channel estimate

            arguments
                carrier
                srsCfg
                rxGrid
                opts.nLayers (1,1) double {mustBeInteger,mustBePositive} = 1
                opts.method (1,:) char = "SVD"
                opts.cdmLengths double = []
            end

            if ~(exist("nrSRSIndices","file") == 2 || exist("nrSRSIndices","file") == 6)
                error("BeamformingSRSReciprocity:Missing5G","5G Toolbox function nrSRSIndices not found.");
            end

            refInd = nrSRSIndices(carrier, srsCfg);
            refSym = nrSRS(carrier, srsCfg);

            if isempty(opts.cdmLengths)
                [Hest, nVar] = nrChannelEstimate(carrier, rxGrid, refInd, refSym);
            else
                [Hest, nVar] = nrChannelEstimate(carrier, rxGrid, refInd, refSym, "CDMLengths", opts.cdmLengths);
            end

            out = BeamformingSRSReciprocity.fromHest(Hest, opts.nLayers, opts.method);
            out.NoiseVar = nVar;
            out.RefInd = refInd;
            out.RefSym = refSym;
            out.Hest = Hest;
        end

        function out = fromHest(Hest, nLayers, method)
            %FROMHEST Compute precoder from a channel estimate tensor.
            %
            % Expected Hest dimensions from nrChannelEstimate:
            %   [Nsc x Nsym x Nr x Nt]
            % where:
            %   Nr = number of receive antennas at gNB (UL)
            %   Nt = number of transmit antennas at UE (UL)
            %
            % For reciprocity we derive DL channel as transpose of averaged UL channel.

            arguments
                Hest
                nLayers (1,1) double {mustBeInteger,mustBePositive} = 1
                method (1,:) char = "SVD"
            end

            Hbar = BeamformingSRSReciprocity.averageHest(Hest);
            Hdl = Hbar.'; % Reciprocity mapping (UE Rx x gNB Tx)

            W = BeamformingSRSReciprocity.computePrecoderFromHdl(Hdl, nLayers, method);

            out = struct();
            out.W = W;
            out.Method = char(method);
            out.nLayers = nLayers;
            out.Hbar = Hbar;
            out.Hdl = Hdl;
        end

        function Hbar = averageHest(Hest)
            %AVERAGEHEST Average channel estimate over subcarriers and OFDM symbols.

            sz = size(Hest);
            if numel(sz) < 4
                error("BeamformingSRSReciprocity:BadHest","Hest must be at least 4-D: [Nsc x Nsym x Nr x Nt].");
            end

            % Average over first two dimensions
            Hbar = squeeze(mean(mean(Hest, 1), 2)); % [Nr x Nt]
            if ~ismatrix(Hbar)
                % If squeeze produced unexpected dims, force reshape
                Nr = sz(3);
                Nt = sz(4);
                Hbar = reshape(Hbar, [Nr Nt]);
            end
        end

        function W = computePrecoderFromHdl(Hdl, nLayers, method)
            %COMPUTEPRECODERFROMHDL Compute gNB precoder weights for downlink.
            %
            % Hdl dimensions: [Nr_UE x Ntx_gNB]
            % W dimensions  : [Ntx_gNB x nLayers]

            arguments
                Hdl double
                nLayers (1,1) double {mustBeInteger,mustBePositive}
                method (1,:) char
            end

            m = upper(string(method));
            [NrUE, Ntx] = size(Hdl);

            if nLayers > min(NrUE, Ntx)
                warning("BeamformingSRSReciprocity:ReduceLayers", ...
                    "Requested nLayers=%d exceeds min(NrUE,Ntx)=%d. Clipping.", nLayers, min(NrUE,Ntx));
                nLayers = min(NrUE, Ntx);
            end

            switch m
                case {"SVD","MRT"}
                    % Dominant right singular vectors of Hdl
                    [~,~,V] = svd(Hdl, "econ");
                    W = V(:, 1:nLayers);

                case "ZF"
                    % Simple ZF precoder (single-user): W = H^H (H H^H)^-1
                    G = Hdl * Hdl';
                    Wfull = (Hdl') / (G + 1e-12*eye(size(G)));
                    % Use first nLayers columns
                    if size(Wfull,2) >= nLayers
                        W = Wfull(:, 1:nLayers);
                    else
                        W = Wfull;
                    end

                otherwise
                    error("BeamformingSRSReciprocity:BadMethod","Unknown method: %s", method);
            end

            % Normalize columns
            for i = 1:size(W,2)
                ni = norm(W(:,i));
                if ni > 0
                    W(:,i) = W(:,i) ./ ni;
                end
            end
        end

    end
end
