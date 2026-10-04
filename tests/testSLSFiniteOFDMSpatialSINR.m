function ok=testSLSFiniteOFDMSpatialSINR()
% Algebraic fixtures, not physical calibration or measured performance.
G=cat(3,[1 .3i;.2 1]/sqrt(2),[.8 .1;.4i .6],zeros(2));
leak=cat(3,[.1 .02i;-.02i .2],.05*eye(2),zeros(2));
total=leak;
for k=1:3, total(:,:,k)=total(:,:,k)+G(:,:,k)*G(:,:,k)'; end
o=struct('SameResourceEffectiveChannel',G,'SameResourceChannelIncludesTransmitPower',true, ...
    'OtherResourceCovariance',leak,'Covariance',total,'Coordinates0Based',[0 0;1 0;2 0], ...
    'SourceClassification',"modeled_finite_filter_independent_symbol_covariance", ...
    'BoundaryPolicy',"explicit_zero_outside_declared_observation_window", ...
    'WithinWindowISIICIIncluded',true,'FullNetworkInterferenceQualified',false, ...
    'CommonControlInterferenceQualified',false,'StatisticalBLERQualified',false, ...
    'PrimaryStudyAccepted',false);
noise=.01*eye(2);
out=sixgr.system.abstraction.evaluateFiniteOFDMSpatialSINR(o,noise);
reference=zeros(3,2);
for k=1:3
    errorCov=(eye(2)+G(:,:,k)'*((noise+leak(:,:,k))\G(:,:,k)))\eye(2);
    reference(k,:)=(1./real(diag(errorCov))-1).';
end
assert(max(abs(out.SINRLinear-reference),[],'all')<1e-11);
assert(all(out.SINRLinear(3,:)==0) && all(out.SINR_dB(3,:)==-Inf) && ...
    ~out.WaveformBacked && ~out.PrimaryStudyAccepted);
bad=o; bad.OtherResourceCovariance=bad.Covariance;
reject(@()sixgr.system.abstraction.evaluateFiniteOFDMSpatialSINR(bad,noise), ...
    'sixgr:abstraction:FiniteSpatialPartition');
bad=o; bad.SameResourceChannelIncludesTransmitPower=false;
reject(@()sixgr.system.abstraction.evaluateFiniteOFDMSpatialSINR(bad,noise), ...
    'sixgr:abstraction:FiniteSpatialEvidence');
bad=o; bad.FullNetworkInterferenceQualified=true;
reject(@()sixgr.system.abstraction.evaluateFiniteOFDMSpatialSINR(bad,noise), ...
    'sixgr:abstraction:FiniteSpatialEvidence');
reject(@()sixgr.system.abstraction.evaluateFiniteOFDMSpatialSINR(o,-noise), ...
    'sixgr:abstraction:Covariance');
% The factored-channel API and direct effective-channel API must preserve
% every numerical field and label of the existing production calculation.
H=[1 .4i;.2 1]; F=eye(2)/sqrt(2); p=3;
for receiver=["lmmse","zf"]
    factored=sixgr.system.abstraction.evaluateSpatialSINR(H,F,p,noise,receiver);
    direct=sixgr.system.abstraction.evaluateEffectiveSpatialSINR(H*F*sqrt(p),noise,receiver);
    direct.Source=factored.Source;
    assert(isequaln(factored,direct),'The existing spatial receiver API must remain numerically identical.');
end
fprintf('SLS_FINITE_OFDM_SPATIAL_SINR_PASS independent_error_covariance=1 double_count_rejected=1 qualification=0\n');
ok=true;
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
