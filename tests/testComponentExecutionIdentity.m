function ok = testComponentExecutionIdentity()
% Metadata fixture only: no physical performance or connected qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg.run = struct('runTag',"component_run",'executionID',"component_execution", ...
    'scenarioID',"component_scenario");
cfg.meta.configHash = string(repmat('a',1,64));
row = table(1,20,20,0,true,"isolated_component_waveform", ...
    'VariableNames',{'Slot','ExpectedBitCount','DecodedBitCount','BitErrors', ...
    'ReceiverUsable','SourceClassification'});
for signal = ["PBCH","PRACH","PDCCH","PUCCH","SRS","TRS","CSI-RS"]
    bound = sixgr.truth.bindComponentExecutionIdentity(row,cfg,signal);
    assert(bound.RunID==cfg.run.runTag && bound.ExecutionID==cfg.run.executionID && ...
        bound.ScenarioID==cfg.run.scenarioID && bound.ConfigHash==cfg.meta.configHash);
    assert(bound.EvidenceScope=="component_anchor" && ~bound.SameScenarioInPathEligible);
    assert(isequaln(bound(:,row.Properties.VariableNames),row));
    assert(isequaln(bound,sixgr.truth.bindComponentExecutionIdentity(bound,cfg,signal)));
    foreign = bound; foreign.ExecutionID="other_execution";
    mustFail(@()sixgr.truth.bindComponentExecutionIdentity(foreign,cfg,signal), ...
        "sixgr:truth:CoupledControlIdentityMismatch");
    promoted = bound; promoted.SameScenarioInPathEligible=true;
    mustFail(@()sixgr.truth.bindComponentExecutionIdentity(promoted,cfg,signal), ...
        "sixgr:truth:ComponentEvidenceScopeConflict");
end
% CSI-RS remains a measured isolated component: metadata ownership must
% preserve RS power, SINR, selected rank and resource identity exactly.
csirs = table(3,7,-18.25,11.5,2,true, ...
    'VariableNames',{'Slot','ResourceID','RSRP_dBm','MeasuredSINR_dB','RI','Observed'});
boundCSI=sixgr.truth.bindComponentExecutionIdentity(csirs,cfg,"CSI-RS");
assert(isequaln(boundCSI(:,csirs.Properties.VariableNames),csirs) && ...
    boundCSI.SourceClassification=="isolated_component_waveform" && ...
    boundCSI.EvidenceScope=="component_anchor" && ~boundCSI.SameScenarioInPathEligible);
unbound = sixgr.truth.bindComponentExecutionIdentity(row,struct(),"PUCCH");
assert(~ismember("ExecutionID",string(unbound.Properties.VariableNames)) && ...
    ~unbound.SameScenarioInPathEligible);
assert(isequaln(table(),sixgr.truth.bindComponentExecutionIdentity(table(),cfg,"PUCCH")));
for signal=["PRACH","SRS","TRS"]
    missingClassification=removevars(row,"SourceClassification");
    component=sixgr.truth.bindComponentExecutionIdentity(missingClassification,cfg,signal);
    assert(component.SourceClassification=="isolated_component_waveform");
    canonical=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable(signal,component);
    assert(canonical.SourceClassification=="isolated_component_waveform" && ...
        canonical.RuntimeConsumer=="none_isolated_component");
end
for label=["execution_failed","proxy_test_only"]
    explicit=row; explicit.SourceClassification=label;
    preserved=sixgr.truth.bindComponentExecutionIdentity(explicit,cfg,"SRS");
    assert(preserved.SourceClassification==label, ...
        'Binding scope must never erase a producer failure or proxy label.');
end
% Immutable identity alone must not promote the component to in-path truth.
bound = sixgr.truth.bindComponentExecutionIdentity(row,cfg,"PUCCH");
result = sixgr.truth.evaluateInPathComponentEvidence(cfg,struct('PUCCH',bound),"pucch");
assert(~result.StrictOk && result.FailureReason=="component_scope_not_eligible_for_in_path");
% Exercise the exact producer classification statements without launching
% another bundle. This verifies metadata scope, not receiver qualification.
source=fileread(which('sixgr.truth.runWaveformLinkBundle'));
control=fileread(which('sixgr.truth.PDCCHControlRuntime'));
assert(contains(source, ...
    '[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.receiveTrial(varargin{:});'), ...
    'The runner must consume the canonical PDCCH producer classification.');
for signal=["PDCCH","PRACH"]
    if signal=="PDCCH"
        producer=control;
        pattern='(?s)if isempty\(fieldnames\(grantContext\)\)\s+r.SourceClassification = "isolated_component_waveform";.*?\r?\n\s*end';
    else
        producer=source;
        pattern='(?s)if ~isfinite\(slotIdx\)\s+r.SourceClassification = "isolated_component_waveform";.*?\r?\nend';
    end
    statement=regexp(producer,pattern,'match');
    assert(numel(statement)==1,'Expected one producer scope binding for %s.',signal);
    for integrated=[false,true]
        r=struct('SourceClassification',"active_integrated", ...
            'RuntimeConsumer',"actual_runtime_consumer", ...
            'CRCPass',false,'BitErrors',3,'ExpectedBitCount',20);
        grantContext=struct(); slotIdx=NaN;
        if integrated, grantContext.GrantContextId="grant_1"; slotIdx=7; end
        eval(statement{1});
        assert(~r.CRCPass && r.BitErrors==3 && r.ExpectedBitCount==20, ...
            'Scope classification must not change measured outcomes.');
        if integrated
            assert(r.SourceClassification=="active_integrated" && ...
                r.RuntimeConsumer=="actual_runtime_consumer");
        else
            assert(r.SourceClassification=="isolated_component_waveform" && ...
                r.RuntimeConsumer=="none_isolated_component");
            T=struct2table(r);
            % Full RA procedure fields must not override isolated scope.
            if signal=="PRACH"
                T.RAProcedureType="contention_based_four_step";
                T.FullRAEvidenceSource="sixgr.phy.ra.runFourStepRA";
                T.PreambleIndexTx=1;
                T.RACompleted=true;
            end
            T=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable(signal,T);
            assert(T.SourceClassification=="isolated_component_waveform" && ...
                T.RuntimeConsumer=="none_isolated_component");
        end
    end
end
ok = true;
end

function mustFail(fn,id)
try
    fn();
catch ME
    assert(string(ME.identifier)==id,'%s: %s',ME.identifier,ME.message);
    return;
end
error('testComponentExecutionIdentity:ExpectedFailure','Expected %s.',id);
end
