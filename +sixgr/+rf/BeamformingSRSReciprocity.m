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
% - Accept an explicitly supplied channel estimate without a fallback oracle
%
% NOTE: This is not a full NR procedure implementation. It is a beamformer
% building block used by Link-level and Hybrid simulation. Reciprocity assumes
% calibrated TDD RF (or an explicitly ideal RF model); this is not a CSI PMI
% codebook, and coherent wideband averaging is not a per-PRB estimator.

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

            out = sixgr.rf.BeamformingSRSReciprocity.fromHest(Hest, opts.nLayers, opts.method);
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

            Hbar = sixgr.rf.BeamformingSRSReciprocity.averageHest(Hest);
            Hdl = Hbar.'; % Reciprocity mapping (UE Rx x gNB Tx)

            W = sixgr.rf.BeamformingSRSReciprocity.computePrecoderFromHdl(Hdl, nLayers, method);

            out = struct();
            out.W = W;
            out.Method = char(method);
            out.nLayers = nLayers;
            out.Hbar = Hbar;
            out.Hdl = Hdl;
            out.ChannelReduction = "coherent_wideband_mean_of_received_estimate";
            out.ReciprocityAssumption = "calibrated_TDD_RF_or_explicit_ideal_reciprocity";
            out.PowerNormalization = "unit_norm_per_layer_column_not_total_transmit_power";
            out.PrecoderFamily = "non_codebook_linear_beamformer_not_NR_PMI";
        end

        function out = fromMeasuredSRS(measurement, cfg, currentSlot)
            %FROMMEASUREDSRS Authoritative measured-SRS RI/SRI/TPMI path.
            arguments
                measurement (1,1) sixgr.phy.mimo.CSIMeasurementState
                cfg (1,1) struct
                currentSlot (1,1) double {mustBeInteger,mustBeNonnegative}
            end
            measurement.validateAt(currentSlot);
            if ~contains(upper(measurement.ResourceType),"SRS")
                error("sixgr:mimo:MissingSRSState", ...
                    "UL reciprocity/TPMI selection requires a measured SRS resource.");
            end
            localCfg = cfg;
            localCfg.NoiseVar = double(measurement.NoiseVariance);
            localCfg.Strict = true;
            [W,tpmi,~,~,selection] = sixgr.mimo.selectULBeamFromSRS( ...
                [],[],measurement.ChannelEstimate,[],localCfg);
            out = struct( ...
                "W",W, ...
                "RI",double(selection.RI), ...
                "SRI",double(sixgr.util.structGet(selection,"SRI",0)), ...
                "TPMI",double(tpmi), ...
                "MeasurementID",measurement.MeasurementID, ...
                "MeasurementSlot",measurement.Slot, ...
                "MeasurementAgeSlots",double(currentSlot-measurement.Slot), ...
                "MeasurementProvenance",measurement.Provenance, ...
                "SelectionMatrixSHA256",selection.SelectionMatrixSHA256, ...
                "SchedulerMatrixSHA256",selection.SchedulerMatrixSHA256, ...
                "AppliedMatrixSHA256",selection.AppliedMatrixSHA256, ...
                "MeasurementAuthoritative",true, ...
                "ConfiguredOverrideUsed",false, ...
                "Method","measured_srs_ri_sri_tpmi_receiver_objective");
        end

        function Hbar = averageHest(Hest)
            %AVERAGEHEST Average channel estimate over subcarriers and OFDM symbols.

            if ~(isnumeric(Hest) && ~isempty(Hest) && ndims(Hest)<=4 ...
                    && all(isfinite(Hest),'all'))
                error("BeamformingSRSReciprocity:BadHest", ...
                    "Hest must be finite [Nsc x Nsym x Nr x Nt], with implicit trailing singleton dimensions allowed.");
            end
            % MATLAB omits trailing singleton dimensions. squeeze additionally
            % transposes the intended shape when Nr=1 and Nt>1. Keep axes.
            Hbar = reshape(mean(mean(Hest,1),2),size(Hest,3),size(Hest,4));
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
            if ~ismatrix(Hdl) || isempty(Hdl) || any(~isfinite(Hdl),'all')
                error("BeamformingSRSReciprocity:BadChannel", ...
                    "Hdl must be a finite nonempty receiver-by-transmitter matrix.");
            end
            if nLayers > min(NrUE, Ntx)
                error("BeamformingSRSReciprocity:InvalidLayers", ...
                    "Requested nLayers=%d exceeds min(NrUE,Ntx)=%d; rank selection must occur upstream.", nLayers, min(NrUE,Ntx));
            end

            switch m
                case "SVD"
                    % Dominant right singular vectors of Hdl
                    [~,D,V] = svd(Hdl, "econ");
                    if D(nLayers,nLayers) <= max(size(Hdl))*eps(norm(Hdl,2))
                        error("BeamformingSRSReciprocity:RankDeficientSVD", ...
                            "Requested SVD stream is in the numerical channel nullspace.");
                    end
                    W = V(:, 1:nLayers);
                case "MRT"
                    % Matched transmission to the selected receive streams.
                    % Unlike SVD this does not promise inter-stream nulling.
                    W = Hdl(1:nLayers,:)';
                case "ZF"
                    % Hsel*Wraw=I. No hidden diagonal loading: regularized ZF
                    % is a different receiver-policy choice and needs a name.
                    selected = Hdl(1:nLayers,:);
                    if rank(selected) < nLayers
                        error("BeamformingSRSReciprocity:RankDeficientZF", ...
                            "Selected channel rows cannot support the requested ZF streams.");
                    end
                    [Q,R] = qr(selected',0);
                    W = Q/R';

                otherwise
                    error("BeamformingSRSReciprocity:BadMethod","Unknown method: %s", method);
            end

            % Normalize columns
            for i = 1:size(W,2)
                ni = norm(W(:,i));
                if ~(isfinite(ni) && ni > 0)
                    error("BeamformingSRSReciprocity:ZeroPrecoder", ...
                        "Requested stream has no finite nonzero precoding vector.");
                end
                W(:,i) = W(:,i) ./ ni;
            end
        end

    end
end
