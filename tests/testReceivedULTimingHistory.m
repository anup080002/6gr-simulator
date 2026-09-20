function ok=testReceivedULTimingHistory()
% Actual two-pilot TDD component and retained earlier-PUCCH clock selection.
% Declared access inputs remain component inputs, not a full access pass.
setup6GRSimToolkit('Verbose',false);
previous=rng; cleanup=onCleanup(@()rng(previous)); %#ok<NASGU>
rng(73,'twister');
root=fullfile('results','lls','received_ul_timing_history', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
ok=testSharedPUCCHFeedbackClock(false,'TDD','',root,'',true);
end
