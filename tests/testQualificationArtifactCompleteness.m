function tests=testQualificationArtifactCompleteness
tests=functiontests(localfunctions);
end

function testFullStackSpecifiedReduction(testCase)
audit=sixgr.integration.qualification. ...
    QualificationArtifactAuditSchema.empty(26);
audit.ArtifactID=compose("A-%02d",(1:26)');
audit.Domain(:)="Full Stack Qualification";
audit.ArtifactType=[repmat("CSV",16,1);repmat("PNG",10,1)];
audit.Required(:)=true;audit.Present(:)=true;
audit.Status=[repmat("PASS",13,1);repmat("INVALID_SCHEMA",3,1); ...
    repmat("PASS",10,1)];
T=sixgr.integration.qualification. ...
    QualificationArtifactCompleteness.reduce(audit);
verifyEqual(testCase,T.ValidCSV,13);
verifyEqual(testCase,T.ValidPNG,10);
verifyEqual(testCase,T.CompletenessPct,100*23/26,"AbsTol",1e-12);
verifyEqual(testCase,string(T.Status),"FAIL");
end
