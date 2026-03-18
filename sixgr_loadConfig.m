function cfg = sixgr_loadConfig(cfgFile)
%SIXGR_LOADCONFIG Thin wrapper around sixgr.config.loadConfig.
%
%   cfg = sixgr_loadConfig(cfgFile)
%
% All callers should go through this function so the config system has a
% single source of truth (defaults + merge + normalize + validate).

if nargin < 1 || (isstring(cfgFile) && strlength(cfgFile)==0) || (ischar(cfgFile) && isempty(cfgFile))
    cfgFile = fullfile("config","suite_config.json");
end

% Prefer package config loader
cfg = sixgr.config.loadConfig(cfgFile);

end
