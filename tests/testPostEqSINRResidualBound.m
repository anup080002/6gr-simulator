function ok=testPostEqSINRResidualBound()
% Numerical contract tests; NOT PHY/statistical qualification episodes.
raw=[30 10;30 10];
info=struct('RawSINR_dB',20,'RawPerLayerSINR_dB',[30 10], ...
    'PerLayerSINR_dB',[30 10],'Source',"executed_equalizer", ...
    'ValueStatus',"OK",'NAReason',"");
residual=struct('Available',true,'SINR_dB',20, ...
    'PerLayerSINR_dB',[10 30],'BoundKind',"dmrs_residual");
% Equal wideband means must not hide the bad first layer.
[wb,re,first]=sixgr.phy.rx.applyPostEqSINRResidualBound(20,raw,info,residual);
assert(wb==10 && isequal(re,[10 10;10 10]) && first.DMRSResidualBoundApplied);
assert(first.RawEqualizerSINR_dB==20 && isequal(first.RawPerLayerSINR_dB,[30 10]));
residual.PerLayerSINR_dB=[5 15]; residual.SINR_dB=10;
residual.BoundKind="decision_residual";
[wb,re,second]=sixgr.phy.rx.applyPostEqSINRResidualBound(wb,re,first,residual);
assert(wb==7.5 && isequal(second.PerLayerSINR_dB,[5 10]));
assert(second.DMRSResidualBoundApplied && second.DecisionResidualBoundApplied);
assert(second.RawEqualizerSINR_dB==20 && second.UnboundedSource=="executed_equalizer");
assert(isequal(second.RawPerLayerSINR_dB,info.RawPerLayerSINR_dB));
assert(wb==mean(re,'all') && isequal(second.PerLayerSINR_dB,mean(re,1)));
% Variable REs retain one denominator convention, not a mismatched scalar.
raw=[0 30;20 10]; residual.PerLayerSINR_dB=[8 25];
[wb,re,third]=sixgr.phy.rx.applyPostEqSINRResidualBound(15,raw,info,residual);
assert(isequal(re,[0 25;8 10]) && wb==10.75);
assert(~isfield(third,'DMRSResidualBoundApplied') && third.DecisionResidualBoundApplied);
residual.Available=false;
[w2,r2,i2]=sixgr.phy.rx.applyPostEqSINRResidualBound(15,raw,info,residual);
assert(w2==15 && isequal(r2,raw) && isequal(i2,info));
residual.Available=true; residual.PerLayerSINR_dB=8;
try
    sixgr.phy.rx.applyPostEqSINRResidualBound(15,raw,info,residual);
    error('test:ExpectedLayerMismatch','Aggregate residual must not be copied to unmeasured layers.');
catch err
    assert(strcmp(err.identifier,'sixgr:phy:rx:ResidualSINRLayerMismatch'));
end
fprintf('POST_EQ_RESIDUAL_BOUND_PASS numerical layers, sequential bounds, immutable raw, unavailable/malformed.\n');
ok=true;
end
