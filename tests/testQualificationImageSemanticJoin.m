function tests=testQualificationImageSemanticJoin
tests=functiontests(localfunctions);
end

function testExactImageAndSourceHashesJoin(testCase)
[root,audit,semantic,cleanup]=localFixture(); %#ok<ASGLU>
[updated,trace]=sixgr.integration.qualification. ...
    QualificationImageSemanticJoin.apply(audit,semantic,root);
verifyEqual(testCase,string(trace.Status),"PASS");
verifyEqual(testCase,string(updated.Status(2)),"PASS");
verifyTrue(testCase,updated.SemanticValid(2));
end

function testDuplicateAndStaleSemanticRowsFailClosed(testCase)
[root,audit,semantic,cleanup]=localFixture(); %#ok<ASGLU>
duplicate=[semantic;semantic];
[updated,trace]=sixgr.integration.qualification. ...
    QualificationImageSemanticJoin.apply(audit,duplicate,root);
verifyEqual(testCase,string(trace.FailureCode), ...
    "FULLSTACK:SemanticAuditJoinCardinality");
verifyEqual(testCase,string(updated.Status(2)),"INVALID_SEMANTICS");

semantic.PNG_SHA256(:)=string(repmat('0',1,64));
[~,trace]=sixgr.integration.qualification. ...
    QualificationImageSemanticJoin.apply(audit,semantic,root);
verifyFalse(testCase,trace.PNGHashMatch);
verifyEqual(testCase,string(trace.Status),"FAIL");
end

function [root,audit,semantic,cleanup]=localFixture()
root=string(tempname);mkdir(root);
cleanup=onCleanup(@()rmdir(root,"s"));
csvDir=fullfile(root,"reports","csv");mkdir(fullfile(root,"reports"));mkdir(csvDir);
source=fullfile(csvDir,"observed.csv");
writetable(table((1:4)',[1;2;3;4], ...
    'VariableNames',{'Index','Observed'}),source);
imagePath=fullfile(csvDir,"observed.png");
pixels=uint8(repmat(uint8(0:63),64,1));
imwrite(pixels,imagePath);
sourceHash=sixgr.integration.qualification.ArtifactResolver.fileHash(source);
imageHash=sixgr.integration.qualification.ArtifactResolver.fileHash(imagePath);
audit=sixgr.integration.qualification. ...
    QualificationArtifactAuditSchema.empty(2);
audit.RunID(:)="fixture";audit.ArtifactID=["CSV-1";"PNG-1"];
audit.Domain(:)="Fixture";audit.RelativePath= ...
    ["reports/csv/observed.csv";"reports/csv/observed.png"];
audit.ArtifactType=["CSV";"PNG"];audit.MIMEType=["text/csv";"image/png"];
audit.Required(:)=true;audit.Present(:)=true;audit.Valid(:)=true;
audit.Status(:)="PASS";audit.SHA256=[sourceHash;imageHash];
audit.HashValid(:)=true;audit.SchemaValid(:)=true;
audit.SemanticValid(:)=true;
semantic=table("observed.png","observed.csv",sourceHash,imageHash, ...
    64,64,"Fixture","x","y",1,1,4,"PASS", ...
    'VariableNames',{'ImageFile','SourceCSV','SourceCSV_SHA256', ...
    'PNG_SHA256','Width','Height','Title','XLabel','YLabel', ...
    'AxesCount','SeriesCount','FinitePointCount','Status'});
end
