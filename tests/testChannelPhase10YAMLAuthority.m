function ok = testChannelPhase10YAMLAuthority()
% Both operator modes expose and preserve the complete Phase-10 surface.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
root = fullfile(pwd,"simulator","configs","scenarios");
names = ["master_sinr_sweep.yaml","master_geometry_based.yaml"];
required = ["enabled","profile_id","specification","propagation_scenario", ...
    "coordinate_frame","pathloss","los","o2i","oxygen_absorption", ...
    "topology","ue_drop","channel_update","interference", ...
    "absolute_power","raytracing"];
for index = 1:numel(names)
    scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(root,names(index)));
    source = scenario.toStruct();
    assert(isfield(source.channels,"phase10_strict"), ...
        "%s does not expose channels.phase10_strict.",names(index));
    phase = source.channels.phase10_strict;
    assert(all(isfield(phase,required)), ...
        "%s omits a Phase-10 operator field.",names(index));
    cfg = sixgr.lls6g.buildInternalConfig(source,tempdir);
    assert(isfield(cfg.channel,"phase10Strict"));
    assert(string(cfg.channel.phase10Strict.profile_id)==string(phase.profile_id));
    assert(string(cfg.channel.phase10Strict.specification)=="TR38.901-V19.2.0");
    assert(double(cfg.channel.pathloss.streetWidth_m)== ...
        double(phase.pathloss.street_width_m));
    assert(double(cfg.channel.pathloss.buildingHeight_m)== ...
        double(phase.pathloss.building_height_m));
    if logical(phase.enabled)
        assert(string(cfg.channel.complianceMode)=="strict_38901");
        assert(string(cfg.channel.propagationScenario)== ...
            string(phase.propagation_scenario));
        assert(string(cfg.channel.o2i.model)==string(phase.o2i.profile));
    end
end

badConfig = sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(root,"master_geometry_based.yaml"));
badScenario = badConfig.toStruct();
badScenario.channels.phase10_strict.enabled = true;
badScenario.channels.phase10_strict.coordinate_frame = "WGS84";
localAssertError(@()sixgr.lls6g.buildInternalConfig(badScenario,tempdir), ...
    "CHANNEL:InvalidCoordinateFrame");
ok = true;
end

function localAssertError(action, expected)
try
    action();
catch exception
    assert(strcmp(exception.identifier,expected), ...
        "Expected %s, received %s.",expected,exception.identifier);
    return;
end
error("testChannelPhase10YAMLAuthority:ExpectedFailure", ...
    "Expected %s.",expected);
end
