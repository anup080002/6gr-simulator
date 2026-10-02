classdef MCSCatalog
    %MCSCATALOG Canonical entries and representation maps for AI 10.3.2.

    methods (Static)
        function entries = baseline256()
            qm = [2 2 2 2 2 4 4 4 4 4 4 6 6 6 6 6 6 6 6 6 8 8 8 8 8 8 8 8];
            r = [120 193 308 449 602 378 434 490 553 616 658 ...
                466 517 567 616 666 719 772 822 873 ...
                682.5 711 754 797 841 885 916.5 948];
            entries = sixgr.studies.ran1ai1032.MCSEntry.empty(0,1);
            for k = 1:numel(qm)
                entries(k,1) = sixgr.studies.ran1ai1032.MCSEntry( ...
                    "B" + compose("%02d", k-1), qm(k), r(k), "baseline", ...
                    "square_qam", "CP-OFDM", true, true, ...
                    "TS_38_214_table_5_1_3_1_2_reference_baseline");
            end
        end

        function entries = highOrderCandidates()
            ids = ["H0" "H1" "H2" "H3"];
            rates = [805.5 853 900.5 948];
            entries = sixgr.studies.ran1ai1032.MCSEntry.empty(0,1);
            for k = 1:numel(ids)
                entries(k,1) = sixgr.studies.ran1ai1032.MCSEntry( ...
                    ids(k), 10, rates(k), ...
                    "capability_1024qam_and_fwa_applicable", ...
                    "square_qam", "CP-OFDM", true, true, ...
                    "6GR_RAN1_AI_10_3_2_candidate");
            end
        end

        function T = optionA()
            entries = [sixgr.studies.ran1ai1032.MCSCatalog.baseline256(); ...
                sixgr.studies.ran1ai1032.MCSCatalog.highOrderCandidates()];
            T = sixgr.studies.ran1ai1032.MCSEntry.toTable(entries);
            T.representation = repmat("A_joint_5bit_invariant", height(T), 1);
            T.profile = repmat("invariant", height(T), 1);
            T.indication_index = (0:height(T)-1).';
            T.indication_width_bits = repmat(5, height(T), 1);
            sixgr.studies.ran1ai1032.MCSCatalog.assertInvariantMap(T, 5);
        end

        function T = optionB()
            baseline = sixgr.studies.ran1ai1032.MCSEntry.toTable( ...
                sixgr.studies.ran1ai1032.MCSCatalog.baseline256());
            baseline.representation = repmat("B_profile_switching", height(baseline), 1);
            baseline.profile = repmat("baseline", height(baseline), 1);
            baseline.indication_index = (0:height(baseline)-1).';
            baseline.indication_width_bits = repmat(5, height(baseline), 1);

            fwa = sixgr.studies.ran1ai1032.MCSCatalog.optionA();
            fwa.representation(:) = "B_profile_switching";
            fwa.profile(:) = "fwa_high_order";
            T = [baseline; fwa];
            if any(groupsummary(T, "profile", "max", "indication_index").max_indication_index > 31)
                error("sixgr:ran1ai1032:ProfileIndexOverflow", ...
                    "Every profile-switching table must fit its declared 5-bit indication.");
            end
        end

        function T = optionC()
            % Preserve every distinct physical pair in the two reference
            % lower-order tables, then append H0-H3.  A stable flat entry
            % number is assigned only after the physical pairs are deduplicated.
            q1 = [2 2 2 2 2 2 2 2 2 2 4 4 4 4 4 4 4 6 6 6 6 6 6 6 6 6 6 6 6];
            r1 = [120 157 193 251 308 379 449 526 602 679 340 378 434 490 553 616 658 ...
                438 466 517 567 616 666 719 772 822 873 910 948];
            base2 = sixgr.studies.ran1ai1032.MCSEntry.toTable( ...
                sixgr.studies.ran1ai1032.MCSCatalog.baseline256());
            pairs = [q1(:) r1(:); base2.Qm base2.target_code_rate_x1024];
            [pairs, ia] = unique(pairs, "rows", "stable"); %#ok<ASGLU>
            entries = sixgr.studies.ran1ai1032.MCSEntry.empty(0,1);
            for k = 1:size(pairs,1)
                entries(k,1) = sixgr.studies.ran1ai1032.MCSEntry( ...
                    "W" + compose("%02d", k-1), pairs(k,1), pairs(k,2), ...
                    "baseline", "square_qam", "CP-OFDM", true, true, ...
                    "TS_38_214_reference_union");
            end
            entries = [entries; sixgr.studies.ran1ai1032.MCSCatalog.highOrderCandidates()];
            T = sixgr.studies.ran1ai1032.MCSEntry.toTable(entries);
            T.representation = repmat("C_larger_flat_table", height(T), 1);
            T.profile = repmat("flat", height(T), 1);
            T.indication_index = (0:height(T)-1).';
            width = ceil(log2(height(T)));
            T.indication_width_bits = repmat(width, height(T), 1);
            sixgr.studies.ran1ai1032.MCSCatalog.assertInvariantMap(T, width);
        end

        function out = optionD()
            flat = sixgr.studies.ran1ai1032.MCSCatalog.optionC();
            qValues = unique(flat.Qm, "stable");
            rValues = unique(flat.target_code_rate_x1024, "stable");
            valid = flat(:, ["entry_id","Qm","target_code_rate_x1024", ...
                "nominal_spectral_efficiency","eligibility","new_TB_allowed", ...
                "retransmission_allowed"]);
            valid.qm_code = arrayfun(@(x) find(qValues == x, 1) - 1, valid.Qm);
            valid.rate_code = arrayfun(@(x) find(rValues == x, 1) - 1, ...
                valid.target_code_rate_x1024);
            out = struct( ...
                "Representation", "D_separate_modulation_and_rate", ...
                "QmValues", qValues(:).', ...
                "RateValuesX1024", rValues(:).', ...
                "QmFieldBits", ceil(log2(numel(qValues))), ...
                "RateFieldBits", ceil(log2(numel(rValues))), ...
                "TotalIndicationBits", ceil(log2(numel(qValues))) + ceil(log2(numel(rValues))), ...
                "ValidPairs", valid);
        end

        function T = equalSpectralEfficiencyPairs()
            pair = ["E1";"E1";"E2";"E2";"E3";"E3"];
            member = ["A";"B";"A";"B";"A";"B"];
            qm = [4;6;6;8;8;10];
            rate = [658;1316/3;873;654.75;948;758.4];
            eta = qm .* rate / 1024;
            T = table(pair, member, qm, rate, eta, ...
                repmat("same_allocation_same_TBS_same_rank_same_total_UE_power",6,1), ...
                'VariableNames', {'pair_id','member','Qm', ...
                'target_code_rate_x1024','nominal_spectral_efficiency', ...
                'comparison_contract'});
            for p = ["E1" "E2" "E3"]
                rows = T.pair_id == p;
                if range(T.nominal_spectral_efficiency(rows)) > 1e-12
                    error("sixgr:ran1ai1032:EqualSEContract", ...
                        "Pair %s does not have equal nominal spectral efficiency.", p);
                end
            end
        end

        function assertInvariantMap(T, width)
            required = ["entry_id","Qm","target_code_rate_x1024", ...
                "indication_index","indication_width_bits"];
            if ~all(ismember(required, string(T.Properties.VariableNames))) || ...
                    numel(unique(T.entry_id)) ~= height(T) || ...
                    numel(unique(T.indication_index)) ~= height(T) || ...
                    any(T.indication_index < 0) || ...
                    any(T.indication_index >= 2^width) || ...
                    any(T.indication_width_bits ~= width)
                error("sixgr:ran1ai1032:InvalidInvariantMap", ...
                    "MCS map is not a unique invariant mapping within its indication width.");
            end
        end
    end
end
