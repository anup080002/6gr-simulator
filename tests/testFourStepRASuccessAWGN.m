function ok = testFourStepRASuccessAWGN()
res = raStrictAnchorSuccessResult();
assert(logical(res.RACompleted), "Four-step RA must complete in AWGN anchor.");
assert(logical(res.StrictOk), "StrictOk must be true only for full MSG1-MSG4 success.");
ok = true;
end
