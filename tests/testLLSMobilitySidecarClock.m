function ok=testLLSMobilitySidecarClock()
% Model-derived sidecar positions must use the same elapsed clock as SLS.
setup6GRSimToolkit('Verbose',false);
fixture=sixgr.lls6g.config.readConfigFile(fullfile('simulator','configs', ...
    'fixtures','lls_mobility_sidecar_clock.yaml'));
cfg=sixgr.config.normalizeConfig(sixgr.util.mergeStruct(sixgr.config.defaultConfig(),fixture));
root=fullfile(pwd,'results','lls','mobility_sidecar_clock', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
fprintf('LLS_MOBILITY_CLOCK_EVIDENCE_ROOT=%s\n',root);
artifacts=sixgr.truth.exportLLSLiveMobilityTables(cfg,root,struct());
T=artifacts.ServingTraceTable;
onDisk=readtable(artifacts.ServingTracePath,'VariableNamingRule','preserve');
save(fullfile(root,'clock_regression.mat'),'cfg','artifacts','-v7.3');
dt=sixgr.time.slotDurationSec(cfg);
cadence=double(cfg.system.mobility.updatePeriod_slots);
slot=(0:height(T)-1).';
observedTime=floor(slot/cadence)*cadence*dt;
path=cfg.scenario.mobility.userPaths(1);
speed=double(path.speed_kmh)/3.6;
assert(max(abs(T.Time_s-slot*dt))<1e-12,'Exported observation times must be canonical.');
assert(max(abs(T.X_m-(path.initial_position_m(1)+speed*observedTime)))<1e-10, ...
    'Sidecar must not use future geometry at a held or refreshed observation.');
assert(max(abs(T.Y_m-path.initial_position_m(2)))<1e-10);
assert(max(abs(onDisk.X_m-T.X_m))<1e-9,'Persisted CSV must retain the checked trajectory.');
assert(T.X_m(1)==T.X_m(cadence) && T.X_m(cadence+1)>T.X_m(cadence), ...
    'The first movement must occur after one complete cadence.');
ok=true;
end
