function test_energy_normalization()
%TEST_ENERGY_NORMALIZATION Verify all declared normalization policies.
grid=complex(zeros(20,4)); grid(1:20)=1;
[~,a]=sixgr.phy.ia.c0.waveform.normalizeEnergy(grid,20,"equal_epre");
assert(a.Passed&&abs(a.ClosureDB)<0.01);
[g,b]=sixgr.phy.ia.c0.waveform.normalizeEnergy( ...
    grid,40,"equal_total_energy");
assert(b.Passed&&abs(sum(abs(g(:)).^2)-40)<1e-10);
[~,c]=sixgr.phy.ia.c0.waveform.normalizeEnergy( ...
    grid,20,"equal_tf_resource");
assert(c.Passed);
fprintf('test_energy_normalization: PASS\n');
end
