function T=buildRRCConnectionEvidence(r,msg3Tx,msg4Tx)
% Replayed protocol milestones backed by the same RA attempt's PHY results.
% This bounded state owner is not a qualified TS 38.331 ASN.1/RRC stack.
template=struct('AttemptID',"",'Endpoint',"",'EventOrdinal',NaN, ...
    'PreviousState',"",'Event',"",'NextState',"",'TransactionID',NaN, ...
    'UEIdentity',"",'SRB1Installed',false,'SRB1InstalledBefore',false, ...
    'MessageSHA256',"",'MessageEvidenceRole',"",'CRC',NaN,'CRCApplicable',false, ...
    'CRCSource',"",'AbsoluteSlot0Based',NaN,'Slot1Based',NaN, ...
    'TimerName',"",'FailureReason',"",'Status',"", ...
    'StatusScope',"bounded_protocol_transition_not_PHY_CRC", ...
    'EvidenceScope',"same_attempt_PHY_outcomes_replayed_through_bounded_RRC_state_owner", ...
    'MACRRCStandardsQualified',false);
rows=repmat(template,0,1);
trace=r.RRCTrace;
if isempty(trace), T=struct2table(rows,'AsArray',true); return; end
assert(istable(trace) && all(ismember({'SRB1InstalledBefore','SRB1InstalledAfter', ...
    'UETransactionID','GNBTransactionID'},trace.Properties.VariableNames)), ...
    'sixgr:phy:ra:MissingRRCHistoricalState','RRC events require their own state-owner snapshots.');
for i=1:height(trace)
    event=string(trace.Event(i));
    for endpoint=["UE","GNB"]
        row=template; row.AttemptID=string(r.RunId)+"-A"+string(r.AttemptId);
        row.Endpoint=endpoint; row.EventOrdinal=double(trace.Ordinal(i)); row.Event=event;
        row.PreviousState=string(trace.(endpoint+"StateBefore")(i));
        row.NextState=string(trace.(endpoint+"StateAfter")(i));
        row.TransactionID=double(trace.(endpoint+"TransactionID")(i));
        row.UEIdentity="UE-"+string(round(double(r.UEId)));
        row.SRB1InstalledBefore=logical(trace.SRB1InstalledBefore(i));
        row.SRB1Installed=logical(trace.SRB1InstalledAfter(i));
        row.FailureReason=string(trace.ErrorIdentifier(i));
        row.Status="PASS";
        if strlength(row.FailureReason)>0, row.Status="FAIL"; end
        if event=="T300_EXPIRE", row.TimerName="T300"; end
        receiver=""; txHash=""; rxHash=""; crc=NaN; crcField=""; slot=NaN;
        if event=="MSG3_RRC_SETUP_REQUEST_OK" || ...
                (event=="UL_DCCH_CRC_FAIL" && trace.UEStateBefore(i)=="CAMPED")
            receiver="GNB"; crcField="Msg3PUSCHCrcPass"; slot=r.Msg3ScheduledSlot;
            txHash=string(sixgr.util.structGet(msg3Tx,'Msg3.RRCSetupRequestSHA256',""));
            rxHash=string(r.RRCSetupRequestSHA256); crc=r.Msg3PUSCHCrcPass;
        elseif event=="MSG4_RRC_SETUP_OK"
            receiver="UE"; crcField="Msg4PDSCHCrcPass"; slot=r.Msg4ScheduledSlot;
            txHash=string(sixgr.util.structGet(msg4Tx,'Msg4.RRCSetupSHA256',""));
            rxHash=string(r.RRCSetupSHA256); crc=r.Msg4PDSCHCrcPass;
        elseif event=="RRC_SETUP_COMPLETE_OK" || ...
                (event=="UL_DCCH_CRC_FAIL" && trace.UEStateBefore(i)=="WAIT_SETUP_COMPLETE")
            receiver="GNB"; crcField="RRCSetupCompleteCRC"; slot=r.SetupCompleteScheduledSlot;
            txHash=string(sixgr.util.structGet(r,'SetupCompleteTx.RRCSetupComplete.PayloadHash',""));
            rxHash=string(r.RRCSetupCompletePayloadSHA256); crc=r.RRCSetupCompleteCRC;
        end
        if strlength(receiver)>0
            validateattributes(slot,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            row.AbsoluteSlot0Based=double(slot); row.Slot1Based=double(slot)+1;
            if endpoint==receiver
                assert(isscalar(crc) && any(double(crc)==[0 1]), ...
                    'sixgr:phy:ra:MissingRRCPhysicalCRC','Retain the actual receiver CRC decision.');
                row.CRCApplicable=true; row.CRC=double(crc); row.CRCSource=crcField;
                if crc
                    row.MessageSHA256=rxHash; row.MessageEvidenceRole="crc_valid_receiver_decoded_message";
                else
                    assert(strlength(rxHash)==0,'sixgr:phy:ra:FailedRRCDecodeHasMessageHash', ...
                        'A failed CRC must not inherit the transmitted message hash.');
                    row.MessageEvidenceRole="no_decoded_RRC_message_after_CRC_failure";
                end
            else
                row.MessageSHA256=txHash; row.MessageEvidenceRole="transmitted_message_not_received_evidence";
            end
            if ~row.CRCApplicable || row.CRC==1
                assert(~isempty(regexp(char(row.MessageSHA256),'^[0-9a-fA-F]{64}$','once')), ...
                    'sixgr:phy:ra:MissingRRCMessageHash','Hash actual message bytes, never an event name.');
            end
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
end
T=struct2table(rows,'AsArray',true);
end
