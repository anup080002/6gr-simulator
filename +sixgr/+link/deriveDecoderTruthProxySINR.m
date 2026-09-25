function [sinr_dB, meta] = deriveDecoderTruthProxySINR(inputMetrics)
%DERIVEDECODERTRUTHPROXYSINR Quarantine EVM-derived SINR from primary truth.
% EVM-derived 10log10(1/EVM^2) is a useful diagnostic, but it is not a
% decoder-truth SINR measurement and must not populate primary truth rows.
% Use the explicit EVMProxySINR_* diagnostic columns for that value.

sinr_dB = NaN;
meta = struct( ...
    "Source", "evm_proxy_quarantined_not_decoder_truth", ...
    "ValueRole", "unavailable", ...
    "ValueStatus", "unavailable", ...
    "DiagnosticEVMProxySINR_dB", NaN, ...
    "DiagnosticValueRole", "unavailable", ...
    "DiagnosticValueStatus", "unavailable", ...
    "Definition", "10log10(1/EVM_rms^2)_from_equalized_symbols_vs_transmitted_reference_symbols", ...
    "NAReason", "decoder_truth_sinr_requires_receiver_or_decoder_evidence_not_evm_proxy");

evm_rms = double(sixgr.util.structGet(inputMetrics, "EVM_rms", NaN));
if ~(isscalar(evm_rms) && isreal(evm_rms) && isfinite(evm_rms) && evm_rms >= 0)
    meta.NAReason = "evm_unavailable";
    return;
end

% Log-domain evaluation preserves tiny finite EVM without squaring underflow.
% Zero measured error gives +Inf diagnostic ratio, not infinite receiver SINR.
meta.DiagnosticEVMProxySINR_dB = -20 * log10(evm_rms);
meta.DiagnosticValueRole = "diagnostic_evm_proxy_not_decoder_truth";
meta.DiagnosticValueStatus = "diagnostic_available_primary_unavailable";
if evm_rms==0
    meta.DiagnosticValueStatus="zero_error_unbounded_diagnostic_primary_unavailable";
end
end
