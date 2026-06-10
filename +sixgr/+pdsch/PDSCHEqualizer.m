function eq = PDSCHEqualizer(cfg, rx)
%PDSSCHEqualizer Report the equalizer used by the active truth path.

eq = struct();
eq.EqualizerType = char(string(cfg.ReceiverType));
eq.CSILength = double(numel(sixgr.util.structGet(rx, "CSI", [])));
eq.PostEqSINR_dB = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
eq.PostEqSINRSource = char(string(sixgr.util.structGet(rx, "PostEqSINRSource", "")));
eq.ReceiverHestSINR_dB = double(sixgr.util.structGet(rx, "ReceiverHestSINR_dB", NaN));
eq.ReceiverHestSINRSource = char(string(sixgr.util.structGet(rx, "ReceiverHestSINRSource", "")));
eq.ReceiverSINR_dB = eq.PostEqSINR_dB;
if ~isfinite(eq.ReceiverSINR_dB)
    eq.Source = "post_equalization_sinr_unavailable";
else
    eq.Source = "nrEqualizeMMSE_inside_pdsch_rx_post_equalization_sinr";
end
end
