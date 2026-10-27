function ok=testCompactCausalStageEvidence()
% Declared reducer fixtures; actual original-row replay is a separate test.
cfg=sixgr.config.defaultConfig(); cfg.phy.pdsch.strictScheduledDL=true;
root=tempname; mkdir(root); cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
h=string(repmat('a',1,64));
c=table("DL",1,1,4,"grant1","dci1",4660,true,true,"bound","",h,h,true,"PASS", ...
    'VariableNames',{'LinkedPDSCHOrPUSCH','ServingCell','UEIndex','GrantSlot','GrantContextId','DCIId', ...
    'RNTI','GrantBindingRequired','GrantBindingOk','GrantBindingStatus','GrantBindingFailureCode', ...
    'DCIFieldsHash','GrantFieldsHash','DCICrcPass','Status'});
c.PDCCHReceiverTrialExecuted=1;
d=table("DL",1,1,4,"grant1","dci1",4660,true,true,"bound","",h,h,true,1,h, ...
    'VariableNames',{'Direction','ServingCell','UEIndex','Slot','GrantContextId','PDCCHGrantDCIId', ...
    'RNTI','PDCCHGrantBindingRequired','PDCCHGrantBindingOk','PDCCHGrantBindingStatus', ...
    'PDCCHGrantBindingFailureCode','PDCCHGrantDCIFieldsHash','PDCCHGrantFieldsHash','DCICrcPass','Layers', ...
    'AppliedPrecoderMatrixSHA256'});
required=struct('DL',true,'UL',false);
g=sixgr.truth.buildPDCCHGrantBindingEvidence(c,cfg,d,table(),required);
assert(g.BindingGateOk&&height(g.Rows)==1&&g.Rows.BindingStatus=="bound");
blocked=c; blocked.GrantContextId="blocked"; blocked.Status="NA";
blocked.PDCCHReceiverTrialExecuted=0; blocked.GrantBindingOk=false;
blocked.GrantBindingStatus="blocked_before_transmission"; blocked.DCICrcPass=false;
g2=sixgr.truth.buildPDCCHGrantBindingEvidence([c;blocked],cfg,d,table(),required);
assert(isequaln(g.Rows,g2.Rows),'Known unobserved admission must not become a decode.');
for fault=["hash","identity","identity_alias","missing_hash","missing_dci","crc"]
    bad=d;
    switch fault
        case "hash", bad.PDCCHGrantFieldsHash=string(repmat('b',1,64));
        case "identity", bad.UEIndex=2;
        case "identity_alias", bad.UEID=2;
        case "missing_hash", bad.PDCCHGrantDCIFieldsHash="";
        case "missing_dci", bad.PDCCHGrantDCIId="";
        case "crc", bad.DCICrcPass=false;
    end
    rejected=sixgr.truth.buildPDCCHGrantBindingEvidence(c,cfg,bad,table(),required);
    assert(~rejected.BindingGateOk&&height(rejected.Rows)==1&&rejected.Rows.BindingStatus=="failed");
end
raw=struct('DL',d,'UL',table());
sixgr.util.csvWriteTable(fullfile(root,'control','csv','pdcch_trials.csv'),[c;blocked],'PreserveSchema',true);
alias=c; alias.GrantFieldsHash=string(repmat('b',1,64));
sixgr.util.csvWriteTable(fullfile(root,'air_interface','csv','pdcch_trials.csv'),alias,'PreserveSchema',true);
out=sixgr.truth.exportCompactCausalStageEvidence(root,cfg,raw);
full=sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg,raw);
assert(isequaln(out.PrecoderEvidence,full.PrecoderEvidence));
assert(height(out.Binding.Rows)==1&&all(out.PrecoderEvidence.AppliedPrecoderMatrixSHA256==h));
assert(out.Binding.Rows.BindingStatus=="bound",'Retain canonical control-table precedence.');
unapplied=d; unapplied.AppliedPrecoderMatrixSHA256=""; unapplied.ConfiguredPMI=4;
missing=sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg,struct('DL',unapplied), ...
    'PublicationScope','precoder_only');
assert(~any(missing.PrecoderEvidence.PrecodingActive)&&all(missing.PrecoderEvidence.EvidenceType=="missing"), ...
    'Configured PMI alone cannot prove application.');
empty=sixgr.truth.buildPDCCHGrantBindingEvidence(table(),cfg,table(),table(),required);
assert(isempty(empty.Rows)&&~empty.BindingGateOk,'Configuration must not invent a received grant.');
ok=true; fprintf('COMPACT_CAUSAL_STAGE_EVIDENCE_PASS\n');
end
