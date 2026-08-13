function ok=testUL10523Deterministic()
%TESTUL10523DETERMINISTIC Exact analytical identities and source coverage.
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
out=sixgr.tdoc.ul10523.DeterministicSuite.run();
assert(height(out.Checks)==6 && all(out.Checks.Pass));
for idx=1:22
    key=sprintf("TFIG_%02d",idx);
    assert(isfield(out.Sources,key) && istable(out.Sources.(key)) && height(out.Sources.(key))>0, ...
        "Missing nonempty source for %s.",key);
end
gain=out.Sources.TFIG_05.RelativeArrayGain_dB;
assert(all(diff(gain)<=1e-12) && abs(gain(1))<1e-12);
assert(isequal(out.Sources.TFIG_09.IndicationBits,10+4*out.Sources.TFIG_09.RefinedGroupCountK));
assert(isequal(out.Sources.TFIG_19.DirectDetectionHypotheses, ...
    2.^out.Sources.TFIG_19.UCIPayloadBits));
ok=true; fprintf("UL10523Deterministic: 6 invariants and 22 persisted figure sources PASS.\n");
end
