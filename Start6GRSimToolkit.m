function Start6GRSimToolkit(cfgFile)
%START6GRSIMTOOLKIT Launch GUI if present, otherwise print CLI usage.

if nargin < 1 || (isstring(cfgFile) && strlength(cfgFile)==0) || (ischar(cfgFile) && isempty(cfgFile))
    cfgFile = fullfile("config","suite_config.json");
end

setup6GRSimToolkit("Verbose", true);

if exist("SimSuiteGUI","file") == 2
    try
        if exist("sixgr.config.loadConfig","file") == 2 && isfile(cfgFile)
            cfg = sixgr.config.loadConfig(cfgFile);
            SimSuiteGUI("Cfg", cfg);
        else
            SimSuiteGUI("Cfg", cfgFile);
        end
    catch
        SimSuiteGUI();
    end
else
    fprintf("[Start] SimSuiteGUI.m not found yet.\n");
    fprintf("[Start] Use CLI instead:\n");
    fprintf('        report = sixgr_run_3gpp_full_campaign("%s");\n', cfgFile);
end

end
