function rx = PDCCHStudyReceiver(rxGrid4D, ctrlCfg, regTable, reTable, cceMap, truth)
%PDCCHStudyReceiver Wrapper for the 6GR blind-monitoring receiver chain.

if ~logical(ctrlCfg.BlindDetectionEnabled)
    error("sixgr:ctrl:PDCCHStudyReceiver:BlindDetectionDisabled", ...
        "The study framework expects BlindDetectionEnabled=true.");
end

rx = sixgr.ctrl.PDCCHBlindDetector(rxGrid4D, ctrlCfg, ctrlCfg.SearchSpaces, regTable, reTable, cceMap, truth);
end
