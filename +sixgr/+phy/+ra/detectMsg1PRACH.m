function det = detectMsg1PRACH(rxWaveform, cfg, raCfg, occasion)
%DETECTMSG1PRACH Legacy RA adapter; TX comparison follows actual reception.
sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.ra.detectMsg1PRACH","PRACH","UL",struct("Stage","RX"));
prachCfg = sixgr.phy.ra.buildPRACHConfigFromRACHCommon(cfg, raCfg);
det = sixgr.phy.ra.detectConfiguredPRACH(rxWaveform, cfg, prachCfg, occasion);
% Diagnostic only: a mismatch cannot change the receiver's decision, RAPID,
% threshold, timing, frequency, background or full candidate population.
det.RAPIDMatchesTx = logical(det.Detected) && double(det.DetectedPreambleIndex) == double(raCfg.PreambleIndex);
end
