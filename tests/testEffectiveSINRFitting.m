function ok=testEffectiveSINRFitting()
% Deterministic numerical-contract fixture, NOT physical calibration data.
q=struct('minimum_conditional_trials',100,'confidence_level',0.95, ...
    'maximum_wilson_half_width',0.11,'maximum_validation_absolute_bler_error',0.03, ...
    'beta_linear_bounds',[0.05 20],'beta_log_grid_count',121,'minimum_beta_objective_contrast',1e-6);
reference=struct('SINRAxes_dB',{{[-20;-5;5;20]}},'TrialCount',10000*ones(4,1), ...
    'ErrorCount',[9900;9000;1000;100],'ConfigurationSHA256',"numerical_contract_only");
histories=cell(400,1); errors=false(400,1); groups=strings(400,1);
patterns={[.01;1],[.1;10],[1;100],[.3;3]};
for k=1:4
    g=patterns{k}; effective=-2*log(mean(exp(-g/2)));
    p=interp1(reference.SINRAxes_dB{1},reference.ErrorCount./reference.TrialCount,10*log10(effective));
    ix=(k-1)*100+(1:100);
    for n=ix, histories{n}={g}; end
    errors(ix(1:round(100*p)))=true; groups(ix)="group_"+k;
end
fit=table("fit_"+(1:400)',(1:400)',(401:800)',errors,histories,groups, ...
    repmat(reference.ConfigurationSHA256,400,1), ...
    'VariableNames',{'TrialID','NoiseSeed','ChannelSeed','CRCError','SINRHistory','GroupID','ConfigurationSHA256'});
validation=fit; validation.TrialID="heldout_"+(1:400)';
validation.NoiseSeed=validation.NoiseSeed+1000; validation.ChannelSeed=validation.ChannelSeed+1000;
r=sixgr.calibration.fitEffectiveSINR(reference,fit,validation,q);
assert(r.FittingPassed && ~r.PrimaryStudyAccepted && abs(log(r.BetaLinear/2))<0.15);
bad=validation; bad.CRCError(:)=true;
b=sixgr.calibration.fitEffectiveSINR(reference,fit,bad,q);
assert(b.BetaLinear==r.BetaLinear && ~b.FittingPassed,'Held-out CRCs must not tune beta.');
bad=validation; bad.NoiseSeed(1)=fit.NoiseSeed(1);
reject(@()sixgr.calibration.fitEffectiveSINR(reference,fit,bad,q),'sixgr:calibration:ValidationLeakage');
bad=validation; bad.ConfigurationSHA256(:)="other_direction_or_rank";
reject(@()sixgr.calibration.fitEffectiveSINR(reference,fit,bad,q),'sixgr:calibration:FittingKey');
flat=fit; held=validation;
for k=1:400, flat.SINRHistory{k}={ones(4,1)}; held.SINRHistory{k}={ones(4,1)}; end
reject(@()sixgr.calibration.fitEffectiveSINR(reference,flat,held,q),'sixgr:calibration:UnidentifiableBeta');
bad=reference; bad.TrialCount(:)=1; bad.ErrorCount(:)=0;
reject(@()sixgr.calibration.fitEffectiveSINR(bad,fit,validation,q),'sixgr:calibration:ReferencePopulation');
% A two-attempt numerical contract exercises Cartesian interpolation and
% the same nested-cell shape assembled from retained physical episodes.
reference2=reference;
reference2.SINRAxes_dB={reference.SINRAxes_dB{1},reference.SINRAxes_dB{1}};
reference2.TrialCount=10000*ones(4,4);
reference2.ErrorCount=(reference.ErrorCount+reference.ErrorCount.')/2;
fit2=fit; held2=validation;
for k=1:4
    history={patterns{k},patterns{mod(k,4)+1}};
    effective=zeros(1,2);
    for a=1:2, effective(a)=10*log10(-2*log(mean(exp(-history{a}/2)))); end
    probability=interpn(reference2.SINRAxes_dB{:},reference2.ErrorCount./reference2.TrialCount, ...
        effective(1),effective(2),'linear');
    ix=(k-1)*100+(1:100); fit2.CRCError(ix)=false;
    fit2.CRCError(ix(1:round(100*probability)))=true;
    record=struct('SINRHistory',{{history}},'GroupID',"contract");
    row=struct2table(record);
    for n=ix, fit2.SINRHistory{n}=row.SINRHistory{1}; end
end
held2.SINRHistory=fit2.SINRHistory; held2.CRCError=fit2.CRCError;
r2=sixgr.calibration.fitEffectiveSINR(reference2,fit2,held2,q);
assert(r2.FittingPassed && abs(log(r2.BetaLinear/2))<0.15);
outside=fit; outside.SINRHistory{1}={1e8*ones(4,1)};
reject(@()sixgr.calibration.fitEffectiveSINR(reference,outside,validation,q), ...
    'sixgr:calibration:ReferenceCoverage');
unsupported=reference; unsupported.SupportedMask=[true;false;true;true];
reject(@()sixgr.calibration.fitEffectiveSINR(unsupported,fit,validation,q), ...
    'sixgr:calibration:ReferenceCoverage');
ok=true; fprintf('EFFECTIVE_SINR_FITTING_PASS numerical_contract_only=1\n');
end
function reject(fn,id)
try, fn(); catch ME, assert(string(ME.identifier)==id,'%s: %s',ME.identifier,ME.message); return; end
error('test:ExpectedFailure','Expected %s',id);
end
