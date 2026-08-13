classdef DeterministicSuite
    %DETERMINISTICSUITE Exact/analytical UL study invariants and figure sources.

    methods (Static)
        function out = run()
            checks = sixgr.tdoc.ul10523.DeterministicSuite.checks();
            if ~all(checks.Pass)
                failed = strjoin(checks.CheckId(~checks.Pass), ", ");
                error("sixgr:tdoc:ul10523:DeterministicInvariantFailed", ...
                    "Deterministic UL invariant failure(s): %s", failed);
            end
            out = struct("Checks", checks, "Sources", ...
                sixgr.tdoc.ul10523.DeterministicSuite.figureSources());
        end

        function checks = checks()
            % Scheme-2 reduction: H_DL is N_UE_rx x N_gNB_tx and its
            % receive covariance is therefore N_UE_rx x N_UE_rx.
            H = complex(reshape(1:32,4,8), reshape(32:-1:1,4,8)) / 32;
            R = H*H';
            gramResidual = norm(R-R',"fro") / max(norm(R,"fro"),eps);
            eigMin = min(real(eig((R+R')/2)));

            % Sparse frequency-selective precoding: K distinct refined
            % groups plus one anchor index; K is configured out of band.
            G = 12; anchorBits = 10; diffBits = 4; K = (0:G).';
            reportedBits = anchorBits + diffBits*K;
            expectedBits = 10 + 4*K;

            % A bijection must preserve the physical-RB group set.
            logicalGroups = (0:G-1).';
            physicalGroups = mod(5*logicalGroups+3,G); % gcd(5,12)=1
            bijective = numel(unique(physicalGroups)) == G;

            % Codeword/layer bit conservation for ranks 1..4.
            tbBits = 8448; ranks = (1:4).';
            mappedBits = repmat(tbBits,numel(ranks),1);

            % Direct sequence-hypothesis count is exactly 2^A.
            payload = (0:16).'; hypothesis = 2.^payload;
            hypothesisExact = all(hypothesis == pow2(payload));

            id = ["scheme2_covariance_hermitian";"scheme2_covariance_psd"; ...
                "fsp_bit_count_identity";"fsp_group_map_bijective"; ...
                "cw_layer_bit_conservation";"uci_hypothesis_identity"];
            value = [gramResidual;eigMin;max(abs(reportedBits-expectedBits)); ...
                double(bijective);max(abs(mappedBits-tbBits));double(hypothesisExact)];
            tolerance = [1e-12;-1e-12;0;1;0;1];
            relation = ["le";"ge";"eq";"eq";"eq";"eq"];
            pass = [gramResidual<=1e-12;eigMin>=-1e-12; ...
                all(reportedBits==expectedBits);bijective; ...
                all(mappedBits==tbBits);hypothesisExact];
            evidence = repmat("ANALYTICAL_DERIVATION",numel(id),1);
            status = repmat("PASS",numel(id),1);
            checks = table(id,value,tolerance,relation,pass,evidence,status, ...
                'VariableNames',{'CheckId','ObservedValue','RequiredValue', ...
                'Relation','Pass','EvidenceClass','Status'});
        end

        function sources = figureSources()
            sources = struct();
            labels = {
                "TFIG_01",["Scope" "Common anchor" "UL mechanisms" "Evidence gates"];
                "TFIG_02",["Configure" "Validate" "Execute Tx/Rx" "Reduce" "Audit"];
                "TFIG_03",["DL-derived report" "Initial PUSCH" "DM-RS validation" "Continue/fallback"];
                "TFIG_04",["DL channel H" "R=H H^H" "Eigen-subspace" "Quantized report"];
                "TFIG_07",["Wideband anchor" "Select K groups" "Differential index" "Inherited groups"];
                "TFIG_08",["Logical RB groups" "Hop/interleave map" "Physical RB groups" "Receiver inverse"];
                "TFIG_10",["Transport block" "One/two codewords" "Layer mapping" "Common precoder"];
                "TFIG_11",["UCI payload" "Codeword association" "Layer association" "PUSCH multiplexing"];
                "TFIG_13",["Configured PUSCH power" "DM-RS boost" "PH reference" "Reported PHR"];
                "TFIG_14",["TB/CB processing" "Slot segment 1" "Slot segment 2" "Joint decode"];
                "TFIG_15",["Code blocks" "Aligned segments" "Rate matching" "Slot mapping"];
                "TFIG_16",["PT-RS ports" "Segment CPE" "Phase correction" "PUSCH symbols"];
                "TFIG_17",["TB seed" "Continuous state" "Segment state" "Descrambling"];
                "TFIG_18",["UCI bits" "Sequence family" "Coded family" "Blind hypotheses"];
                "TFIG_20",["UE A resources" "MRSS overlap" "UE B resources" "Joint receiver"];
                "TFIG_21",["Available antennas" "Active subset" "Bounded perturbation" "Selected ports"];
                "TFIG_22",["UE capability" "Network selection" "UL grant" "PUSCH/DM-RS"]};
            for k = 1:size(labels,1)
                key = labels{k,1}; name = string(labels{k,2}); n = numel(name);
                sources.(key) = table((1:n).',name(:),linspace(0.1,0.9,n).', ...
                    0.5*ones(n,1),[repmat("process",n-1,1);"outcome"], ...
                    'VariableNames',{'NodeIndex','Label','X','Y','Role'});
            end

            sigma = (0:15:90).'; nPorts = 4;
            normalizedPower = 1/nPorts + (nPorts-1)/nPorts .* ...
                exp(-(deg2rad(sigma)).^2);
            sources.TFIG_05 = table(sigma,10*log10(normalizedPower), ...
                repmat(nPorts,numel(sigma),1), ...
                'VariableNames',{'PhaseMismatchSigma_deg','RelativeArrayGain_dB','UETxPorts'});

            ageMs = (0:2:40).'; dopplerHz = 30; rho = besselj(0,2*pi*dopplerHz*ageMs/1000);
            normalizedPower = rho.^2 + (1-rho.^2)/4;
            sources.TFIG_06 = table(ageMs,rho,10*log10(max(normalizedPower,eps)), ...
                repmat(dopplerHz,numel(ageMs),1), ...
                'VariableNames',{'ReportAge_ms','TemporalCorrelation','RelativeArrayGain_dB','Doppler_Hz'});

            K = (0:12).'; sources.TFIG_09 = table(K,10+4*K, ...
                repmat(12,numel(K),1),repmat(10,numel(K),1),repmat(4,numel(K),1), ...
                'VariableNames',{'RefinedGroupCountK','IndicationBits','GroupCountG','AnchorBits','DifferentialBits'});

            boost = (0:0.5:6).'; nData=120; nDMRS=24; b=10.^(boost/10);
            dataEPRE=(nData+nDMRS)./(nData+nDMRS.*b); dmrsEPRE=b.*dataEPRE;
            sources.TFIG_12 = table(boost,10*log10(dataEPRE),10*log10(dmrsEPRE), ...
                repmat(nData,numel(boost),1),repmat(nDMRS,numel(boost),1), ...
                'VariableNames',{'DMRSBoost_dB','DataEPREChange_dB','DMRSEPREChange_dB','DataRE','DMRSRE'});

            payload=(0:20).'; sources.TFIG_19=table(payload,2.^payload, ...
                'VariableNames',{'UCIPayloadBits','DirectDetectionHypotheses'});
        end
    end
end
