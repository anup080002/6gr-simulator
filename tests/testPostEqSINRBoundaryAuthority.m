function ok = testPostEqSINRBoundaryAuthority()
% Preserve actual RE/layer identity and mathematical noise boundaries.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
H=reshape(diag([1 2]),1,2,2);
[~,~,equalizer]=sixgr.phy.rx.equalizeMMSE([1 1],H,.1);
[wideband,perRE,info]=sixgr.phy.rx.computePostEqSINR(H,.1, ...
    'EqualizerResult',equalizer.EqualizerResult);
expected=10*log10([10 40]);
assert(isequal(size(perRE),[1 2]) && info.NRE==1 && info.NumLayers==2, ...
    'One RE with two layers must not be relabelled as two REs with one layer.');
assert(max(abs(perRE-expected))<1e-11 && abs(wideband-mean(expected))<1e-11);
assert(isequal(size(info.DemapperReliability),[1 2]));
[~,perRE,info]=sixgr.phy.rx.computePostEqSINR(H,.1, ...
    'EqualizerResult',equalizer.EqualizerResult,'Layers',1);
assert(isequal(size(perRE),[1 1]) && info.NumLayers==1);
assert(isequal(size(info.DemapperReliability),[1 1]));

% A deep but finite null is not a machine-epsilon physical SINR floor.
[wideband,perRE,info]=sixgr.phy.rx.computePostEqSINR(ones(2,1)*1e-12,1);
assert(abs(wideband+240)<1e-10 && all(abs(perRE+240)<1e-10));
assert(string(info.ValueStatus)=="OK" && info.ValidSINRSampleCount==2);

% Exact zero noise gives an infinite model SINR, not invented noise. A
% scheduler may only get a finite cap if that cap was explicitly supplied.
[wideband,perRE,info]=sixgr.phy.rx.computePostEqSINR(ones(2,1),0);
assert(isinf(wideband) && wideband>0 && all(isinf(perRE)));
assert(isinf(info.RawSINR_dB) && string(info.ValueStatus)=="unavailable");
[wideband,perRE,info]=sixgr.phy.rx.computePostEqSINR(ones(2,1),0,'MaxTrustedSINR_dB',45);
assert(wideband==45 && all(perRE==45) && isinf(info.RawSINR_dB));
assert(string(info.ValueStatus)=="OK_dynamic_range_limited");

[wideband,perRE,info]=sixgr.phy.rx.computePostEqSINR(zeros(2,1),1);
assert(isinf(wideband) && wideband<0 && all(isinf(perRE) & perRE<0));
assert(all(info.PostEqSINRLinear==0) && string(info.ValueStatus)=="unavailable");

% A geometric mean containing both zero and infinity is undefined. Keep
% its individual observations; never discard the difficult values to pass.
result=equalizer.EqualizerResult;
result.PostEqSINRLinear=[0;Inf]; result.DemapperReliability=[0;1];
result.NRE=2; result.NumRxAnt=1; result.NumTxPorts=1;
[wideband,perRE,info]=sixgr.phy.rx.computePostEqSINR([],0,'EqualizerResult',result);
assert(isnan(wideband) && isequal(perRE,[-Inf;Inf]));
assert(string(info.NAReason)=="undefined_post_equalization_geometric_reduction");
assert(info.ValidSINRSampleCount==2 && info.InvalidSINRSampleCount==0);
for invalid={NaN,Inf,-1,1+1i}
    [value,~,info]=sixgr.phy.rx.computePostEqSINR(ones(2,1),invalid{1});
    assert(isnan(value) && string(info.ValueStatus)=="unavailable");
end
fprintf('POST_EQ_SINR_BOUNDARY_AUTHORITY_PASS single_RE_layer_identity=1 no_physical_eps_floor=1\n');
ok=true;
end
