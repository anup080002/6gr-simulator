function ok=testTDDSharedPUSCHIndependentCompletion()
% Actual shared receive/context/common-commit path with no DL obligation.
% This does not qualify nonempty HARQ, missing DCI, mixed UCI or the full runner.
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_pusch_independent_empty_uci_fixture.yaml');
logsRoot=fullfile(root,'logs','tdd_shared_pusch_independent_completion');
if ~isfolder(logsRoot), mkdir(logsRoot); end
outputRoot=tempname(logsRoot);
fprintf('TDD_INDEPENDENT_PUSCH_ARTIFACT_ROOT=%s\n',outputRoot);
ok=testSharedPUSCHChannelArtifacts('TDD',false,false,false,true,true,false,outputRoot,fixture,true);
% Structural wiring guard only; the RF fixture above exercises these same
% helpers, but is not evidence that the whole normal coordinator ran.
source=fileread(fullfile(root,'+sixgr','+truth','runWaveformLinkBundle.m'));
section=extractBetween(string(source),'function state=localCompleteSharedDataPlan(state,item)', ...
    'function [state,dl,ul,dc,uc,ds,us]=localDrainSharedDataPlans');
assert(isscalar(section) && contains(section,'job=sixgr.truth.bindSharedPUSCHReceiverContext(state,job);') && ...
    contains(section,'[state,res.HARQ]=sixgr.truth.CoupledTruthRuntime.completeSharedPUSCHHARQFeedbackRuntime(') && ...
    contains(section,'res.TrialTable=sixgr.truth.exportSharedPUSCHChannelEstimate('));
end
