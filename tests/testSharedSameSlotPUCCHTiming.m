function ok=testSharedSameSlotPUCCHTiming()
% Actual SRS and HARQ PUCCH share a slot; their samples exist before decode.
root=fullfile('results','lls','same_slot_pucch_timing', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
ok=testSharedPUCCHFeedbackClock(false,'TDD', ...
    'simulator/configs/scenarios/lls_pucch_same_slot_srs_fixture.yaml',root,'',true,true);
end
