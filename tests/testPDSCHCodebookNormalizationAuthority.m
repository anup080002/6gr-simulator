function [ok,checks] = testPDSCHCodebookNormalizationAuthority(outputRoot)
% Declared scheduling operands -> native codebook/freeze/hydration boundary.
% No received CSI, PDCCH, waveform execution, BLER or rank adaptation claim.
% The actual strict Type-I matrix is never rescaled to satisfy a later guard.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_four_port_received_rank_transition_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
[cfg,~]=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,16,2);
strict=logical(sixgr.util.structGet(cfg,'mimo.strict', ...
    sixgr.util.structGet(cfg,'phy.mimo.strict',false)));
assert(strict && cfg.phy.pdsch.numPorts==4);
% Explicit adversarial ambient default: this is not the selected codebook's
% power convention. It must remain valid for separately supplied matrices.
cfg.phy.pdsch.precoding.normalizationConvention='semi_unitary';
cfg.phy.pdsch.precoderNormalizationConvention='semi_unitary';
before=cfg;
if nargin<1 || strlength(string(outputRoot))==0
    outputRoot=tempname(fullfile(fileparts(fileparts(mfilename('fullpath'))),'logs'));
end
assert(~isfolder(outputRoot),'test:PDSCHNormalizationOutputExists', ...
    'Use a new diagnostic folder; do not overwrite retained evidence.');
mkdir(outputRoot);
rows=repmat(struct('Case',"",'Passed',false,'FailureID',"",'Detail',"", ...
    'FailureStackJSON',"",'FailureReport',""),0,1);
evidence=cell(0,1);
for rankValue=1:4
    for pmi=[0 7]
        record("native_rank"+rankValue+"_pmi"+pmi, ...
            @() localNative(cfg,rankValue,pmi));
    end
end
for rankValue=[2 4]
    record("explicit_semi_unitary_rank"+rankValue, ...
        @() localExplicit(cfg,rankValue,"semi_unitary",false));
    record("explicit_unit_frobenius_rank"+rankValue, ...
        @() localExplicit(cfg,rankValue,"unit_frobenius",false));
    record("explicit_bad_semi_unitary_rank"+rankValue, ...
        @() localExplicit(cfg,rankValue,"semi_unitary",true));
    record("explicit_bad_unit_frobenius_rank"+rankValue, ...
        @() localExplicit(cfg,rankValue,"unit_frobenius",true));
end
for rankValue=[1 4]
    record("contradictory_codebook_declaration_rank"+rankValue, ...
        @() localConflict(cfg,rankValue));
end
record("legacy_non_strict_per_layer_policy",@() localLegacy(cfg));
assert(isequaln(cfg,before),'test:PDSCHNormalizationInputMutation', ...
    'Codebook selection and hydration cannot mutate the installed input.');
checks=struct2table(rows);
scope=struct('WaveformExecuted',false,'ReceivedFeedbackQualified',false, ...
    'EvidenceScope',"declared_native_codebook_frozen_grant_hydration_boundary");
save(fullfile(outputRoot,'pdsch_normalization_authority.mat'), ...
    'checks','evidence','scope','cfg','-v7.3');
writetable(checks,fullfile(outputRoot,'pdsch_normalization_authority.csv'));
failed=checks(~checks.Passed,:);
for k=1:height(failed)
    fprintf(2,'PDSCH_NORMALIZATION %s FAIL %s %s\n', ...
        failed.Case(k),failed.FailureID(k),failed.Detail(k));
end
fprintf('PDSCH_NORMALIZATION_AUTHORITY cases=%d failures=%d waveform=0 folder=%s\n', ...
    height(checks),height(failed),string(outputRoot));
assert(isempty(failed),'test:PDSCHCodebookNormalizationAuthority', ...
    '%d/%d normalization contracts failed; evidence: %s.', ...
    height(failed),height(checks),string(outputRoot));
