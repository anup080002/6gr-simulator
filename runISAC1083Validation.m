function result=runISAC1083Validation(configPath,options)
%RUNISAC1083VALIDATION Repository entry point for agenda item 10.8.3.
arguments
    configPath (1,1) string = "configs/isac/joint_isac_tdoc_master.yaml"
    options.OutputRoot (1,1) string = ""
    options.RunId (1,1) string = ""
end
args={};
if options.OutputRoot~="", args=[args,{"OutputRoot",options.OutputRoot}]; end
if options.RunId~="", args=[args,{"RunId",options.RunId}]; end
result=sixgr.isac.run1083Validation(configPath,args{:});
end
