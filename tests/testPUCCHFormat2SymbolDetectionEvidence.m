function ok=testPUCCHFormat2SymbolDetectionEvidence()
% Diagnostic retention regression, not qualification of the receiver policy.
setup6GRSimToolkit('Verbose',false);
logsRoot=fullfile(pwd,'logs');
if ~isfolder(logsRoot), mkdir(logsRoot); end
scenarios=["lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml", ...
    "lls_tdd_5mhz_rank2_shared_awgn_20db.yaml"];
for name=scenarios
    outputRoot=tempname(logsRoot);
    rows=diagnosePUCCHFormat2SymbolDetection( ...
        fullfile('simulator','configs','scenarios',name),outputRoot);
    restored=readtable(fullfile(outputRoot,'symbol_detection_diagnostic.csv'),'TextType','string');
    scope=sixgr.util.jsonRead(fullfile(outputRoot,'scope.json'));
    assert(height(rows)==3 && height(restored)==3 && scope.AllObservationsWritten);
    assert(isequal(rows.Case,["coded_signal_present";"noise_only";"unrelated_qpsk_interference"]));
    assert(isequal(rows.ObservationOutcome,restored.ObservationOutcome));
    assert(all(isnan(rows.PayloadMatch(~rows.SignalPresent))) && ...
        all(isnan(rows.BitErrors(~rows.SignalPresent))));
    assert(~any(rows.CRCApplicable) && ~scope.ThresholdTuned && ...
        ~scope.QualificationPassed && ~scope.CandidatePolicyInstalledInReceiver);
    assert(isequal(rows.WhiteNoiseNullApplicable,[false;true;false]));
    assert(rows.ReceiverAccepted(1)==(rows.DetectionOutcome(1)=="detected" && ...
        rows.DecodedBitCount(1)==rows.PayloadBits(1)));
    if contains(name,'m10db')
        assert(rows.ObservationOutcome(1)=="signal_payload_failed", ...
            'test:MissingFailedPayloadCoverage','Frozen low-SNR case must retain its failed payload.');
    else
        assert(rows.ObservationOutcome(1)=="signal_payload_recovered", ...
            'test:MissingGoodPayloadCoverage','The 20 dB coded-symbol observation must recover the payload.');
    end
    fprintf('PUCCH_SYMBOL_EVIDENCE_RETAINED scenario=%s csv=%s\n', ...
        name,fullfile(outputRoot,'symbol_detection_diagnostic.csv'));
end
ok=true; disp('PUCCH_SYMBOL_EVIDENCE_RETENTION_PASS physical_qualification=0');
end
