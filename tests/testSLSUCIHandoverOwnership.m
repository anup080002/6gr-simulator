function ok=testSLSUCIHandoverOwnership()
% Ownership lifecycle only: no physical UCI or BLER qualification claim.
r=sixgr.config.loadSimulationRequest('simulator/configs/scenarios/sls_nr_tdd_21cell_connected.yaml');
cfg=r.Config; cfg.phy.csi.reportCSI=false;
evidenceRoot=fullfile(pwd,'results','sls','uci_identity', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(evidenceRoot);
fprintf('SLS_UCI_IDENTITY_EVIDENCE_ROOT=%s\n',evidenceRoot);
for mode=["shared_configured_resources","per_cell_frequency_pool"]
    current=cfg;
    current.system.linkAbstraction.dynamicPUCCH.resourceBinding.mode=char(mode);
    ledger=sixgr.system.SLSDynamicPUCCH(current);
    ledger.configureUEIdentities(4660);
    ledger.configureServingCells(1,0);
    % Explicit ledger fixture. Only appendDL's ownership contract is used;
    % this is not a generated/decoded grant and is not exported as one.
    g=struct('UEIndex',1,'RNTI',4660,'ControlAbsoluteSlot',0, ...
        'ScheduledAbsoluteSlot',0,'HARQFeedbackAbsoluteSlot',4, ...
        'PHYGrant',struct('IsFrozen',true,'CodingLayout',struct('NumCodewords',1)));
    ledger.appendDL(g,1,0);
    reject(@()ledger.configureServingCells(2,1));
    reject(@()ledger.configureServingCells(2,4));
    reject(@()ledger.configureServingCells(2,5));
    ledger.configureServingCells(1,5);
    assert(isempty(ledger.CompletionTrace),'Elapsed time cannot synthesize completion.');

    % A published SR obligation also remains source-cell-owned until its
    % modeled transport completes; a mere resource/calendar row is not ACK.
    sr=sixgr.system.SLSDynamicPUCCH(current);
    sr.configureUEIdentities(4660);
    due=sr.snapshot(9,9,1,struct([]));
    assert(~isempty(due) && all([due.SRBits]==1));
    before=sr.Trace;
    assert(ismember('RNTI',before.Properties.VariableNames) && ...
        all(before.RNTI==4660), ...
        'sixgr:test:MissingUCIExportIdentity', ...
        'Published UCI must export the installed RNTI, not only the UE index.');
    % A UE identity cannot be replaced after publishing SR/CSI-only UCI.
    % There need not be a data grant or PUSCH transport binding yet.
    rejectIdentity(@()sr.configureUEIdentities(4661));
    assert(sr.rntiForUE(1)==4660 && isequaln(sr.Trace,before), ...
        'Rejected reconfiguration must preserve the original UE and obligation.');
    reject(@()sr.configureServingCells(2,9));
    reject(@()sr.configureServingCells(2,10));
    assert(isequaln(sr.Trace,before) && isempty(sr.CompletionTrace));
    % Use a fresh ledger for in-order completion after the late negative
    % query, so the test never asks a resource registry to rewind its clock.
    completed=sixgr.system.SLSDynamicPUCCH(current);
    completed.configureUEIdentities(4660);
    completed.completeSlot(9,1,struct([]),{},struct([]));
    assert(~isempty(completed.CompletionTrace) && ...
        ~any(completed.CompletionTrace.WaveformBacked) && ...
        ~any(completed.CompletionTrace.PhysicalDecodeQualified));
    priorCompletion=completed.CompletionTrace;
    assert(ismember('RNTI',priorCompletion.Properties.VariableNames) && ...
        all(priorCompletion.RNTI==4660), ...
        'sixgr:test:MissingUCIExportIdentity', ...
        'Completion must retain the original obligation RNTI.');
    rejectIdentity(@()completed.configureUEIdentities(4661));
    assert(completed.rntiForUE(1)==4660 && ...
        isequaln(completed.CompletionTrace,priorCompletion), ...
        'Completed historical evidence must not change protocol identity.');
    publication=fullfile(evidenceRoot,char(mode+"_obligations.csv"));
    completion=fullfile(evidenceRoot,char(mode+"_completions.csv"));
    sixgr.util.csvWriteTable(publication,completed.Trace,'PreserveSchema',true);
    sixgr.util.csvWriteTable(completion,completed.CompletionTrace,'PreserveSchema',true);
    for file=[string(publication),string(completion)]
        exported=readtable(file,'VariableNamingRule','preserve');
        assert(all(exported.RNTI==4660) && all(exported.UEIndex==1) && ...
            ~any(exported.WaveformBacked), ...
            'CSV must preserve installed RNTI versus UE index and model provenance.');
    end
    completed.configureServingCells(2,10);
end

function rejectIdentity(fn)
try, fn(); catch ME
    assert(strcmp(ME.identifier,'sixgr:system:UCIIdentityAlreadyIssued'), ...
        'Unexpected identity error %s: %s',ME.identifier,ME.message);
    return;
end
error('sixgr:test:LostUCIIdentity','Published UCI was reinterpreted under a replacement RNTI.');
end
fprintf('SLS_UCI_HANDOVER_OWNERSHIP_PASS policies=2 future_due_overdue_and_SR=1 physical_qualification=0\n');
ok=true;
end

function reject(fn)
try, fn(); catch ME
    assert(strcmp(ME.identifier,'sixgr:system:UCIHandoverOutstanding'), ...
        'Unexpected ownership error %s: %s',ME.identifier,ME.message);
    return;
end
error('sixgr:test:LostUCIOwnership','Handover discarded an uncompleted source-cell UCI obligation.');
end
