function [cfg, provenance, scfg] = loadStudyConfig(configPath)
%LOADSTUDYCONFIG Load a WebGUI-visible scenario through the canonical loader.
arguments
    configPath (1,1) string = "simulator/configs/scenarios/lls_ran1_10522_td_dmrs_single_slot.yaml"
end
root = localRepoRoot(); path = configPath;
if ~java.io.File(char(path)).isAbsolute(), path = string(fullfile(root, path)); end
scfg = sixgr.lls6g.config.loadScenarioConfig(path);
cfg = scfg.toStruct();
sixgr.studies.ran1ai10522.validateStudyConfig(cfg);
contractPath = string(cfg.study.parameter_contract_path);
if ~java.io.File(char(contractPath)).isAbsolute()
    contractPath = string(fullfile(root, contractPath));
end
if exist(contractPath, "file") ~= 2
    error("sixgr:ran1ai10522:ParameterContractMissing", ...
        "Parameter contract is missing: %s.", contractPath);
end
contract = sixgr.lls6g.config.readConfigFile(contractPath);
if ~strcmp(string(contract.schema_version), ...
        "sixgr.ran1.10_5_2_2.parameter_contract/v1")
    error("sixgr:ran1ai10522:BadParameterContract", ...
        "The parameter contract schema version is unsupported.");
end
provenance = struct( ...
    "ConfigPath", string(scfg.ConfigPath), ...
    "SourceFiles", scfg.SourceFiles, ...
    "ConfigSHA256", string(scfg.ConfigHash), ...
    "ParameterContractPath", contractPath, ...
    "ParameterContractSHA256", sixgr.csi.fileSHA256(contractPath), ...
    "PromptSHA256", lower(string(cfg.study.controlling_prompt_sha256)));
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
