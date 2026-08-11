function result = runJointISACStudy(runMode,configPath,options)
%RUNJOINTISACSTUDY Public executable for the integrated 10.8.2/10.8.3 study.

arguments
    runMode (1,1) string = "quick"
    configPath (1,1) string = "configs/isac/joint_isac_tdoc_master.yaml"
    options.OutputRoot (1,1) string = ""
    options.RunId (1,1) string = ""
end
result = sixgr.isac.runJointStudy(configPath,runMode, ...
    "OutputRoot",options.OutputRoot,"RunId",options.RunId);
end
