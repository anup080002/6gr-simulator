function ok=testInterLayerEvidence()
setup6GRSimToolkit('Verbose',false);
for H={eye(2),[1 .8;.3 1]}
    matrix=H{1}; h=repmat(reshape(matrix,1,2,2),8,1,1);
    [~,~,eq]=sixgr.phy.rx.equalizeMMSE(ones(8,2),h,.2);
    e=sixgr.phy.rx.interLayerEvidence(eq.EqualizerResult);
    W=(matrix'*matrix+.2*eye(2))\matrix'; A=W*matrix;
    expected=[abs(A(1,2)/A(1,1))^2 abs(A(2,1)/A(2,2))^2];
    assert(max(abs(e.ResidualInterLayerPowerPerLayer-expected))<1e-10);
    assert(abs(e.ResidualInterLayerPowerMean-mean(expected))<1e-10);
end
missing=sixgr.phy.rx.interLayerEvidence(struct());
assert(isnan(missing.ResidualInterLayerPowerMean));
fprintf('INTER_LAYER_EVIDENCE_PASS identity_zero=1 coupled_positive=1 unit_desired_gain=1 no_missing_zero_fallback=1\n');
ok=true;
end
