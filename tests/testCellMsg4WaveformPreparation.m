function ok=testCellMsg4WaveformPreparation()
% Native Msg3 decoder -> original CCCH -> actual Msg4 sample preparation.
% Cell RAR TX and receive-clock anchors are declared planner boundaries;
% this test does not claim shared propagation or UE Setup admission.
[~,f]=testCellMsg3ReceiveAuthority();p=f.Plans{1};cfg=f.PreparedRAR.Config;
request=sixgr.mac.ra.buildNRMsg3Payload("randomValue",2^38+7,"mo-Signalling");
tx=sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg,p.RAContext,p.Grant,request);
rx=sixgr.phy.ra.receiveMsg3PUSCHPhysical(tx.Waveform,cfg,p.RAContext,p.Grant);
assert(rx.Ok,'The original native unit-channel Msg3 must decode.');
bytes=uint8(reshape(double(rx.TransportBlock),8,[]).'*(2.^(7:-1:0)).');
message=sixgr.mac.ra.parseNRInitialAccessMACPDU("UL",bytes);
received=struct('ObservationID',"declared_planner_clock_native_Msg3_decoded", ...
    'PlanSHA256',p.SHA256,'TemporaryCRNTI',p.TemporaryCRNTI,'ServingCell',p.ServingCell, ...
    'RAPID',p.RAPID,'ObservationEndSampleExclusive',p.ReceiveEndSampleExclusive, ...
    'CRCPass',rx.Ok,'SemanticAccepted',message.Valid,'Message',message, ...
    'ReceivedMACSHA256',sixgr.protocol.ProtocolHash.bytes(bytes), ...
    'OriginalReceiveSHA256',sixgr.phy.waveform.WaveformHash.numeric(tx.Waveform), ...
    'FixtureBoundary',"native_unit_channel_Msg3_with_declared_independent_receive_clock_not_shared_RF");
received.SHA256=hash(received);
[txcfg,ra,msg4,proposal]=sixgr.truth.buildCellMsg4TransmissionContext(cfg,p,received,@(~)true);
assert(proposal.ResponseSchedulable&&ra.UEId==0&&~ra.RequireRRCSetupComplete && ...
    ra.Msg4DCIReference.FrequencyReferenceSource=="original_gNB_configured_mib_coreset0" && ...
    isequal(msg4.ContentionIdentityBytes,message.ContentionIdentityBytes));
prepared=sixgr.truth.prepareCellMsg4Transmission(txcfg,ra,msg4,proposal,received);
assert(prepared.StageName=="Msg4"&&prepared.RFExecutionDeferred&&prepared.PortCount==1 && ...
    all(isfinite(prepared.PhysicalWaveform),'all')&&any(prepared.PhysicalWaveform~=0,'all') && ...
    all(string({prepared.CommonResourceReservations.Direction})=="DL") && ...
    prepared.Tx.PDSCHExecutionProfile=="ra_si_strict");
actualBytes=uint8(reshape(double(prepared.Tx.TransportBlockBits),8,[]).'*(2.^(7:-1:0)).');
parsed=sixgr.mac.ra.parseNRInitialAccessMACPDU("DL",actualBytes);
assert(parsed.ContentionIdentity==request.ContentionIdentity && ...
    parsed.RRCSetupSHA256==msg4.RRCSetupSHA256&&isnan(parsed.FinalCRNTI));
bad=received;bad.CRCPass=false;bad.SHA256=hash(rmfield(bad,'SHA256'));
reject(@()sixgr.truth.buildCellMsg4TransmissionContext(cfg,p,bad,@(~)true),'sixgr:truth:CellMsg4ReceiveAuthority');
[~,~,~,blocked]=sixgr.truth.buildCellMsg4TransmissionContext(cfg,p,received,@(~)false);
assert(~blocked.ResponseSchedulable&&isnan(blocked.Msg4Slot));
reject(@()sixgr.phy.ra.recoverMsg4Waveform([],txcfg,ra,struct(),struct()), ...
    'sixgr:phy:ra:GNBConfigurationAtUEReceiver');
owner=sixgr.truth.CoupledWaveformStream();
reject(@()owner.originalCellMsg3ReceiveReceipt(received.ObservationID),'sixgr:truth:CellMsg4ReceiveAuthority');
ok=true;fprintf('CELL_MSG4_PREPARATION_PASS native_Msg3_received=1 canonical_Msg4_samples=1 shared_RF=0 UE_Setup_admission=0\n');
end
function h=hash(v)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(v))));
end
function reject(f,id)
try,f();catch e,assert(string(e.identifier)==id,'Expected %s, got %s: %s',id,e.identifier,e.message);return;end
error('test:MissingCellMsg4Guard','Expected %s.',id);
end
