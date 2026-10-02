function result = executeS0FTP3CalibrationCase(request, baseConfig, study, runtimeParameters)
%EXECUTES0FTP3CALIBRATIONCASE Explicitly selected S0 SystemLevelRunner adapter.
% The caller supplies the validated complete S0 runtime configuration and
% explicit duration. This adapter does not invent PHY/array/MCS policies.
arguments
    request struct
    baseConfig struct
    study struct
    runtimeParameters struct
end
c=request.Case;
if ~istable(c) || height(c)~=1 || string(c.ComparatorID)~="S0"
    error("sixgr:ran1ai1032:LoadCalibrationComparator","Only S0 can establish the offered-load rate.");
end
if ~isfield(runtimeParameters,"NumTTI") || ...
        runtimeParameters.NumTTI<request.FirstMeasurementTTI || ...
        runtimeParameters.NumTTI~=fix(runtimeParameters.NumTTI)
    error("sixgr:ran1ai1032:LoadCalibrationDuration","Explicit NumTTI must extend beyond warmup.");
end
cfg=sixgr.util.mergeStruct(baseConfig,c.ConfigDelta{1});
cfg.traffic.ftp3.arrivalRatePerCell_s=request.ArrivalRatePerCell_s;
cfg.traffic.ftp3.seed=c.TrafficSeed;
cfg.run.shortRun=false;
cfg.run.strictMode=true;
assert(string(study.sls.execution.architecture)=="calibrated_link_abstraction", ...
    'sixgr:ran1ai1032:SLSArchitecture','Use the approved calibrated SLS execution architecture.');
cfg.system.phyBackend=char(study.sls.execution.architecture);
assert(~logical(sixgr.util.structGet(cfg,'system.linkAbstraction.allowDevelopmentFixtures',true)), ...
    'sixgr:ran1ai1032:LoadCalibrationEvidence','Development fixtures cannot calibrate study offered load.');
cfg.system.resourceReservations.enabled=true;
cfg.outputs.detailedSystemTrace=true;
cfg.sls.fwa_population_definitions=study.sls.fwa_population_definitions;
cfg=sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);
params=sixgr.util.mergeStruct(runtimeParameters,c.ExecutionParameters{1});
params.ForceLong=true;
params.DetailedTrace=true;
params.PHYBackend=cfg.system.phyBackend;
spec=params.FWAPopulationSpec;
params.FWAPopulationTable=sixgr.studies.ran1ai1032.buildFWAPopulation( ...
    study,string(spec.ProfileID),spec.ExpectedUECount,spec.PopulationSeed);
if ~isfolder(request.OutputFolder), mkdir(request.OutputFolder); end
save(fullfile(request.OutputFolder,"resolved_runtime.mat"),"cfg","params");
ctx=sixgr.core.SimContext(cfg,"RunFolder",request.OutputFolder);
cleanup=onCleanup(@() localClose(ctx)); %#ok<NASGU>
result=sixgr.system.SystemLevelRunner.run(ctx,params);
result.Details.LoadCalibrationBaseConfigSHA256=string(sixgr.util.sha256Hex( ...
    uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(baseConfig)),"UTF-8"))));
end

function localClose(ctx)
ctx.Logger.close();
delete(ctx);
end
