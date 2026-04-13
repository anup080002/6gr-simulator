function [sinr_dB, meta] = deriveDecoderTruthProxySINR(inputMetrics)
%DERIVEDECODERTRUTHPROXYSINR Derive a decode-side SINR proxy from runtime EVM.
% This is a symbol-domain proxy from equalized-vs-reference mismatch, not a
% decoder-truth SINR measurement.

sinr_dB = NaN;
meta = struct( ...
    "Source", "post_equalization_evm_proxy", ...
    "ValueRole", "derived", ...
    "ValueStatus", "UNAVAILABLE", ...
    "Definition", "10log10(1/EVM_rms^2)_from_equalized_symbols_vs_transmitted_reference_symbols", ...
    "NAReason", "evm_unavailable");

evm_rms = double(sixgr.util.structGet(inputMetrics, "EVM_rms", NaN));
if ~(isfinite(evm_rms) && evm_rms > 0)
    return;
end

sinr_dB = 10 * log10(1 / (evm_rms .^ 2));
meta.ValueStatus = "OK";
meta.NAReason = "";
end
