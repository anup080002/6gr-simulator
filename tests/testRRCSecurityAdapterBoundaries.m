function ok=testRRCSecurityAdapterBoundaries()
% Actual NIA2/PDCP/RLC and UPER; explicitly declared transport boundaries, RF=0.
cfg=struct('UEID',"connection-A",'BearerID',"SRB-1",'BearerType',"SRB",'SRBID',1, ...
 'QFI',0,'LCID',1,'PDCPSNBits',12,'RLCSNBits',12,'ConfigurationEpoch',1, ...
 'Direction',"UL",'CipherAlgorithm',"NEA0",'IntegrityAlgorithm',"NIA0");
c=struct('ContractVersion',"PDCP_endpoint_security/v1",'ContextID',"UL-core", ...
 'UEID',cfg.UEID,'BearerID',cfg.BearerID,'Direction',0,'ConfigurationEpoch',1, ...
 'CipherAlgorithm',"NEA0",'IntegrityAlgorithm',"128-NIA2",'CipherKey',uint8(16:31), ...
 'IntegrityKey',uint8(0:15),'SampleRateHz',1000,'ClockEpoch',1,'KeySource',"configured_preestablished_core_key");
d=c;d.Direction=1;d.ContextID="DL-core";
expected=struct('ExecutionRunID',"component-run",'ServingCell',1,'RNTI',42, ...
 'ProtocolConfigurationSHA256',sixgr.protocol.ProtocolHash.bytes(uint8(1)), ...
 'RRCTransactionID',2,'UEID',cfg.UEID,'ConfigurationEpoch',1,'SampleRateHz',1000,'ClockEpoch',1);
command=sixgr.rrc.asn1.NRAccessMessageCodec.encode('security_mode_command', ...
 struct('transaction_id',2,'ciphering_algorithm',"nea0",'integrity_algorithm',"nia2"));
r=struct('ContractVersion',"validated_RRC_security_boundary/v1",'ContextID',c.ContextID, ...
 'UEID',c.UEID,'BearerID',c.BearerID,'Direction',0,'ConfigurationEpoch',1,'Endpoint',"TX", ...
 'Purpose',"security_command_verified",'RRCTransactionID',2,'RRCPayloadSHA256',command.SHA256, ...
 'PDCPPDUSHA256',"",'OriginalObservationSHA256',command.SHA256,'AtSample',0, ...
 'SampleRateHz',1000,'ClockEpoch',1,'EvidenceBoundary',"declared_component");
ue=sixgr.protocol.ProtocolRuntime(cfg);ue.stageSecurityContext('TX',c);ue.activateTransmitIntegrity(c.ContextID,r);
complete=sixgr.rrc.asn1.NRAccessMessageCodec.encode('security_mode_complete',struct('transaction_id',2));
original=ue.transmit('complete-original',complete.Bytes,.001);
amd=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(original.Bytes,12);
submission=expected;submission.ContractVersion="declared_PDCP_to_RLC_submission/v1";
submission.BearerID=c.BearerID;submission.PDCPPDU=amd.Payload;submission.PDCPCount=0;
submission.SubmittedAtSample=1;submission.SubmissionID="declared-original-handoff";
submission.OriginalSubmissionSHA256=sixgr.protocol.ProtocolHash.bytes(original.Bytes);
before=ue.securityState();
out=sixgr.rrc.validateSubmittedSecurityComplete(submission,c,d,expected,"declared_component");
assert(isequal(out.Message.Bytes,complete.Bytes)&&out.TXReceipt.EvidenceBoundary=="declared_component"&& ...
 isequaln(before,ue.securityState())&&~out.SecurityActivated);
