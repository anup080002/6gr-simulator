function ok=testLLSEndpointEnergyIntervals()
% Accounting fixtures; these are not measured device power or radio trials.
setup6GRSimToolkit('Verbose',false);
T=table(["gNB";"gNB"],[1;1],["run1|point1";"run1|point1"], ...
    [0;.5],[.001;.001],[10;10],[.002;.002],["DL";"DL"],["data";"control"], ...
    'VariableNames',{'Entity','EntityID','ObservationPopulationKey', ...
    'TimestampSim_ms','Duration_s','Power_W','BBProcessingEnergy_J', ...
    'Direction','Domain'});
T.EndpointPowerStateID=repmat("declared_constant_10W_endpoint_state",height(T),1);
a=sixgr.truth.integrateLLSEndpointEnergy(T);
assert(height(a)==3 && abs(sum(a.Energy_J)-.015)<1e-14 && ...
    abs(sum(a.BBProcessingEnergy_J)-.003)<1e-14);
assert(all(a.Availability=="AVAILABLE"));
unbound=removevars(T,'EndpointPowerStateID');
a=sixgr.truth.integrateLLSEndpointEnergy(unbound);
assert(sum(a.Availability=="NOT_EVALUATED")==1 && ...
    any(a.Status=="equal_power_does_not_establish_joint_endpoint_state"));
% Distinct power states may not be summed, averaged or max-selected.
different=T; different.Power_W(2)=20;
a=sixgr.truth.integrateLLSEndpointEnergy(different);
assert(sum(a.Availability=="NOT_EVALUATED")==1 && isnan(sum(a.Energy_J)));
assert(a.Energy_J(1)==.005 && a.Energy_J(3)==.01);
% Independent populations and separate sites must never be collapsed.
independent=T; independent.ObservationPopulationKey(2)="run1|point2";
a=sixgr.truth.integrateLLSEndpointEnergy(independent);
assert(abs(sum(a.Energy_J)-.02)<1e-14);
twoSites=T; twoSites.EntityID(2)=2;
a=sixgr.truth.integrateLLSEndpointEnergy(twoSites);
assert(abs(sum(a.Energy_J)-.02)<1e-14);
% Overlapping opposite directions require actual joint-state authority.
opposite=T; opposite.Direction(2)="UL";
a=sixgr.truth.integrateLLSEndpointEnergy(opposite);
assert(sum(a.Availability=="NOT_EVALUATED")==1);
% Adjacent half-open intervals do not overlap.
adjacent=T; adjacent.TimestampSim_ms(2)=1;
adjacent.Power_W(2)=20;
a=sixgr.truth.integrateLLSEndpointEnergy(adjacent);
assert(all(a.Availability=="AVAILABLE") && abs(sum(a.Energy_J)-.03)<1e-14);
% A missing load/model operand is not a measured nonidentical power state.
missing=T(1,:); missing.Power_W=NaN;
a=sixgr.truth.integrateLLSEndpointEnergy(missing);
assert(a.Availability=="NOT_EVALUATED" && ...
    a.Status=="missing_endpoint_power_model_inputs" && isnan(a.Energy_J));
ok=true;
end
