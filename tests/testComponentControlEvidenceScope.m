function ok = testComponentControlEvidenceScope()
% Contract fixtures, not statistical or waveform qualification.
cfg.run=struct('scenarioID',"component_scenario",'runTag',"component_run", ...
    'executionID',"component_execution");
cfg.meta.configHash=string(repmat('a',1,64));
cfg.phy=struct('pdcch',struct('enable',true),'pucch',struct('enable',true));
scfg.scenario.target_cases={'pdcch','pucch'};
cfg.validation.strict_component_evidence=struct('enabled',true, ...
    'execution_scope',"component_anchor",'required_components',{{'pdcch','pucch'}});
policy=sixgr.lls6g.runners.resolveStrictControlEvidencePolicy(scfg,cfg);
assert(policy.PDCCHScope=="component_anchor" && policy.PUCCHScope=="component_anchor");
base=table("PASS",'VariableNames',{'Status'});
for field=["StrictOk","ReceiverUsable","DecodeUsable","StrictReceiverEvidenceOk", ...
        "ResourceExtractionAvailable","ChannelEstimateAvailable"]
    base.(field)=true;
end
base.ProxyUsed=false;
base=sixgr.truth.bindComponentExecutionIdentity(base,cfg,"control");
pdcch=base;
for field=["DCICrcPass","PDCCHPayloadMatch","PDCCHReceiverTrialExecuted"]
    pdcch.(field)=true;
end
pdcch.PDCCHExpectedDCIBitCount=64;
pdcch.PDCCHDecodedDCIBitCount=64;
pdcch.PDCCHDCIBitsCompared=64;
pdcch.PDCCHDCIBitErrors=0;
pdcch.GrantValid=false; % No connected grant is claimed by this component.
pucch=base;
for field=["UCIContentMatch","DetectionAttempted","DetectionUsable","CRCPass"]
    pucch.(field)=true;
end
pucch.CRCApplicable=true;
pucch.ExpectedBitCount=20; pucch.DecodedBitCount=20;
pucch.BitsCompared=20; pucch.BitErrors=0;
raw=struct('PDCCH',pdcch,'PUCCH',pucch);
out=sixgr.truth.evaluateConfiguredControlEvidence(cfg,raw,policy);
assert(out.Ok && ~out.SameScenarioInPathEligible && ~out.LaunchedSupplementalWaveform);
assert(all(out.SummaryTable.EvidenceScope=="component_anchor"));
assert(~out.PUCCH.StatisticalDetectorQualified);
assert(isequaln(out.PUCCH.ArtifactTables.pucch_trials,pucch));
inpath=sixgr.truth.evaluateInPathControlEvidence(cfg,raw);
assert(~inpath.Ok,'Identical component evidence must not qualify connected operation.');
for field=["ProxyUsed","SameScenarioInPathEligible"]
    bad=raw; bad.PUCCH.(field)=true;
    rejected=sixgr.truth.evaluateConfiguredControlEvidence(cfg,bad,policy);
    assert(~rejected.Ok);
end
for field=["DecodedBitCount","BitsCompared","CRCPass","ReceiverUsable"]
    bad=raw; bad.PUCCH.(field)=0;
    rejected=sixgr.truth.evaluateConfiguredControlEvidence(cfg,bad,policy);
    assert(~rejected.Ok);
end
bad=raw; bad.PUCCH.ExecutionID="foreign";
assert(~sixgr.truth.evaluateConfiguredControlEvidence(cfg,bad,policy).Ok);
bad=raw; bad.PDCCH=table();
assert(~sixgr.truth.evaluateConfiguredControlEvidence(cfg,bad,policy).Ok);
bad=raw; bad.PUCCH=removevars(pucch,'CRCApplicable');
assert(~sixgr.truth.evaluateConfiguredControlEvidence(cfg,bad,policy).Ok);
% Short payloads legitimately lack CRC, but still require exact decoded bits.
short=raw; short.PUCCH.CRCApplicable=false; short.PUCCH.CRCPass=false;
short.PUCCH.ExpectedBitCount=2; short.PUCCH.DecodedBitCount=2; short.PUCCH.BitsCompared=2;
assert(sixgr.truth.evaluateConfiguredControlEvidence(cfg,short,policy).Ok);
required=cfg; required.run.controlGating.pdcchRequired=true;
mustFail(@()sixgr.lls6g.runners.resolveStrictControlEvidencePolicy(scfg,required));
coupled=cfg; coupled.lls6g.users=struct('enabled',true, ...
    'n_users',1,'execution_model',"slot_coupled_truth");
mustFail(@()sixgr.lls6g.runners.resolveStrictControlEvidencePolicy(scfg,coupled));
unspecified=rmfield(cfg,'validation');
default=sixgr.lls6g.runners.resolveStrictControlEvidencePolicy(scfg,unspecified);
assert(default.PDCCHScope=="in_path" && default.PUCCHScope=="in_path");
fprintf('PASS testComponentControlEvidenceScope\n');
ok=true;
end

function mustFail(fn)
try
    fn();
catch ME
    assert(string(ME.identifier)=="sixgr:lls6g:ControlEvidenceScopeConflict",'%s',ME.message);
    return;
end
error('testComponentControlEvidenceScope:ExpectedFailure','Expected causal-scope rejection.');
end
