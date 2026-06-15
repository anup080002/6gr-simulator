function ok = testRAOracleGuard()
res = raStrictAnchorSuccessResult();
G = res.OracleGuard;
assert(~any(logical(G.Violation)), "Receiver/gNB RA stages must not consume transmitter oracle fields.");
assert(all(~logical(G.WasAccessed)), "Oracle guard must record zero oracle-field access.");
ok = true;
end
