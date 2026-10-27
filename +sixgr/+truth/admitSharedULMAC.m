function [state,reverseEvidence]=admitSharedULMAC(state,item,prepared,harq,reverse)
% Independent decoder bytes -> same-generation received MAC state.
if nargin<5, reverse=struct(); end
reverseEvidence=struct();
policy=sixgr.util.structGet(prepared.InputConfig,'phy.mac.uplinkControl',struct('Enabled',false));
if prepared.Direction~="UL" || ~policy.Enabled
    if ~isempty(fieldnames(reverse))
        reverseEvidence=sixgr.truth.commitReceivedMACAdmissions(state.ProtocolBridge,reverse,[],struct(),[],struct());
    end
    return;
end
identity=sixgr.truth.preparedDataTransmissionIdentity(prepared,item.UE);
assert(string(harq.SharedTransmissionID)==identity.TransmissionID, ...
    'sixgr:mac:ReceiveAttemptIdentity','Original receiver attempt identity required.');
records=state.SharedDataTXLedger;
hit=cellfun(@(r)r.Identity.TransmissionID==identity.TransmissionID,records);
assert(nnz(hit)==1,'sixgr:mac:ReceiveAttemptIdentity','Require exact original transmitted attempt.');
attempt=records{find(hit,1)}; grant=attempt.Grant;
scope=grant.MACOwnerScope;
assert(isequaln(scope,state.SharedUEMACScopes{item.UE})&&scope.RNTI==identity.RNTI, ...
    'sixgr:mac:ReceivedMACGeneration','Late or foreign received MAC cannot enter current owner.');
tb=string(grant.TransportBlockId);
initial=cellfun(@(r)r.Identity.Direction=="UL"&&r.Identity.UEIndex==item.UE&& ...
    r.Identity.RNTI==scope.RNTI&&string(sixgr.util.structGet(r.Grant,'TransportBlockId',''))==tb&& ...
    ~sixgr.truth.GrantPreparation.grantIsRetransmission(r.Grant),records);
assert(nnz(initial)==1,'sixgr:mac:OriginalMACTBIdentity','Require one original new-data MAC TB owner.');
first=records{find(initial,1)};
assert(isequaln(first.Grant.MACOwnerScope,scope),'sixgr:mac:ReceivedMACGeneration','Original allocation generation differs.');
t=harq.ReceivedTimingEvidence;
assert(t.Direction=="UL"&&t.RNTI==scope.RNTI&& ...
    t.GrantContextId==identity.PHYGrantContextId&&t.SampleRateHz==scope.SampleRateHz, ...
    'sixgr:mac:ReceivedMACClock','Original received assignment and sample clock required.');
rx=struct('Scope',scope,'Direction',"UL",'CRCPass',harq.CombinedDecodeOK, ...
    'LogicalTBID',tb,'TransmissionID',identity.TransmissionID, ...
    'ReferenceGrantContextID',string(first.Grant.PHYGrantContextId), ...
    'OriginalTransmissionStartSample',first.FirstActiveSample, ...
    'ObservationEndSampleExclusive',t.ObservationEndSampleExclusive, ...
    'AvailableSample',t.ResultAvailableAtSample);
rx.ReferenceAllocation=first.Grant.PHRAllocationReference;
bits=harq.DecodedTransportBlockBits;
phr=state.SharedGNBPHRStates{item.UE}; bsr=state.SharedGNBBufferStates{item.UE};
[phCandidate,phStatus]=phr.previewAdmission(bits,rx);
if rx.CRCPass
    bytes=uint8(double(reshape(bits,8,[]).')*(2.^(7:-1:0)).');
    mac=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',bytes);
    count=0; statusCount=0; installedLCID=prepared.InputConfig.protocol.mac.lcid;
    for k=1:numel(mac.SubPDUs)
        q=mac.SubPDUs(k);
        if string(q.Kind)~="SDU", continue; end
        assert(q.LCID==installedLCID,'sixgr:mac:UninstalledReceivedLogicalChannel','Received SDU LCID is not installed.');
        if ~isempty(q.Payload)&&bitget(q.Payload(1),8)==0
            binding=state.ProtocolBridge.originalTransportApplicationBinding(tb);
            assert(isequal(sixgr.util.structGet(binding,'ControlOnly',false),true), ...
                'sixgr:mac:UnexpectedRLCControl','STATUS must use the original received reverse-control path.');
            sixgr.l2.rlc18.RLCStatusCodec.decodeReport(q.Payload,prepared.InputConfig.protocol.rlc.sn_bits);
            statusCount=statusCount+numel(q.Payload);
            continue; % Retire received L2 demand, never application/AMD bytes.
        end
        rlc=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(q.Payload,prepared.InputConfig.protocol.rlc.sn_bits);
        count=count+numel(rlc.Payload);
    end
    rx.DecodedRLCPayloadBytes=count; rx.DecodedRLCStatusBytes=statusCount; rx.DecodedMACSHA256=mac.SHA256;
end
[bsCandidate,bsStatus]=bsr.previewAdmission(bits,rx);
% Validate both independently before either receiver-owned handle mutates.
reverseEvidence=sixgr.truth.commitReceivedMACAdmissions( ...
    state.ProtocolBridge,reverse,phr,phCandidate,bsr,bsCandidate);
row=rmfield(rx,intersect(fieldnames(rx),{'DecodedRLCPayloadBytes'}));
row.PHRStatus=phStatus; row.BSRStatus=bsStatus;
row.Source="original_PUSCH_decoder_CRC_and_MAC_bytes";
state.SharedReceivedMACLedger=[sixgr.util.structGet(state,'SharedReceivedMACLedger',{});{row}];
state.SchedulerStateChanged=true;
end