reject(@()sixgr.rrc.validateSubmittedSecurityComplete(submission,c,d,expected),'sixgr:rrc:SecurityCompleteSubmission');
bad=submission;bad.PDCPPDU(end)=bitxor(bad.PDCPPDU(end),uint8(1));
reject(@()sixgr.rrc.validateSubmittedSecurityComplete(bad,c,d,expected,"declared_component"),'sixgr:rrc:SecurityCompleteSubmission');
wrong=expected;wrong.RRCTransactionID=3;
reject(@()sixgr.rrc.validateSubmittedSecurityComplete(submission,c,d,wrong,"declared_component"),'sixgr:rrc:SecurityCompleteSubmission');
% Actual protected SRB reconfiguration, with explicitly declared RX boundary.
cfg.Direction="DL";cfg.IntegrityAlgorithm="128-NIA2";cfg.IntegrityKey=c.IntegrityKey;
cfg.CipherKey=c.CipherKey;cfg.SecurityActive=true;
srb=sixgr.protocol.ProtocolRuntime(cfg);
s=struct('transaction_id',2,'cell_group_id',0,'drb_id',1,'lcid',4, ...
    'pdcp',struct('sn_size_ul',"len12bits",'sn_size_dl',"len18bits", ...
        'discard_timer',"ms100",'t_reordering',"ms40",'integrity_protection',false), ...
    'sdap',struct('pdu_session',1,'qfi',9,'header_ul',"present",'header_dl',"present",'default_drb',true), ...
    'rlc_am',struct('sn_size_ul',"size12",'sn_size_dl',"size18",'t_poll_retransmit',"ms45", ...
        'poll_pdu',"p16",'poll_byte',"kB25",'max_retx_threshold',"t8", ...
        't_reassembly',"ms35",'t_status_prohibit',"ms10"), ...
    'logical_channel',struct('priority',3,'prioritised_bit_rate',"kBps8", ...
        'bucket_size_duration',"ms100",'logical_channel_group',1,'scheduling_request_id',0, ...
        'logical_channel_sr_mask',false,'logical_channel_sr_delay_timer_applied',false));

message=sixgr.rrc.asn1.NRAccessMessageCodec.encode('reconfiguration',s);
original=srb.transmit('reconfiguration-original',message.Bytes,.002);
[delivered,completions]=srb.receive(original,.003);
assert(delivered&&numel(completions)==1&&isequal(completions.Payload,message.Bytes));
amd=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(original.Bytes,12);
delivery=expected;delivery.ContractVersion="declared_authenticated_SRB1_delivery/v1";
delivery.Payload=completions.Payload;delivery.BearerID=cfg.BearerID;delivery.Direction="DL";
delivery.AvailableAtSample=3;delivery.RRCPayloadSHA256=message.SHA256;
delivery.PDCPPDUSHA256=sixgr.protocol.ProtocolHash.bytes(amd.Payload);
delivery.ObservationID="declared-protocol-reception";
delivery.OriginalObservationSHA256=sixgr.protocol.ProtocolHash.bytes(original.Bytes);
delivery.IntegrityVerified=true;delivery.CipheringActive=true;
% Pure decoded configuration checks replace received-only owner construction.
before=srb.securityState();
actual=sixgr.rrc.asn1.NRAccessMessageCodec.decode('reconfiguration',completions.Payload);
configs=sixgr.rrc.buildNewDRBProtocolConfigurations(actual,expected,d);
assert(numel(configs)==2&&configs{1}.Direction=="DL"&&configs{2}.Direction=="UL"&& ...
 configs{1}.PDCPSNBits==18&&configs{2}.PDCPSNBits==12&& ...
 configs{1}.RLCSNBits==18&&configs{2}.RLCSNBits==12&& ...
 configs{1}.DiscardTime_s==.1&&configs{1}.ReorderingTime_s==.04&& ...
 configs{1}.PollByte==25000&&configs{1}.IntegrityAlgorithm=="NIA0");
changed=actual;changed.Semantic.pdcp.sn_size_dl="len12bits";
reject(@()sixgr.rrc.buildNewDRBProtocolConfigurations(changed,expected,d),'sixgr:rrc:NewDRBInstallation');
connection=expected;connection.ConnectionReceiptSHA256=sixgr.protocol.ProtocolHash.bytes(uint8('declared-connection'));
prepared=sixgr.rrc.PendingDRBEndpoints(actual,connection,d,{});
assert(numel(prepared.snapshot())==2&&isequaln(before,srb.securityState()));
dl=prepared.directionalRuntime("DL");ul=prepared.directionalRuntime("UL");
reject(@()dl.enqueuePacket('no-original-issued-DL',uint8([1 2]),.004),'sixgr:protocol:DRBEndpointNotAdmitted');
reject(@()ul.enqueuePacket('no-original-issued-UL',uint8([1 2]),.004),'sixgr:protocol:DRBEndpointNotAdmitted');
% Production installer rejects the old received-only component call outright.
state=struct('InstalledDRBBearers',{{}});
reject(@()sixgr.rrc.installReceivedNewDRB(state,srb,delivery,expected,d,"declared_component"),'sixgr:rrc:OriginalIssuedDRBRequired');
assert(isequaln(before,srb.securityState()));
fprintf('RRC_ADAPTER_BOUNDARIES_PASS actual_NIA2_PDCP_RLC_UPER=1 boundary=declared_component RF=0 traffic_admitted=0\n');
ok=true;
end
function reject(f,id)
try,f();catch e,assert(string(e.identifier)==id,e.message);return;end
error('test:ExpectedRejection','Expected %s.',id);
end
