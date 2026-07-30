function result=resumeFinalize(options)
%RESUMEFINALIZE Recover finalization without rerunning simulation physics.
arguments
    options.SourceRunRoot (1,1) string
    options.RecoveryRunRoot (1,1) string
    options.Strict (1,1) logical = true
    options.StopAfterStage (1,1) string = ""
end
result=sixgr.integration.qualification. ...
    QualificationFinalizationRecoveryRunner.run( ...
    options.SourceRunRoot,options.RecoveryRunRoot, ...
    "Strict",options.Strict,"StopAfterStage",options.StopAfterStage);
end
