function eq = PDSCHEqualizer(cfg, rx)
%PDSSCHEqualizer Report the equalizer used by the active truth path.

eq = struct();
eq.EqualizerType = char(string(cfg.ReceiverType));
eq.CSILength = double(numel(sixgr.util.structGet(rx, "CSI", [])));
eq.ReceiverSINR_dB = double(sixgr.util.structGet(rx, "ReceiverHestSINR_dB", NaN));
eq.Source = "nrEqualizeMMSE_inside_pdsch_rx";
end

