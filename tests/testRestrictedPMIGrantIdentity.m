function [ok,checks] = testRestrictedPMIGrantIdentity(outputRoot)
% Strict, declared codebook subset -> immutable grant identity boundary.
% No received CSI, over-air DCI, waveform or rank-adaptation qualification.
% The actual enumerator owns legal PMI identifiers; their array positions
% are not an alternative wire/index namespace when restrictions leave gaps.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_four_port_received_rank_transition_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
[cfg,~]=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,16,2);
strict=logical(sixgr.util.structGet(cfg,'mimo.strict', ...
    sixgr.util.structGet(cfg,'phy.mimo.strict',false)));
assert(strict && cfg.phy.csi.reportConfiguration.Ports==4);
% Explicit valid request fixture: only two nonadjacent panel beams remain.
% Do not copy an unrestricted matrix array and relabel its PMI identities.
restriction=zeros(1,8); restriction([2 4])=1;
cfg.phy.csi.reportConfiguration.CodebookSubsetRestriction=restriction;
cfg.phy.csi.reportConfiguration.I2Restriction=[];
before=cfg;
if nargin<1 || strlength(string(outputRoot))==0
    outputRoot=tempname(fullfile(fileparts(fileparts(mfilename('fullpath'))),'logs'));
end
assert(~isfolder(outputRoot),'test:RestrictedPMIOutputExists', ...
    'Use a fresh diagnostic folder.');
mkdir(outputRoot);
prototype=struct('Case',"",'Rank',NaN,'RequestedPMI',NaN, ...
    'Passed',false,'FailureID',"",'Detail',"");
rows=repmat(prototype,0,1); evidence=cell(0,1);
for rankValue=1:4
    [candidates,info]=sixgr.phy.dl.pmiCodebookCandidates(cfg,rankValue,4);
    identifiers=double([candidates.PMI]);
    assert(numel(unique(identifiers))==numel(identifiers) && ...
        ~isequal(identifiers,0:numel(identifiers)-1) && ~ismember(0,identifiers), ...
        'test:RestrictedPMIFixture','The actual allowed domain must be noncontiguous and exclude PMI 0.');
    for index=1:numel(candidates)
        record("allowed_sparse_identity",rankValue,identifiers(index), ...
            @() localAllowed(cfg,rankValue,candidates(index),info));
    end
    record("missing_identity_inside_array_count",rankValue,0, ...
        @() localMissing(cfg,rankValue,0));
    record("fractional_identity",rankValue,identifiers(1)+0.5, ...
        @() localMissing(cfg,rankValue,identifiers(1)+0.5));
    record("identity_beyond_allowed_domain",rankValue,max(identifiers)+1, ...
        @() localMissing(cfg,rankValue,max(identifiers)+1));
end
assert(isequaln(cfg,before),'test:RestrictedPMIInputMutation');
checks=struct2table(rows);
scope=struct('WaveformExecuted',false,'ReceivedFeedbackQualified',false, ...
    'EvidenceScope',"declared_actual_codebook_subset_and_frozen_grant_identity");
save(fullfile(outputRoot,'restricted_pmi_grant_identity.mat'), ...
    'checks','evidence','scope','cfg','-v7.3');
writetable(checks,fullfile(outputRoot,'restricted_pmi_grant_identity.csv'));
failed=checks(~checks.Passed,:);
for k=1:height(failed)
    fprintf(2,'RESTRICTED_PMI rank=%g PMI=%g %s FAIL %s %s\n', ...
        failed.Rank(k),failed.RequestedPMI(k),failed.Case(k), ...
        failed.FailureID(k),failed.Detail(k));
end
fprintf('RESTRICTED_PMI_GRANT_IDENTITY cases=%d failures=%d waveform=0 folder=%s\n', ...
    height(checks),height(failed),string(outputRoot));
assert(isempty(failed),'test:RestrictedPMIGrantIdentity', ...
    '%d/%d PMI identity cases failed; retained diagnostics: %s.', ...
    height(failed),height(checks),string(outputRoot));
ok=true;
    function record(name,rankValue,pmi,fn)
        row=prototype; row.Case=name; row.Rank=rankValue; row.RequestedPMI=pmi;
        retained=struct();
        try
            retained=fn(); row.Passed=true;
        catch failure
            row.FailureID=string(failure.identifier); row.Detail=string(failure.message);
        end
        rows(end+1,1)=row; evidence{end+1,1}=retained; %#ok<AGROW>
    end
end

function retained=localAllowed(cfg,rankValue,candidate,info)
grant=localGrant(cfg,rankValue,candidate.PMI);
frozen=sixgr.phy.grant.freezePHYGrant(cfg,'DL',grant);
prec=frozen.PrecodingState;
expectedSHA=string(sixgr.phy.mimo.MatrixContract.digest(double(candidate.W)));
assert(prec.PMI==candidate.PMI && ...
    string(prec.PMICodebookMatrixCSIPortsSHA256)==expectedSHA && ...
    isequaln(prec.PMICodebookMatrixCSIPorts,double(candidate.W)), ...
    'test:RestrictedPMIWrongMatrix', ...
    'Frozen PMI %g must use its own matrix, not candidate-array index PMI+1.',candidate.PMI);
applied=sixgr.phy.grant.applyPHYGrantToConfig(cfg,frozen);
resolved=sixgr.phy.dl.resolvePDSCHPrecoding(struct('NumLayers',rankValue),applied);
assert(resolved.PMI==candidate.PMI && ...
    string(resolved.AppliedMatrixSHA256)==string(prec.AppliedMatrixSHA256), ...
    'test:RestrictedPMIReplayIdentity','Replay must preserve exact PMI and physical matrix.');
retained=struct('Candidate',candidate,'EnumerationInfo',info,'Frozen',frozen,'Resolved',resolved);
end

function retained=localMissing(cfg,rankValue,pmi)
grant=localGrant(cfg,rankValue,pmi);
try
    sixgr.phy.grant.freezePHYGrant(cfg,'DL',grant);
catch failure
    assert(string(failure.identifier)=="sixgr:phy:grant:DLPMIOutOfRange", ...
        'test:RestrictedPMIWrongRejection','Expected DLPMIOutOfRange, got %s: %s.', ...
        failure.identifier,failure.message);
    retained=struct('RequestedPMI',pmi,'ExpectedRejection',string(failure.identifier));
    return;
end
error('test:RestrictedPMIMissingRejection', ...
    'Unavailable PMI %g must not alias a remaining candidate-array position.',pmi);
end

function grant=localGrant(cfg,rankValue,pmi)
pdsch=cfg.phy.pdsch;
grant=struct('Direction','DL','Frame',2,'Slot',16,'UEIndex',1, ...
    'RNTI',double(pdsch.RNTI),'ServingCell',1, ...
    'PRBSet',double(pdsch.prbSet(:).'),'SymbolAllocation',double(pdsch.symbolAllocation(:).'), ...
    'Modulation',pdsch.modulation,'TargetCodeRate',double(pdsch.codeRate), ...
    'MCSIndex',double(pdsch.mcsIndex),'MCS',double(pdsch.mcsIndex), ...
    'NumLayers',rankValue,'Layers',rankValue,'NumLogicalPorts',4, ...
    'PMI',pmi,'AppliedPrecoderPMI',pmi,'CRI',0, ...
    'PrecodingMatrix',[],'PrecodingActive',true,'K0',0, ...
    'GrantContextId',"declared_restricted_rank_"+rankValue+"_pmi_"+pmi, ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
grant=withAuthoredPDSCHDCI(cfg,grant);
end
