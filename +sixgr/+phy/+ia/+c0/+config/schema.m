function value = schema()
%SCHEMA Load the versioned C0 IA configuration schema.
root = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts( ...
    mfilename("fullpath")))))));
value = sixgr.lls6g.config.readConfigFile(fullfile(root,"simulator", ...
    "configs","initial_access","c0","schema.yaml"));
end
