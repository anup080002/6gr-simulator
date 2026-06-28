function T = releaseBaselineSpecTable()
%RELEASEBASELINESPECTABLE Numerical release baseline metadata.

matlabRelease = string(version("-release"));
tbx = ver("5G Toolbox");
if isempty(tbx)
    toolboxVersion = "nr_api_available_version_not_reported";
else
    toolboxVersion = string(tbx(1).Version);
end

rows = [
    row("pure_math", "core", "3GPP NR Rel-17, TS 38.214 v17.7.0", "direct_linear_algebra_mmse_irc", "1e-10")
    row("grid_bit", "phy", "3GPP NR Rel-17, TS 38.211 v17.7.0 / TS 38.212 v17.7.0", "nrPDSCHIndices_nrPUSCHIndices_nrRateMatchLDPC", "bit_exact")
    row("waveform_loopback", "phy", "3GPP NR Rel-17, TS 38.211 v17.7.0", "nrOFDMModulate_nrOFDMDemodulate", "1e-11")
    row("awgn_channel", "channel", "3GPP NR Rel-17, TS 38.901 v17.1.0", "closed_form_awgn_power_and_toa_doppler", "0.05_dB_or_exact_formula")
    row("harq_soft_buffer", "mac", "3GPP NR Rel-17, TS 38.212 v17.7.0", "position_mapped_mother_code_llr_arithmetic", "exact_position_sum")
    row("interference_superposition", "link", "3GPP NR Rel-17, TR 38.901 v17.1.0", "sample_exact_shared_slot_contribution_sum", "1e-15")
    row("random_access", "mac", "3GPP NR Rel-17, TS 38.321 v17.7.0 / TS 38.211 v17.7.0", "four_step_ra_awgn_msg1_msg4_anchor", "state_machine_success")
    row("rank2_mimo", "link", "3GPP NR Rel-17, TS 38.214 v17.7.0", "fixed_rank2_no_collapse_anchor", "rank_exact")
    row("campaign_convergence", "link", "3GPP NR Rel-17, TS 38.214 v17.7.0", "fixed_link_monte_carlo_seed_budget_contract", "seed_exact")
    row("kpi_reproducibility", "core", "3GPP NR Rel-17, TS 38.321 v17.7.0", "causal_tb_delivery_ledger_reconstruction", "1e-12")
    ];
T = struct2table(rows);

    function r = row(anchorID, layer, specVersion, referencePath, tolerance)
        r = struct( ...
            "AnchorID", string(anchorID), ...
            "Layer", string(layer), ...
            "SpecVersion", string(specVersion), ...
            "ReferencePath", string(referencePath), ...
            "MATLABRelease", matlabRelease, ...
            "FiveGToolboxVersion", toolboxVersion, ...
            "NumericTolerance", string(tolerance));
    end
end
