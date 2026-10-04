function ok = testTruthValidationSettings()
% Metadata unit check; not physical/campaign qualification.
cfg=struct('channel',struct('model',"TDL-C",'tdlProfile',"TDL-C",'awgnOnly',false));
opt=struct('ConfigFile',"config/suite_config_truth_validation.json", ...
    'LinkSNR_dB',30,'LinkMaxSimFrames',8,'E2EMaxSlots',24, ...
    'E2EUECount',2,'E2ETrafficModel',"traceReplay", ...
    'SaveFigures',true,'GenerateCampaignPlots',true);
fromFile=sixgr.truth.buildValidationSettings(opt,cfg);
assert(string(fromFile.ConfigFile)==opt.ConfigFile && fromFile.ConfigInputKind=="file");
opt.ConfigFile=cfg;
fromStruct=sixgr.truth.buildValidationSettings(opt,cfg);
assert(isempty(fromStruct.ConfigFile) && fromStruct.ConfigInputKind=="in_memory_struct");
assert(isequal(rmfield(fromFile,{'ConfigFile','ConfigInputKind'}), ...
    rmfield(fromStruct,{'ConfigFile','ConfigInputKind'})), ...
    'Input representation must not change physics or execution metadata.');
decoded=jsondecode(jsonencode(fromStruct));
assert(isempty(decoded.ConfigFile) && string(decoded.ConfigInputKind)=="in_memory_struct");
for invalid={repmat(cfg,1,2),["one.json","two.json"],"",string(missing),17}
    opt.ConfigFile=invalid{1};
    try
        sixgr.truth.buildValidationSettings(opt,cfg);
    catch ME
        assert(string(ME.identifier)=="sixgr:truth:InvalidValidationConfigSource",'%s',ME.message);
        continue;
    end
    error('testTruthValidationSettings:ExpectedFailure','Invalid source must be rejected.');
end
ok=true;
end
