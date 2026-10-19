function ok=testLLSMobilityRuntimeOwnership()
% Production physics owner; no waveform or scenario campaign is launched.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),8);
state.MobilityEnabled=true; state.UE.pos_m(1,:)=[50 50 1.5];
state.UE.speed_kmh(1)=3; state.UE.heading_deg(1)=0;
state.MobilityModel=sixgr.scenario.mobility.MobilityRMaMixedSpeed([1000 1000],false);
for slot=1:8
    state.CurrentCanonicalSlot=slot; % Slot-entry binding may happen first.
    state=sixgr.truth.CoupledTruthRuntime.advanceFrame(state,cfg,multi,slot,40);
    before=state.UE.pos_m;
    for consumer=1:3
        state.CurrentCanonicalSlot=slot+consumer; % A future planning cursor.
        state=sixgr.truth.CoupledTruthRuntime.advanceFrame(state,cfg,multi,slot,40);
        assert(isequal(state.UE.pos_m,before));
    end
end
T=state.ServingTraceTable;
assert(height(T)==8 && all(T.MobilityStateVersion==(0:7).'));
assert(max(abs(T.X_m-(50+T.PositionValidAtTime_s*(3/3.6))))<1e-10);
assert(max(abs(diff(T.X_m)./diff(T.PositionValidAtTime_s)-3/3.6))<1e-8);
assert(all(T.PositionValidAtTime_s==T.Time_s));
assert(all(isnan(T.AppliedDopplerHz)) && all(T.AppliedDopplerSource=="not_yet_materialized"), ...
    'A geometry-only test must not invent an applied native-channel Doppler.');
% Production slot entry must retain every resolved symbol role, not just
% the DL/UL spans and a misleading zero guard count.
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,"DL",1,1,4,8,40);
slot=state.SlotTraceTable(end,:);
assert(slot.ClassifiedNumSymbols==14 && slot.SymbolRoleIndexBase==0 && ...
    strlength(slot.SymbolRolesJSON)>0);
roles=string(jsondecode(slot.SymbolRolesJSON));
assert(numel(roles)==14 && ...
    nnz(roles=="DL")==slot.DLNumSymbols && ...
    nnz(roles=="UL")==slot.ULNumSymbols && ...
    nnz(roles=="FLEXIBLE")==slot.FlexibleNumSymbols);
ok=true;
end
