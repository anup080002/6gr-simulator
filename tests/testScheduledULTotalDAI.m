function ok=testScheduledULTotalDAI(outputRoot)
% Declared scheduling-ledger cases -> real UL DCI encode/decode.
% Not a shared access/data/UCI execution qualification.
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve earlier evidence.');
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_received_ul_harq_shared_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
% Retain an actual shared SRS/PUSCH grant. A generic calibration request
% cannot manufacture its two-port SRS authority or invent a TPMI.
donorPath='docs/lls/evidence_20260913/received_ul_harq_slot_10.mat';
donor=load(donorPath,'HARQEvidence');
grant=donor.HARQEvidence.GrantSnapshot;
assert(grant.PHYGrant.IsFrozen && grant.TimingDecision.Valid);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,grant.ControlAbsoluteSlot+1);
dataSlot=grant.TimingDecision.DataAbsoluteSlot;
assert(grant.ControlAbsoluteSlot==8 && dataSlot==9);
mkdir(outputRoot); rows=table();
for count=0:8
    ledger=struct();
    for k=1:count
        a=struct('GrantID',"declared-dl-"+k,'RNTI',grant.RNTI, ...
            'PhysicalServingCell',grant.ServingCell, ...
            'ScheduledCCID',string(grant.TimingDecision.ScheduledCCID), ...
            'FeedbackAbsoluteSlot',dataSlot,'ControlAbsoluteSlot',k-1,'ControlStartSymbol',0, ...
            'ConfigurationEpoch',cfg.phy.pdcch.operatorControl.connected_dci.configuration_epoch);
        [ledger,~]=sixgr.truth.nextScheduledType2DAI(ledger,a);
    end
    before=ledger;
    fixed=sixgr.truth.prepareScheduledULDAI(ledger,cfg,grant);
    assert(isequaln(before,ledger) && isequaln(fixed.PHYGrant,grant.PHYGrant) && ...
        isequaln(fixed.TimingDecision,grant.TimingDecision) && fixed.TBSBits==grant.TBSBits && ...
        fixed.DAI==mod(count-1,4) && fixed.ULTotalDAIAuthority.ScheduledDLAssignmentCount==count);
    original=sixgr.phy.pdcch.decodeDCIPayload(grant.DCI.Bits,'0_1',grant.DCI.ContextData);
    parsed=sixgr.phy.pdcch.decodeDCIPayload(fixed.DCI.Bits,'0_1',fixed.DCI.ContextData);
    for field=string(fieldnames(original.Fields)).'
        if field=="first_dai", continue; end
        assert(isequaln(original.Fields.(field),parsed.Fields.(field)),'Unrelated field changed: %s',field);
    end
    same=sixgr.truth.prepareScheduledULDAI(ledger,cfg,fixed);
    assert(isequaln(same,fixed));
    poison=grant; poison.DAI=mod(fixed.DAI+1,4); poison.ExpectedAck=true;
    poison.ControlDecodeOk=false; poison.UEReceivedAssignmentCount=99;
    same=sixgr.truth.prepareScheduledULDAI(ledger,cfg,poison);
    assert(isequal(same.DCI.Bits,fixed.DCI.Bits) && ...
        same.ULTotalDAIAuthority.Digest==fixed.ULTotalDAIAuthority.Digest);
    p=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',fixed.DCI.Bits,'RNTI',fixed.RNTI);
    [control,info]=sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,cfg,'SampleRate_Hz',p.SampleRateHz);
    received=sixgr.phy.pdcch.materializeConnectedDCI(control,info,cfg);
    assert(received.Fields.first_dai==fixed.DAI && received.DataAbsoluteSlot==dataSlot);
    none=sixgr.phy.pucch.HARQACKCodebookBuilder.buildForPUSCH(cfg,received,struct([]));
    expected=mod(count,4);
    assert(numel(none.Bits)==expected && ~any(none.Bits) && isempty(none.Events));
    if count>0
        bad=ledger; bad.Entries(1).Assignment.RNTI=bad.Entries(1).Assignment.RNTI+1;
        localReject(@()sixgr.truth.prepareScheduledULDAI(bad,cfg,grant),'sixgr:truth:InvalidDAILedger');
        bad=ledger; bad.LastControlAbsoluteSlot=grant.ControlAbsoluteSlot+1;
        localReject(@()sixgr.truth.prepareScheduledULDAI(bad,cfg,grant),'sixgr:truth:FutureScheduledULDAI');
        bad=ledger; bad.Entries(1).Ordinal=99;
        localReject(@()sixgr.truth.prepareScheduledULDAI(bad,cfg,grant),'sixgr:truth:InvalidDAILedger');
    end
    save(fullfile(outputRoot,sprintf('scheduled_ul_dai_%d.mat',count)), ...
        'donorPath','ledger','fixed','control','info','received','none');
    rows=[rows;table(count,fixed.DAI,string(received.AssignmentDigest), ...
        'VariableNames',{'DeclaredDLScheduleCount','ReceivedRawULTotalDAI','ReceivedAssignmentDigest'})]; %#ok<AGROW>
end
runtime=fileread(fullfile('+sixgr','+truth','runWaveformLinkBundle.m'));
assert(contains(runtime,'grant=sixgr.truth.prepareScheduledULDAI(candidateDAILedger,cfgU,grant);'), ...
    'Finalization must be wired before actual production PDCCH preparation.');
writetable(rows,fullfile(outputRoot,'scheduled_ul_dai.csv'));
fprintf('SCHEDULED_UL_TOTAL_DAI_PASS actual_UL_DCI_receptions=9 declared_schedule_counts=0:8 guards=24 folder=%s\n',outputRoot);
ok=true;
end

function localReject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return; end
error('test:MissingRejection','Expected %s',id);
end
