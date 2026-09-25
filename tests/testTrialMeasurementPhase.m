function ok=testTrialMeasurementPhase()
% Export fixture: physical failures do not become implicit AMC warm-up.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
T=table((1:3).',true(3,1),true(3,1),false(3,1), ...
    zeros(3,1),[-10;-9;-8],repmat("OK_DMRS_RESIDUAL_BOUNDED",3,1), ...
    true(3,1),false(3,1),repmat("DL",3,1), ...
    'VariableNames',{'Slot','AdaptiveMode','LinkAdaptationScheduled', ...
    'LinkAdaptationApplied','CRCPass','PostEqSINR_dB','PostEqSINRValueStatus', ...
    'FinalizedFlag','FallbackFlag','Direction'});
cfg=struct('run',struct('warmupSlots',0));
out=sixgr.analytics.applyTrialMeasurementPhase(T,cfg);
assert(~any(out.IsWarmupFrame) && all(out.LinkAdaptationBootstrap));
assert(isequaln(out(:,T.Properties.VariableNames),T), ...
    'Measurement phase must not alter physical outcomes or measurements.');
cfg.run.warmupSlots=2;
warm=sixgr.analytics.applyTrialMeasurementPhase(T,cfg);
assert(isequal(warm.IsWarmupFrame,[true;true;false]));
repeated=[T;T]; % Two operating points use the same slot clock origin.
repeated=sixgr.analytics.applyTrialMeasurementPhase(repeated,cfg);
assert(isequal(repeated.IsWarmupFrame,repmat([true;true;false],2,1)));
provided=sixgr.analytics.applyTrialMeasurementPhase(warm,struct());
assert(isequal(provided.IsWarmupFrame,warm.IsWarmupFrame));
fixed=T; fixed.AdaptiveMode(:)=false;
fixed=sixgr.analytics.applyTrialMeasurementPhase(fixed,struct('run',struct('warmupSlots',0)));
assert(~any(fixed.LinkAdaptationBootstrap) && ~any(fixed.IsWarmupFrame));
% Verify the actual curve generator retains all failed bootstrap decodes.
out.TBSize_bits=repmat(1000,3,1); out.OfferedBits=out.TBSize_bits;
out.BitsCompared=out.TBSize_bits; out.BitErrors=repmat(100,3,1);
out.GoodBits=zeros(3,1); out.Throughput_Mbps=zeros(3,1);
out.PropagationDistance_m=repmat(100,3,1);
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
curves=sixgr.analytics.generateMeasuredSINRCurves(folder,'bootstrap_measurements', ...
    'TrialData',struct('dl',out,'ul',table()), ...
    'ScenarioConfig',struct('global_radio_scope',struct('channel_bandwidth_hz',5e6)), ...
    'UpdateAnchorKPIs',false);
assert(curves.Tables.Summary.N_Trials==3 && curves.Tables.Summary.BLER_overall==1);
assert(sum(curves.Tables.DLBlerCurve.TrialCount)==3 && ...
    sum(curves.Tables.DLBlerCurve.FailureCount)==3);
assert(height(readtable(curves.Paths.DLBlerCurve))>0);
fprintf('TRIAL_MEASUREMENT_PHASE_PASS bootstrap_failures_retained=3 configured_warmup_preserved=1\n');
ok=true;
end
