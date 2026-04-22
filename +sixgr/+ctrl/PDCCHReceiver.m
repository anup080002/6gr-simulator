function rx = PDCCHReceiver(rxGrid4D, ctrlCfg, regTable, reTable, cceMap, truth)
%PDCCHReceiver Wrapper for the 6GR blind-monitoring receiver chain.

if ~logical(ctrlCfg.BlindDetectionEnabled)
    error("sixgr:ctrl:PDCCHReceiver:BlindDetectionDisabled", ...
        "The study framework expects BlindDetectionEnabled=true.");
end

rx = sixgr.ctrl.PDCCHBlindDetector(rxGrid4D, ctrlCfg, ctrlCfg.SearchSpaces, regTable, reTable, cceMap, truth);
end
