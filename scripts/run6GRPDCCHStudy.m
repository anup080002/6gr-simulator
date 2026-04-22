function out = run6GRPDCCHStudy(configPath)
%run6GRPDCCHStudy Launch the 6GR PDCCH study from the canonical scenario.

if nargin < 1 || strlength(string(configPath)) == 0
    configPath = fullfile(pwd, "simulator", "configs", "scenarios", "pdcch_6gr_study.yaml");
end

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

cfgPath = string(configPath);
if exist(cfgPath, "file") ~= 2
    error("sixgr:ctrl:run6GRPDCCHStudy:MissingConfig", ...
        "Scenario config not found: %s", cfgPath);
end

scfg = sixgr.lls6g.config.loadScenarioConfig(cfgPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(pwd, "results", "ctrl6gr_pdcch_script"));

scenarioMatrix = [ ...
    struct("ScenarioID","snr_low_al4", "AggregationLevel",4, "CORESETDuration",2, "MappingType","noninterleaved", "FrequencyAllocationMode","contiguous", "RepetitionMode","none", "SNRdB",0, "ChannelModel","AWGN", "SearchSpaceType","USS", "DMRSVariant","single_port_density_3_per_rb", "REGBundleSize",2, "NumREGPerCCE",6, "MRSSMode","exclusive_6gr", "NumTrials",2)
    struct("ScenarioID","snr_high_al4", "AggregationLevel",4, "CORESETDuration",2, "MappingType","noninterleaved", "FrequencyAllocationMode","contiguous", "RepetitionMode","none", "SNRdB",20, "ChannelModel","AWGN", "SearchSpaceType","USS", "DMRSVariant","single_port_density_3_per_rb", "REGBundleSize",2, "NumREGPerCCE",6, "MRSSMode","exclusive_6gr", "NumTrials",2)
    struct("ScenarioID","map_interleaved", "AggregationLevel",4, "CORESETDuration",2, "MappingType","interleaved", "FrequencyAllocationMode","contiguous", "RepetitionMode","none", "SNRdB",10, "ChannelModel","AWGN", "SearchSpaceType","USS", "DMRSVariant","single_port_density_3_per_rb", "REGBundleSize",2, "NumREGPerCCE",6, "MRSSMode","exclusive_6gr", "NumTrials",1)
    struct("ScenarioID","repetition_inter_slot", "AggregationLevel",4, "CORESETDuration",2, "MappingType","noninterleaved", "FrequencyAllocationMode","contiguous", "RepetitionMode","inter_slot", "SNRdB",5, "ChannelModel","AWGN", "SearchSpaceType","USS", "DMRSVariant","single_port_density_3_per_rb", "REGBundleSize",2, "NumREGPerCCE",6, "MRSSMode","exclusive_6gr", "NumTrials",1)
    ];

out = sixgr.ctrl.runPDCCHStudyLLS(cfg, ...
    "ScenarioID", char(string(scfg.ScenarioID)), ...
    "ScenarioMatrix", scenarioMatrix, ...
    "WriteOutputs", true, ...
    "Verbose", true);
end
