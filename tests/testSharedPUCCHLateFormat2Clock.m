function ok=testSharedPUCCHLateFormat2Clock()
% Late HARQ bits force the resource resolver to encode Format 2, not Format 0.
ok=testSharedPUCCHFeedbackClock(2);
end
