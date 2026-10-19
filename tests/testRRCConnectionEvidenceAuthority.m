function ok=testRRCConnectionEvidenceAuthority()
% Real bounded-codec bytes plus explicit state/publication fixtures; no PHY claim.
setup6GRSimToolkit('Verbose',false);
request=sixgr.mac.ra.buildMsg3Payload('UEId',7,'UEIdentity','UE-7','RRCSetupRequest',true);
decoded3=sixgr.mac.ra.parseMsg3Payload(request.PayloadBits);
setup=sixgr.mac.ra.buildMsg4ContentionResolution(decoded3.ContentionIdentity, ...
    'FinalCRNTI',4660,'RRCSetup',true,'TransactionID',2,'SRB1LCID',1);
decoded4=sixgr.mac.ra.parseMsg4ContentionResolution(setup.PayloadBits);
complete=sixgr.mac.ra.buildRRCSetupComplete('TransactionID',2,'SRB1LCID',1,'UEIdentity','UE-7');
decoded5=sixgr.mac.ra.parseRRCSetupComplete(complete.PayloadBits);
prefix="CELL_SELECTED|MSG3_RRC_SETUP_REQUEST_OK|MSG4_RRC_SETUP_OK|";
args={'ExpectedTransactionID',2,'ReceivedTransactionID',2, ...
    'UEIdentity','UE-7','ReceivedUEIdentity','UE-7', ...
    'SRB1InstalledBeforeSetupComplete',true};
r=struct('RunId',"explicit_publication_fixture",'AttemptId',1,'UEId',7, ...
    'Msg3ScheduledSlot',14,'Msg4ScheduledSlot',17,'SetupCompleteScheduledSlot',19, ...
    'Msg3PUSCHCrcPass',true,'Msg4PDSCHCrcPass',true,'RRCSetupCompleteCRC',true, ...
    'RRCSetupRequestSHA256',decoded3.RRCSetupRequestSHA256, ...
    'RRCSetupSHA256',decoded4.RRCSetupSHA256, ...
    'RRCSetupCompletePayloadSHA256',decoded5.PayloadHash, ...
    'SetupCompleteTx',struct('RRCSetupComplete',complete));
tx3=struct('Msg3',request); tx4=struct('Msg4',setup);
for terminal=["RRC_SETUP_COMPLETE_OK","UL_DCCH_CRC_FAIL","T300_EXPIRE"]
    s=sixgr.phy.ia.RRCConnectionEstablishmentStateMachine.evaluate(args{:}, ...
        'EventSequence',prefix+terminal,'SetupCompleteTransactionID',2,'SetupCompleteUEIdentity','UE-7');
    r.RRCTrace=s.Trace; r.RRCSetupCompleteCRC=terminal~="UL_DCCH_CRC_FAIL";
    r.RRCSetupCompletePayloadSHA256=decoded5.PayloadHash;
    if ~r.RRCSetupCompleteCRC, r.RRCSetupCompletePayloadSHA256=""; end
    T=sixgr.phy.ra.buildRRCConnectionEvidence(r,tx3,tx4);
    assert(height(T)==8 && all(~T.SRB1Installed(T.EventOrdinal<3)) && ...
        all(T.SRB1Installed(T.EventOrdinal>=3)) && all(~T.SRB1InstalledBefore(T.EventOrdinal<=3)));
    assert(all(isnan(T.TransactionID(T.EventOrdinal<3))) && all(T.TransactionID(T.EventOrdinal>=3)==2));
    cellSelected=T.Event=="CELL_SELECTED";
    assert(all(T.MessageSHA256(cellSelected)=="") && all(isnan(T.CRC(cellSelected))) && ...
        all(~T.CRCApplicable(cellSelected)) && all(T.TimerName(cellSelected)==""));
    assert(all(isnan(T.CRC(~T.CRCApplicable))) && all(~T.MACRRCStandardsQualified));
    for event=["MSG3_RRC_SETUP_REQUEST_OK","MSG4_RRC_SETUP_OK"]
        rows=T(T.Event==event,:);
        assert(sum(rows.CRCApplicable)==1 && all(rows.Slot1Based==rows.AbsoluteSlot0Based+1));
        assert(rows.MessageSHA256(1)==rows.MessageSHA256(2));
    end
    if terminal=="UL_DCCH_CRC_FAIL"
        rx=T(T.EventOrdinal==4 & T.Endpoint=="GNB",:);
        tx=T(T.EventOrdinal==4 & T.Endpoint=="UE",:);
        assert(rx.CRCApplicable && rx.CRC==0 && rx.MessageSHA256=="" && rx.Status=="FAIL");
        assert(~tx.CRCApplicable && isnan(tx.CRC) && tx.MessageSHA256==complete.PayloadHash);
    elseif terminal=="T300_EXPIRE"
        timed=T(T.EventOrdinal==4,:);
        assert(all(isnan(timed.CRC)) && all(timed.MessageSHA256=="") && all(timed.TimerName=="T300"));
    end
    % Neither a terminal-state flag nor a configured transaction can rewrite history.
    poisoned=r; poisoned.SRB1Installed=false; poisoned.RRCTransactionID=1;
    assert(isequaln(T,sixgr.phy.ra.buildRRCConnectionEvidence(poisoned,tx3,tx4)));
end
% Actual payload bytes can pass CRC while semantic identity is rejected.
s=sixgr.phy.ia.RRCConnectionEstablishmentStateMachine.evaluate(args{:}, ...
    'EventSequence',prefix+"RRC_SETUP_COMPLETE_OK", ...
    'SetupCompleteTransactionID',0,'SetupCompleteUEIdentity','UE-7');
r.RRCTrace=s.Trace; r.RRCSetupCompleteCRC=true; r.RRCSetupCompletePayloadSHA256=decoded5.PayloadHash;
T=sixgr.phy.ra.buildRRCConnectionEvidence(r,tx3,tx4);
rx=T(T.EventOrdinal==4 & T.Endpoint=="GNB",:);
assert(rx.CRC==1 && rx.Status=="FAIL" && rx.MessageSHA256==decoded5.PayloadHash);
bad=r; bad.RRCSetupCompletePayloadSHA256="";
reject(@()sixgr.phy.ra.buildRRCConnectionEvidence(bad,tx3,tx4),'sixgr:phy:ra:MissingRRCMessageHash');
bad=r; bad.RRCTrace=removevars(bad.RRCTrace,'SRB1InstalledAfter');
reject(@()sixgr.phy.ra.buildRRCConnectionEvidence(bad,tx3,tx4),'sixgr:phy:ra:MissingRRCHistoricalState');
fprintf('RRC_CONNECTION_EVIDENCE_AUTHORITY_PASS history_and_CRC_and_message_hashes=1\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch failure, assert(string(failure.identifier)==id); return; end
error('test:MissingExpectedError','Expected %s.',id);
end
