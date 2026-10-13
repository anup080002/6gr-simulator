function scope=standalonePHYCalibrationEvidenceScope(scfg,cfg)
% Explicit execution ownership, never inferred from absent result files.
% Strict waveform truth still applies; only connected scheduler/control
% fields are inapplicable to an independent PHY-calibration bundle.
scope=struct('IndependentPHY',false, ...
    'Reason',"independent_phy_calibration_has_no_connected_scheduler", ...
    'ConnectedFields',["GrantControlState","SchedulerGrantMCSSelectionMode", ...
    "PBCHGatingActive","PRACHGatingActive","PDCCHGatingActive", ...
    "SRSGatingActive","TRSGatingActive"]);
if ~isstruct(cfg) || ~isscalar(cfg), return; end
runner=localScenarioValue(scfg,"scenario.runner_profile","");
model=sixgr.util.structGet(cfg,"lls6g.users.execution_model","");
profiles=[string(sixgr.util.structGet(cfg,"run.pdschExecutionProfile","")), ...
    string(sixgr.util.structGet(cfg,"phy.pdsch.executionProfile","")), ...
    string(sixgr.util.structGet(cfg,"phy.pusch.executionProfile",""))];
if ~isequal(string(runner),"waveform_bundle") || ...
        ~isequal(string(model),"independent_link_sweep") || ...
        numel(profiles)~=3 || ~all(profiles=="phy_calibration")
    return;
end
% A declared causal requirement must never be waived by a profile label.
gates=["pbchRequired","prachRequired","pdcchRequired","pucchRequired", ...
    "puschUCIRequired","srsRequired","trsRequired"];
for field=gates
    value=sixgr.util.structGet(cfg,"run.controlGating."+field,[]);
    if ~((islogical(value) || isnumeric(value)) && isscalar(value) && ...
            isreal(value) && isfinite(value) && value==0)
        return;
    end
end
% Reject a contradictory source configuration as well as runtime metadata.
sourceModel=localScenarioValue(scfg,"users.execution_model",model);
if ~isequal(string(sourceModel),string(model)), return; end
scope.IndependentPHY=true;
end

function value=localScenarioValue(scfg,path,defaultValue)
if isstruct(scfg)
    value=sixgr.util.structGet(scfg,path,defaultValue);
elseif isobject(scfg) && ismethod(scfg,'get')
    value=scfg.get(path,defaultValue);
else
    value=defaultValue;
end
end
