function tests=testQualificationFilesystemPublication
tests=functiontests(localfunctions);
end

function testFilesystemPublishesWithDatabaseInactive(testCase)
sixgr.db.deactivateArtifactStore();
root=string(tempname);mkdir(root);
cleanup=onCleanup(@()rmdir(root,"s")); %#ok<NASGU>
mkdir(fullfile(root,"reports"));mkdir(fullfile(root,"reports","csv"));
path=fullfile(root,"reports","csv","observed.csv");
writetable(table(1,'VariableNames',{'Observed'}),path);
audit=sixgr.integration.qualification. ...
    QualificationArtifactAuditSchema.empty(1);
audit.RunID="R";audit.ArtifactID="A";audit.RelativePath= ...
    "reports/csv/observed.csv";audit.Present=true;
audit.SHA256=sixgr.integration.qualification.ArtifactResolver.fileHash(path);
first=sixgr.integration.qualification.CompositeArtifactPublisher. ...
    publish("R",root,audit,"DatabaseMandatory",false);
second=sixgr.integration.qualification.CompositeArtifactPublisher. ...
    publish("R",root,audit,"DatabaseMandatory",false);
verifyEqual(testCase,string(first.Status),"PASS");
verifyEqual(testCase,string(first.Filesystem.Status),"PASS");
verifyEqual(testCase,height(first.Filesystem),1);
verifyEqual(testCase,first.Filesystem,second.Filesystem);
verifyEqual(testCase,string(first.Database.Status),"NOT_APPLICABLE");
verifyError(testCase,@()sixgr.integration.qualification. ...
    CompositeArtifactPublisher.publish("R",root,audit, ...
    "DatabaseMandatory",true), ...
    "FULLSTACK:MandatoryDatabasePublisherUnavailable");
end
