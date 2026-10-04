function settings = buildValidationSettings(opt, cfg)
%BUILDVALIDATIONSETTINGS Describe the wrapper's actual configuration input.
% A supplied struct is not a file. The effective configuration is persisted
% by the campaign; do not invent a pathname or cast the struct to a string.
settings = struct();
if isstruct(opt.ConfigFile) && isscalar(opt.ConfigFile)
    settings.ConfigFile = '';
    settings.ConfigInputKind = "in_memory_struct";
else
    source = opt.ConfigFile;
    assert((ischar(source) && isrow(source)) || ...
        (isstring(source) && isscalar(source) && ~ismissing(source)), ...
        'sixgr:truth:InvalidValidationConfigSource', ...
        'ConfigFile must be one file path or one scalar configuration struct.');
    assert(strlength(strtrim(string(source)))>0, ...
        'sixgr:truth:InvalidValidationConfigSource','ConfigFile cannot be empty.');
    settings.ConfigFile = char(source);
    settings.ConfigInputKind = "file";
end
settings.UseFastLinkModel = false;
settings.UseMexAcceleration = false;
settings.UseParallelAcceleration = false;
settings.StrictMode = true;
settings.NoProxyTruthContract = true;
settings.OnlyE2EBaseRun = true;
settings.IncludeSystem = false;
settings.IncludeSystemSINRSurface = false;
settings.IncludeCalibrationArtifacts = false;
settings.E2EAirModel = "truth";
settings.E2ETruthFastAWGNPath = false;
settings.RequestedChannelModel = "TDL-C";
settings.NormalizedChannelModel = string(sixgr.util.structGet(cfg, "channel.model", ""));
settings.TDLProfile = string(sixgr.util.structGet(cfg, "channel.tdlProfile", ""));
settings.ChannelAWGNOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", true));
settings.LinkSNR_dB = double(opt.LinkSNR_dB);
settings.LinkMaxSimFrames = round(double(opt.LinkMaxSimFrames));
settings.E2EMaxSlots = round(double(opt.E2EMaxSlots));
settings.E2EUECount = round(double(opt.E2EUECount));
settings.E2ETrafficModel = string(opt.E2ETrafficModel);
settings.SaveFigures = logical(opt.SaveFigures);
settings.GenerateCampaignPlots = logical(opt.GenerateCampaignPlots);
end
