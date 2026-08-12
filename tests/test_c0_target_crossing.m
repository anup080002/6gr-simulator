function test_c0_target_crossing()
%TEST_C0_TARGET_CROSSING Zero-error endpoints still bracket real targets.
points=table([-12;-8],[0.75;0], ...
    'VariableNames',{'SNRDB','PBCHBLER'});
r=sixgr.phy.ia.c0.metrics.findTargetCrossing( ...
    points,"PBCHBLER",0.1);
assert(r.Bracketed);
assert(r.LowerSNRDB==-12 && r.UpperSNRDB==-8);
assert(abs(r.CrossingSNRDB-(-8.53333333333333))<1e-10);
assert(r.Interpolation=="linear_in_probability_zero_endpoint");
fprintf('test_c0_target_crossing: PASS\n');
end
