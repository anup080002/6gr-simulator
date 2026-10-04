function ok=testSLSDeferredReceiveCompletion()
% Native finite filter determines availability; only the BLER package is a
% labeled numerical fixture. Never call this statistical PHY qualification.
ok=testSLSFinitePredictorBinding('Deferred',true);
fprintf('SLS_DEFERRED_RECEIVE_COMPLETION_PASS immutable_grant=1 no_early_bler_draw=1 separate_clocks=1\n');
end