ok=true;
    function record(name,fn)
        row=struct('Case',name,'Passed',false,'FailureID',"",'Detail',"", ...
            'FailureStackJSON',"",'FailureReport',"");
        retained=struct();
        try
            retained=fn(); row.Passed=true;
        catch failure
            row.FailureID=string(failure.identifier); row.Detail=string(failure.message);
            row.FailureStackJSON=string(jsonencode(failure.stack));
            row.FailureReport=string(getReport(failure,'extended','hyperlinks','off'));
        end
        rows(end+1,1)=row; evidence{end+1,1}=retained; %#ok<AGROW>
    end
end

function retained=localNative(cfg,rankValue,pmi)
[candidates,info]=sixgr.phy.dl.pmiCodebookCandidates(cfg,rankValue,4);
index=find([candidates.PMI]==pmi,1);
assert(~isempty(index),'test:PDSCHNormalizationPMI','Declared PMI must exist.');
W=double(candidates(index).W);
assert(string(info.NormalizationConvention)=="unit_frobenius" && ...
    string(candidates(index).NormalizationConvention)=="unit_frobenius");
assert(abs(sum(abs(W(:)).^2)-1)<1e-12 && ...
    norm(W'*W-eye(rankValue)/rankValue,'fro')<1e-12);
grant=localGrant(cfg,rankValue,pmi);
frozen=sixgr.phy.grant.freezePHYGrant(cfg,'DL',grant);
prec=frozen.PrecodingState;
assert(string(prec.NormalizationConvention)=="unit_frobenius" && ...
    isequaln(prec.PMICodebookMatrixCSIPorts,W) && ...
    string(prec.PMICodebookMatrixCSIPortsSHA256)==string(candidates(index).MatrixSHA256));
% Current fixture has an orthonormal physical CSI basis. Preserve both
% selected logical coefficients and its actual composed physical matrix.
assert(abs(norm(prec.MatrixPhysicalPorts,'fro')^2-1)<1e-12);
grant.PHYGrant=frozen;
applied=sixgr.phy.grant.applyPHYGrantToConfig(cfg,frozen);
assert(string(applied.phy.pdsch.precoding.normalizationConvention)=="unit_frobenius" && ...
    string(applied.phy.pdsch.precoderNormalizationConvention)=="unit_frobenius" && ...
    ~applied.phy.pdsch.normalizePrecodingMatrix);
resolved=sixgr.phy.dl.resolvePDSCHPrecoding(struct('NumLayers',rankValue),applied);
assert(string(resolved.NormalizationConvention)=="unit_frobenius" && ...
    string(resolved.AppliedMatrixSHA256)==string(prec.AppliedMatrixSHA256) && ...
    resolved.PrecoderTraceTarget==1 && abs(resolved.PrecoderPowerScale-1)<1e-12 && ...
    resolved.TotalPowerPreservingTrace && resolved.AllPRGTotalPowerPreserving);
hydrated=sixgr.truth.GrantPreparation.hydrateGrantSnapshot(cfg,'DL',grant);
assert(isequaln(hydrated.PHYGrant,frozen) && ...
    isequaln(hydrated.PrecodingMatrix,prec.MatrixPhysicalPorts) && ...
    isequaln(hydrated.PrecodingMatrixLogicalPorts,prec.MatrixLogicalPorts), ...
    'test:PDSCHNormalizationHydration','Hydration must preserve the frozen matrix and convention.');
% Ambient replay configuration cannot reinterpret the original grant.
ambient=cfg; ambient.phy.pdsch.precoding.normalizationConvention='explicit_no_normalization';
replay=sixgr.truth.applyFrozenDLGrantAuthority(ambient,grant,'normalization_replay');
replayed=sixgr.phy.dl.resolvePDSCHPrecoding(struct('NumLayers',rankValue),replay);
assert(isequaln(replayed.MatrixPorts,resolved.MatrixPorts) && ...
    string(replayed.NormalizationConvention)=="unit_frobenius");
assert(isequaln(sixgr.phy.grant.freezePHYGrant(cfg,'DL',grant),frozen));
retained=struct('Candidate',candidates(index),'Frozen',frozen, ...
    'Hydrated',hydrated,'Resolved',resolved);
end

function retained=localExplicit(cfg,rankValue,convention,poison)
W=eye(4,rankValue);
if (convention=="unit_frobenius") ~= poison, W=W/sqrt(rankValue); end
grant=localGrant(cfg,rankValue,NaN);
grant.PrecodingMatrixLogicalPorts=W;
grant.PrecoderNormalizationConvention=char(convention);
frozen=sixgr.phy.grant.freezePHYGrant(cfg,'DL',grant);
assert(string(frozen.PrecodingState.NormalizationConvention)==convention && ...
    isequaln(frozen.PrecodingState.MatrixLogicalPorts,W));
applied=sixgr.phy.grant.applyPHYGrantToConfig(cfg,frozen);
call=@() sixgr.phy.dl.resolvePDSCHPrecoding(struct('NumLayers',rankValue),applied);
if poison
    localReject(call,'sixgr:mimo:PrecoderNormalizationMismatch');
else
    resolved=call();
    assert(string(resolved.NormalizationConvention)==convention && ...
        string(resolved.AppliedMatrixSHA256)==string(frozen.PrecodingState.AppliedMatrixSHA256));
end
retained=struct('Frozen',frozen,'ExpectedRejection',poison);
end

function retained=localConflict(cfg,rankValue)
grant=localGrant(cfg,rankValue,0);
grant.PrecoderNormalizationConvention='semi_unitary';
localReject(@() sixgr.phy.grant.freezePHYGrant(cfg,'DL',grant), ...
    'sixgr:phy:grant:DLCodebookNormalizationConflict');
retained=struct('Requested',grant.PrecoderNormalizationConvention,'Rank',rankValue);
end

function retained=localLegacy(cfg)
cfg.mimo.strict=false; cfg.phy.mimo.strict=false;
[candidates,~]=sixgr.phy.dl.pmiCodebookCandidates(cfg,2,4);
assert(~isfield(candidates,'NormalizationConvention') && ...
    norm(candidates(1).W'*candidates(1).W-eye(2),'fro')<1e-12, ...
    'test:PDSCHLegacyNormalization','Do not change the declared legacy catalog power policy.');
grant=localGrant(cfg,2,candidates(1).PMI);
frozen=sixgr.phy.grant.freezePHYGrant(cfg,'DL',grant);
assert(string(frozen.PrecodingState.NormalizationConvention)=="semi_unitary");
applied=sixgr.phy.grant.applyPHYGrantToConfig(cfg,frozen);
resolved=sixgr.phy.dl.resolvePDSCHPrecoding(struct('NumLayers',2),applied);
assert(resolved.PrecoderTraceTarget==2 && resolved.TotalPowerPreservingTrace);
retained=struct('Frozen',frozen,'Resolved',resolved);
end

function grant=localGrant(cfg,rankValue,pmi)
pdsch=cfg.phy.pdsch;
grant=struct('Direction','DL','Frame',2,'Slot',16, ...
    'UEIndex',1,'RNTI',double(pdsch.RNTI),'ServingCell',1, ...
    'PRBSet',double(pdsch.prbSet(:).'),'SymbolAllocation',double(pdsch.symbolAllocation(:).'), ...
    'Modulation',pdsch.modulation,'TargetCodeRate',double(pdsch.codeRate), ...
    'MCSIndex',double(pdsch.mcsIndex),'MCS',double(pdsch.mcsIndex), ...
    'NumLayers',rankValue,'Layers',rankValue,'NumLogicalPorts',4, ...
    'PMI',pmi,'AppliedPrecoderPMI',pmi,'CRI',0, ...
    'PrecodingMatrix',[],'PrecodingActive',true,'K0',0, ...
    'GrantContextId',string(sprintf('declared_normalization_rank_%d_pmi_%g',rankValue,pmi)), ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
% A missing numeric PMI is legitimate for an explicit matrix. Do not turn
% its unrelated fixture identity into a missing string by concatenating NaN.
assert(~ismissing(grant.GrantContextId) && strlength(grant.GrantContextId)>0);
grant=withAuthoredPDSCHDCI(cfg,grant);
end

function localReject(fn,expected)
try
    fn();
catch failure
    assert(string(failure.identifier)==string(expected), ...
        'test:PDSCHNormalizationWrongRejection','Expected %s; got %s: %s.', ...
        expected,failure.identifier,failure.message);
    return;
end
error('test:PDSCHNormalizationMissingRejection','Expected %s.',expected);
end
