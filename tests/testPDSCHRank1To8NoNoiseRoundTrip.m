function ok = testPDSCHRank1To8NoNoiseRoundTrip()
%TESTPDSCHRANK1TO8NONOISEROUNDTRIP Required named rank coverage gate.

ok = testPDSCHReceiverNoNoiseExact();
assert(ok, "The canonical production rank-1-to-8 round trip failed.");
end
