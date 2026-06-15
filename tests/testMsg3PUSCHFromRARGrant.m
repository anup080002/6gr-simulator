function ok = testMsg3PUSCHFromRARGrant()
res = raStrictAnchorSuccessResult();
assert(logical(res.Msg3PUSCHCrcPass), "gNB must decode MSG3 PUSCH/UL-SCH.");
assert(double(res.Msg3PUSCHPRBStart) == 0 && double(res.Msg3PUSCHNumPRB) == 24, ...
    "MSG3 allocation must come from the decoded RAR UL grant.");
assert(strlength(string(res.Msg3ContentionIdentity)) == 12, "MSG3 contention identity must be recovered.");
ok = true;
end
