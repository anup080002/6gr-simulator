function ok=testSharedCSIRSTimingSearchWindow()
% Exercise the production producer, actual stream tail, receiver and scorer.
% The 37-sample injected RX delay is assertion evidence only, never an
% estimator input. The pre-front-end branch must acquire independently.
ok=testSharedIndependentCSIRSCompletion(73,37);
end
