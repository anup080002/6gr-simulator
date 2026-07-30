function tests=testQualificationRegressionSharding
tests=functiontests(localfunctions);
end

function testScenarioMatrixTasksAreIndependentAndBounded(testCase)
T=sixgr.integration.qualification.ScenarioMatrixRegressionSharder.tasks();
enumerated=sixgr.integration.qualification. ...
    ScenarioMatrixRegressionSharder.enumeratedTests();
classes=sixgr.integration.qualification. ...
    ScenarioMatrixRegressionSharder.timeoutClasses();
verifyEqual(testCase,height(T),2);
verifyEqual(testCase,height(enumerated),2);
verifyEqual(testCase,numel(unique(T.TaskID)),2);
verifyEqual(testCase,numel(unique(T.TestName)),2);
verifyTrue(testCase,all(T.TimeoutClass=="SCENARIO_MATRIX"));
verifyTrue(testCase,all(isfinite(T.TimeoutSeconds) & T.TimeoutSeconds>0));
verifyEqual(testCase,classes.TimeoutClass, ...
    ["UNIT";"COMPONENT";"INTEGRATION"; ...
    "SCENARIO_MATRIX";"FULL_REGRESSION"]);
verifyTrue(testCase,all(isfinite(classes.BudgetSeconds) & ...
    classes.BudgetSeconds>0));
for name=reshape(T.TestName,1,[])
    verifyNotEmpty(testCase,which(name));
end
end

function testTimeoutExitRemainsFailure(testCase)
source=fileread(which("sixgr.integration.qualification." + ...
    "ScenarioMatrixRegressionSharder"));
verifyTrue(testCase,contains(source,"exitCode==124"));
verifyTrue(testCase,contains(source,"FULLSTACK:RegressionTimeout"));
verifyFalse(testCase,contains(source,"exitCode==124,value=""PASS"""));
end
