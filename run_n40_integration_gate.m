function receipt=run_n40_integration_gate(configPath,outputRoot,runTag)
% Actual two-point waveform qualification followed by native55->60 resumes.
% Configuration, output location and run identity are the only CLI inputs.
setup6GRSimToolkit('Verbose',false);
plan=sixgr.validation.preflightN40IntegrationGate(configPath,outputRoot,runTag);
outputRoot=plan.ResultsRoot;
diagnostic=fullfile(outputRoot,'integration_gates',runTag);
assert(~isfolder(diagnostic),'sixgr:validation:N40GateExistingDiagnostics', ...
    'Use a fresh run tag; previous gate evidence must be retained.');
mkdir(diagnostic);
frozen=freeze(plan);
sixgr.util.jsonWrite(fullfile(diagnostic,'preflight.json'),plan);
sixgr.util.jsonWrite(fullfile(diagnostic,'frozen_sources.json'),frozen);
receipt=struct('ContractVersion',plan.ContractVersion,'Ok',false, ...
    'RunFolder',plan.RunFolder,'DiagnosticFolder',string(diagnostic), ...
    'Phase',"running_full_sweep",'Errors',struct([]),'Baseline',struct(),'Final',struct());
saveReceipt();
try
    fprintf('N40_GATE_FULL_SWEEP_START folder=%s\n',plan.RunFolder);
    execution=run_6g_phy_lls_single(configPath,outputRoot,runTag);
    assert(strcmpi(sixgr.util.canonicalPath(execution.RunFolder),sixgr.util.canonicalPath(plan.RunFolder)), ...
        'sixgr:validation:N40GateOutputRoot','Production execution returned a different run folder.');
    assertFrozen();
    receipt.Baseline=sixgr.validation.evaluateN40IntegrationGate(plan.RunFolder,'RequireContinuation',false);
    sixgr.util.jsonWrite(fullfile(diagnostic,'baseline_acceptance.json'),serializable(receipt.Baseline));
    receipt.Phase="verifying_checkpoint_continuations"; saveReceipt();
    for k=1:numel(plan.Children)
        label=plan.Children(k).Label;
        fprintf('N40_GATE_CHECKPOINT_CONTINUATION_START child=%s\n',label);
        try
            sixgr.validation.verifyN40CheckpointContinuation( ...
                fullfile(plan.RunFolder,'sweeps',label),fullfile(diagnostic,label), ...
                'CriteriaPath',plan.CriteriaPath);
        catch cause
            recordError("continuation_"+label,cause);
        end
        assertFrozen();
    end
    receipt.Final=sixgr.validation.evaluateN40IntegrationGate(plan.RunFolder);
    receipt.Ok=receipt.Baseline.Ok && receipt.Final.FinalAccepted && isempty(receipt.Errors);
    receipt.Phase="completed"; saveReceipt();
catch cause
    recordError(receipt.Phase,cause);
    receipt.Phase="failed"; saveReceipt();
    rethrow(cause);
end
assert(receipt.Ok,'sixgr:validation:N40IntegrationGateFailed', ...
    'Full integration gate failed. Original evidence retained in %s.',diagnostic);
fprintf('N40_INTEGRATION_GATE_PASS scenarios=%d slots_each=%d continuation_start=%d actual_continuations=%d\n', ...
    numel(plan.Children),plan.FinalSlot,plan.ContinuationStartSlot,numel(plan.Children));

    function assertFrozen()
        assert(isequaln(frozen,freeze(plan)),'sixgr:validation:N40SourceChanged', ...
            'Sources/configuration changed during qualification. A fresh run is required.');
    end
    function recordError(phase,cause)
        item=struct('Phase',string(phase),'Identifier',string(cause.identifier), ...
            'Message',string(cause.message),'Stack',cause.stack);
        receipt.Errors=[receipt.Errors;item];
        fprintf(2,'N40_GATE_FAILURE phase=%s identifier=%s message=%s\n',phase,cause.identifier,cause.message);
        saveReceipt();
    end
    function saveReceipt()
        sixgr.util.jsonWrite(fullfile(diagnostic,'integration_gate.json'),serializable(receipt));
    end
end

function value=freeze(plan)
value=sixgr.runtime.SlotCheckpoint.sourceIdentity();
root=fileparts(mfilename('fullpath'));
scripts=dir(fullfile(root,'scripts','**','*.py'));
paths=[string(plan.SourceFiles(:));string(plan.CriteriaPath)];
for k=1:numel(scripts), paths(end+1)=string(fullfile(scripts(k).folder,scripts(k).name)); end %#ok<AGROW>
% Runtime capability/report contracts can be loaded independently of YAML
% inheritance. Seal those original inputs too, including added/deleted files.
for relative=["simulator/configs","tests/vectors"]
    inputs=dir(fullfile(root,relative,'**','*')); inputs=inputs(~[inputs.isdir]);
    for k=1:numel(inputs), paths(end+1)=string(fullfile(inputs(k).folder,inputs(k).name)); end %#ok<AGROW>
end
paths=sort(unique(paths));
extras=struct('Path',{},'SHA256',{});
for k=1:numel(paths)
    extras(k)=struct('Path',paths(k),'SHA256',sixgr.util.sha256File(paths(k))); %#ok<AGROW>
end
value.ConfigurationAndReportSources=extras;
end

function out=serializable(value)
if istable(value), value=table2struct(value); end
out=value;
if isstruct(value)
    for j=1:numel(value)
        names=fieldnames(value);
        for k=1:numel(names), out(j).(names{k})=serializable(value(j).(names{k})); end
    end
elseif iscell(value)
    for j=1:numel(value), out{j}=serializable(value{j}); end
end
end
