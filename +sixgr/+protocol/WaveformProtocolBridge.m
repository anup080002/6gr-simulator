classdef WaveformProtocolBridge < handle
    %WAVEFORMPROTOCOLBRIDGE Bind strict protocol PDUs to waveform TB bytes.
    %
    % This object is coordinator-owned.  It is intentionally excluded from
    % parfor payloads: protocol sequence numbers and lineage are serialized
    % state, while the finalized transport-block bits are immutable worker
    % inputs.

    properties (SetAccess = private)
        Enabled (1,1) logical = false
        NumUEs (1,1) double = 0
        Configuration (1,1) struct
        OriginalRRCRequired (1,1) logical = false
    end

    properties (Access = private)
        TxRuntimes cell
        RxRuntimes cell
        Pending containers.Map
        Delivered containers.Map
        Decoded containers.Map
        CompletedPayloads containers.Map
        ReleasedEvidence containers.Map
        QueuedOriginalPayloads containers.Map
        ControlTransports containers.Map
        DiscardReceipts containers.Map
    end

    methods
        function obj = WaveformProtocolBridge(protocolConfig, numUEs)
            arguments
                protocolConfig (1,1) struct
                numUEs (1,1) double {mustBeInteger,mustBeNonnegative}
            end
            obj.Configuration = protocolConfig;
            obj.NumUEs = numUEs;
            authority=string(sixgr.util.structGet(protocolConfig,"mac.bearer_configuration_authority","explicit_preconfigured_bounded_DRB"));
            assert(isscalar(authority)&&any(authority==["explicit_preconfigured_bounded_DRB","original_received_RRC"]), ...
                'sixgr:protocol:DRBConfigurationAuthority','Unsupported bearer configuration authority.');
            obj.OriginalRRCRequired=authority=="original_received_RRC";
            obj.Enabled = logical(sixgr.util.structGet(protocolConfig, "enabled", false)) && ...
                logical(sixgr.util.structGet(protocolConfig, "strict", false));
            obj.TxRuntimes = cell(numUEs, 2);
            obj.RxRuntimes = cell(numUEs, 2);
            obj.Pending = containers.Map('KeyType','char','ValueType','any');
            obj.Delivered = containers.Map('KeyType','char','ValueType','logical');
            obj.Decoded = containers.Map('KeyType','char','ValueType','any');
            obj.CompletedPayloads = containers.Map('KeyType','char','ValueType','any');
            obj.ReleasedEvidence = containers.Map('KeyType','char','ValueType','any');
            obj.QueuedOriginalPayloads=containers.Map('KeyType','char','ValueType','any');
            obj.ControlTransports=containers.Map('KeyType','char','ValueType','any');
            obj.DiscardReceipts=containers.Map('KeyType','char','ValueType','any');
        end

        function validateOriginalDRBBankAvailable(obj,ue,dl,ul)
            obj.requireEnabled();obj.requireUE(ue);
            assert(obj.OriginalRRCRequired&&isa(dl,'sixgr.protocol.ProtocolRuntime')&& ...
                isa(ul,'sixgr.protocol.ProtocolRuntime'),'sixgr:protocol:DRBConnectionScope', ...
                'Original paired DRB owners are required before bridge installation.');
            owners={dl,ul};
            for k=1:2
                old=obj.TxRuntimes{ue,k};oldRX=obj.RxRuntimes{ue,k};owner=owners{k};
                assert((isempty(old)&&isempty(oldRX))|| ...
                    (~isempty(old)&&~isempty(oldRX)&&old==owner&&oldRX==owner), ...
                    'sixgr:protocol:DRBAlreadyInstalled','A different original bearer cannot replace an active bridge owner.');
            end
        end

        function validateOriginalDRBPair(obj,ue,dl,ul,connection)
            obj.requireEnabled();obj.requireUE(ue);
            id='sixgr:protocol:DRBConnectionScope';
            assert(obj.OriginalRRCRequired&&isa(dl,'sixgr.protocol.ProtocolRuntime')&& ...
                isa(ul,'sixgr.protocol.ProtocolRuntime')&&isstruct(connection)&&isscalar(connection), ...
                id,'Original received-RRC mode and the original issued paired Runtime handles are required.');
            obj.validateOriginalDRBBankAvailable(ue,dl,ul);
            owners={dl,ul};directions=["DL","UL"];
            fields={'ExecutionRunID','UEID','ServingCell','RNTI','ConfigurationEpoch','ClockEpoch','SampleRateHz'};
            assert(all(isfield(connection,[fields,{'ConnectionReceiptSHA256'}])),id,'The complete original connection identity is required.');
            assert(ul.endpointAdmissionState().RXEnabled,id,'The gNB must have issued this original DRB configuration.');
            for k=1:2
                owner=owners{k};scope=owner.endpointAdmissionScope();state=owner.endpointAdmissionState();
                assert(state.Mode=="original_reconfiguration_required"&&owner.Direction==directions(k)&& ...
                    owner.BearerType=="DRB"&&all(isfield(scope,fields)),id,'Original directional DRB scope required.');
                for j=1:numel(fields)
                    assert(isequaln(scope.(fields{j}),connection.(fields{j})),id,'DRB belongs to a different original connection.');
                end
                issued=owner.originalIssuedReconfigurationReceipt();
                assert(isequaln(issued.ConnectionReceiptSHA256,connection.ConnectionReceiptSHA256), ...
                    id,'Original issued connection receipt differs.');
            end
            a=dl.endpointAdmissionScope();b=ul.endpointAdmissionScope();
            assert(a.DRBID==b.DRBID&&a.LCID==b.LCID&&a.BearerID==b.BearerID, ...
                id,'The directional handles must belong to the same issued bearer.');
            dlIssued=dl.originalIssuedReconfigurationReceipt();ulIssued=ul.originalIssuedReconfigurationReceipt();
            shared={'RRCTransactionID','RRCReconfigurationSHA256','ProtectedPDCPPDUSHA256', ...
                'TransmitComponentID','TransmitEnqueueReceiptSHA256','OriginalComponentSampleSHA256', ...
                'TransmitObservationSHA256','PhysicalTransmissionReceiptSHA256', ...
                'SecurityContextID','TransmitStartSample','TransmitEndSampleExclusive','IssuedAtSample'};
            for k=1:numel(shared)
                assert(isequaln(dlIssued.(shared{k}),ulIssued.(shared{k})),id, ...
                    'Directional bearers must share the same original issued protected RRC transmission.');
            end
        end

        function installOriginalDRBPair(obj,ue,dl,ul,connection)
            obj.validateOriginalDRBPair(ue,dl,ul,connection);
            obj.TxRuntimes(ue,:)={dl,ul};obj.RxRuntimes(ue,:)={dl,ul};
        end

        function admitted=endpointAdmitted(obj,ue,direction,endpoint)
            obj.requireEnabled();obj.requireUE(ue);direction=obj.normalizeDirection(direction);
            endpoint=string(endpoint);assert(any(endpoint==["TX","RX"]), ...
                'sixgr:protocol:DRBEndpoint','TX or RX endpoint required.');
            if ~obj.OriginalRRCRequired,admitted=true;return;end
            owner=obj.TxRuntimes{ue,1+double(direction=="UL")};
            if isempty(owner),admitted=false;return;end
            state=owner.endpointAdmissionState();admitted=state.(endpoint+"Enabled");
        end

        function validateApplicationMapping(obj,ue,direction,qfi,pduSessionID)
            obj.requireEnabled();obj.requireUE(ue);direction=obj.normalizeDirection(direction);
            owner=obj.runtime(ue,direction,"TX");id='sixgr:protocol:ApplicationBearerMapping';
            assert(isnumeric(qfi)&&isscalar(qfi)&&isfinite(qfi)&&qfi==fix(qfi)&&qfi>=0&&qfi<=63&& ...
                isnumeric(pduSessionID)&&isscalar(pduSessionID)&&isfinite(pduSessionID)&& ...
                pduSessionID==fix(pduSessionID)&&pduSessionID>=1&&pduSessionID<=255&& ...
                qfi==owner.QFI&&pduSessionID==owner.PduSessionID,id, ...
                'The original offered flow must match the installed QFI and PDU session; implicit remapping is unsupported.');
        end

        function validateOriginalApplicationClock(obj,ue,direction,sample,fs,epoch)
            obj.requireEnabled();obj.requireUE(ue);direction=obj.normalizeDirection(direction);
            owner=obj.runtime(ue,direction,"TX");scope=owner.endpointAdmissionScope();
            state=owner.endpointAdmissionState();id='sixgr:protocol:OriginalAdmissionClock';
            assert(obj.OriginalRRCRequired&&isnumeric(sample)&&isreal(sample)&&isscalar(sample)&& ...
                isfinite(sample)&&sample>=0&&sample==fix(sample)&& ...
                isequaln(fs,scope.SampleRateHz)&&isequaln(epoch,scope.ClockEpoch)&& ...
                sample>=round(state.LastRuntimeTime_s*fs),id, ...
                'Application admission must use the original bearer execution sample rate, epoch and current sample.');
        end

        function [bits,e]=prepareMACOnlyTransportBlock(obj,ue,id,tbsBits,authority)
            obj.requireEnabled(); obj.requireUE(ue); key=char(string(id));
            validateattributes(tbsBits,{'numeric'},{'scalar','real','finite','integer','positive'});
            assert(mod(tbsBits,8)==0&&~isKey(obj.Pending,key)&&~isKey(obj.ControlTransports,key), ...
                'sixgr:protocol:DuplicateTransportBlockBinding','Original new byte-aligned MAC TB required.');
            assert(authority.Stage=="original_received_DCI_empty_UE_L2"&&authority.UEIndex==ue&& ...
                authority.TBSBits==tbsBits&&strlength(string(authority.AssignmentDigest))==64, ...
                'sixgr:protocol:MACOnlyAuthority','Original received assignment and unchanged TBS required.');
            assert(obj.pendingTransmitBytes(ue,'UL').TotalBSRBytes==0, ...
                'sixgr:protocol:MACOnlyWithData','Do not replace original eligible L2 bytes with padding.');
            runtime=obj.runtime(ue,"UL","TX");
            mac=sixgr.l2.mac.MACPDUAssembler.assemble('UL',struct([]),tbsBits/8);
            p=struct('TBID',string(id),'UEIndex',ue,'UEID',runtime.UEID,'BearerID',runtime.BearerID, ...
                'Direction',"UL",'DataDirection',"",'ConfigurationEpoch',runtime.ConfigurationEpoch, ...
                'TransportKind',"MAC_CE_PADDING",'ControlOnly',true,'ApplicationPayloadBytes',0, ...
                'ApplicationOffsetBytes',0,'SegmentPayloadBytes',0,'TransportBlockBits',tbsBits, ...
                'LCID',NaN,'MACSHA256',mac.SHA256,'EncodedSHA256',"",'PayloadBytes',0, ...
                'ProtocolFragmentId',string(id),'ReservedControlSubPDUBytes',tbsBits/8, ...
                'Bytes',uint8([]),'Preparation',struct(),'MACBytes',mac.Bytes, ...
                'QueueCommitted',false,'Received',false,'ReceivedGrantAuthority',authority);
            obj.ControlTransports(key)=p;bits=localBytesToBits(mac.Bytes);
            e=obj.originalTransportApplicationBinding(id);e.PayloadBits=0;
        end
        function bytes=pendingReverseStatusBytes(obj,ue,direction)
            obj.requireEnabled(); obj.requireUE(ue); direction=obj.normalizeDirection(direction);
            bytes=0;
            if ~obj.OriginalRRCRequired&&~logical(sixgr.util.structGet(obj.Configuration,'rlc.arq_enabled',false)), return; end
            dataDirection="DL"; if direction=="DL", dataDirection="UL"; end
            runtime=obj.TxRuntimes{ue,1+double(dataDirection=="UL")};
            if isempty(runtime), return; end % No original data bearer has received anything in this direction.
            bytes=runtime.pendingReverseStatusBytes();
        end
        function [bits,e]=prepareReverseStatusTransportBlock(obj,ue,direction,id,tbsBits,time,reserved)
            if nargin<7, reserved=0; end
            validateattributes(reserved,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            obj.requireEnabled(); obj.requireUE(ue); direction=obj.normalizeDirection(direction);
            validateattributes(tbsBits,{'numeric'},{'scalar','real','finite','integer','positive'});
            key=char(string(id));
            assert(strlength(string(id))>0&&mod(tbsBits,8)==0&&~isKey(obj.Pending,key)&&~isKey(obj.ControlTransports,key), ...
                'sixgr:protocol:DuplicateTransportBlockBinding','Require a new original byte-aligned control TB.');
            dataDirection="DL"; if direction=="DL", dataDirection="UL"; end
            runtime=obj.runtime(ue,dataDirection,"TX");
            budget=tbsBits/8-reserved-3; if budget<=254, budget=budget+1; end
            assert(budget>=3,'sixgr:protocol:MACPDUCapacityExceeded','STATUS and MAC subheader must fit.');
            preparation=runtime.prepareReverseStatus(budget,time);
            assert(~isempty(fieldnames(preparation)),'sixgr:protocol:NoPendingReverseStatus','No original triggered STATUS fits this grant.');
            assert(bitget(preparation.Bytes(1),8)==0,'sixgr:protocol:ReverseStatusDC','STATUS requires RLC D/C=0.');
            item=struct('LCID',runtime.LCID,'Payload',preparation.Bytes,'OwnerID',"STATUS-"+string(id));
            mac=sixgr.l2.mac.MACPDUAssembler.assemble(direction,item,tbsBits/8);
            p=struct('TBID',string(id),'UEIndex',ue,'UEID',runtime.UEID,'BearerID',runtime.BearerID, ...
                'Direction',direction,'DataDirection',dataDirection,'ConfigurationEpoch',runtime.ConfigurationEpoch, ...
                'LCID',runtime.LCID,'TransportBlockBits',tbsBits,'ApplicationPayloadBytes',0, ...
                'ApplicationOffsetBytes',0,'ControlOnly',true,'MACSHA256',mac.SHA256, ...
                'EncodedSHA256',sixgr.protocol.ProtocolHash.bytes(preparation.Bytes), ...
                'Preparation',preparation,'MACBytes',mac.Bytes,'QueueCommitted',false,'Received',false);
            p.TransportKind="RLC_STATUS"; p.Bytes=preparation.Bytes; p.PayloadBytes=0; p.ProtocolFragmentId=string(id);
            p.ReservedControlSubPDUBytes=reserved; p.SegmentPayloadBytes=numel(preparation.Bytes);
            obj.ControlTransports(key)=p; bits=localBytesToBits(mac.Bytes);
            e=obj.originalTransportApplicationBinding(id); e.PayloadBits=0;
        end
        function evidence=receiveReverseStatusDecoded(obj,id,bits,crcPassed,time)
            candidate=obj.previewReverseStatusDecoded(id,bits,crcPassed,time);
            evidence=obj.commitReceivedReverseStatus(candidate);
        end
        function candidate=previewReverseStatusDecoded(obj,id,bits,crcPassed,time)
            assert(obj.ControlTransports(char(string(id))).TransportKind=="RLC_STATUS", ...
                'sixgr:protocol:ReverseStatusDC','A MAC-only TB is not RLC STATUS.');
            candidate=obj.previewMACControlDecoded(id,bits,crcPassed,time);
        end
        function candidate=previewMACControlDecoded(obj,id,bits,crcPassed,time)
            obj.requireEnabled(); key=char(string(id));
            assert(isKey(obj.ControlTransports,key),'sixgr:protocol:MissingTransportBlockBinding','Original reverse MAC owner required.');
            p=obj.ControlTransports(key);
            assert(islogical(crcPassed)&&isscalar(crcPassed),'sixgr:protocol:ReverseStatusCRC','Explicit decoder CRC outcome required.');
            assert(p.QueueCommitted,'sixgr:protocol:DecodeBeforeOriginalTX','Original STATUS must have transmitted.');
            evidence=struct('ControlOnly',true,'ApplicationPayloadBytes',0,'TransportBlockId',string(id), ...
                'Status',"crc_failed_no_STATUS_admission",'CompletedTransportBlocks',struct([]));
            candidate=struct('TransportBlockId',string(id),'MACSHA256',p.MACSHA256, ...
                'BaseReceived',p.Received,'RuntimeToken',struct(),'Admit',false,'MarkReceived',false,'Evidence',evidence);
            if ~crcPassed, candidate.SHA256=sixgr.l2.mac.MACHash.of(candidate); return; end
            bytes=localBitsToBytes(bits,p.TransportBlockBits);
            assert(sixgr.l2.mac.MACHash.of(bytes)==p.MACSHA256,'sixgr:protocol:DecodedTransportBlockMismatch','Original decoded MAC bytes differ.');
            mac=sixgr.l2.mac.MACPDUDemultiplexer.decode(p.Direction,bytes);
            sdu=find(string({mac.SubPDUs.Kind})=="SDU");
            if p.TransportKind=="MAC_CE_PADDING"
                assert(isempty(sdu),'sixgr:protocol:MACOnlyUnexpectedSDU','MAC-only binding cannot decode an invented RLC SDU.');
                candidate.Evidence.Status="original_crc_confirmed_MAC_CE_PADDING";
                if p.Received, candidate.Evidence.Status="duplicate_MAC_control_no_state_update"; end
                candidate.MarkReceived=~p.Received;
                candidate.SHA256=sixgr.l2.mac.MACHash.of(candidate); return;
            end
            assert(isscalar(sdu)&&mac.SubPDUs(sdu).LCID==p.LCID, ...
                'sixgr:protocol:ReverseStatusLCID','Require exactly the installed bearer STATUS SDU.');
            decoded=mac.SubPDUs(sdu).Payload;
            assert(~isempty(decoded)&&bitget(decoded(1),8)==0&&sixgr.protocol.ProtocolHash.bytes(decoded)==p.EncodedSHA256, ...
                'sixgr:protocol:ReverseStatusDC','Original received RLC STATUS bytes and D/C required.');
            if p.Received
                candidate.Evidence.Status="duplicate_STATUS_no_state_update";
                candidate.SHA256=sixgr.l2.mac.MACHash.of(candidate); return;
            end
            runtime=obj.runtime(p.UEIndex,p.DataDirection,"TX");
            candidate.RuntimeToken=runtime.previewReceivedStatus(reshape(decoded,1,[]),string(id),time);
            candidate.Admit=true; candidate.MarkReceived=true;
            evidence.Status="original_crc_confirmed_reverse_STATUS";
            evidence.DecodedMACSHA256=p.MACSHA256; evidence.DecodedRLC_SHA256=p.EncodedSHA256;
            candidate.Evidence=evidence; candidate.SHA256=sixgr.l2.mac.MACHash.of(candidate);
        end
        function validateReceivedReverseStatus(obj,candidate)
            key=char(candidate.TransportBlockId);
            assert(isKey(obj.ControlTransports,key)&&candidate.SHA256==sixgr.l2.mac.MACHash.of(rmfield(candidate,'SHA256')), ...
                'sixgr:protocol:ReverseStatusAdmissionConflict','Original STATUS candidate required.');
            p=obj.ControlTransports(key);
            assert(p.QueueCommitted&&p.MACSHA256==candidate.MACSHA256&&p.Received==candidate.BaseReceived, ...
                'sixgr:protocol:ReverseStatusAdmissionConflict','Original received STATUS state changed.');
            if candidate.Admit
                runtime=obj.runtime(p.UEIndex,p.DataDirection,"TX");
                runtime.validateReceivedStatus(candidate.RuntimeToken);
            end
        end
        function validateMACControlAdmission(obj,candidate)
            obj.validateReceivedReverseStatus(candidate);
        end
        function evidence=commitMACControlAdmission(obj,candidate)
            evidence=obj.commitReceivedReverseStatus(candidate);
        end
        function cancelMACControlAdmission(obj,candidate)
            obj.cancelReceivedReverseStatus(candidate);
        end
        function evidence=commitReceivedReverseStatus(obj,candidate)
            obj.validateReceivedReverseStatus(candidate); evidence=candidate.Evidence;
            if ~candidate.Admit
                if candidate.MarkReceived
                    key=char(candidate.TransportBlockId); p=obj.ControlTransports(key);p.Received=true;obj.ControlTransports(key)=p;
                end
                return;
            end
            key=char(candidate.TransportBlockId); p=obj.ControlTransports(key);
            runtime=obj.runtime(p.UEIndex,p.DataDirection,"TX");
            evidence.Disposition=runtime.commitReceivedStatus(candidate.RuntimeToken);
            p.Received=true; obj.ControlTransports(key)=p;
        end
        function cancelReceivedReverseStatus(obj,candidate)
            key=char(candidate.TransportBlockId);
            assert(isKey(obj.ControlTransports,key)&&candidate.SHA256==sixgr.l2.mac.MACHash.of(rmfield(candidate,'SHA256')), ...
                'sixgr:protocol:ReverseStatusAdmissionConflict','Original STATUS preview required.');
            if ~candidate.Admit, return; end
            p=obj.ControlTransports(key); runtime=obj.runtime(p.UEIndex,p.DataDirection,"TX");
            runtime.cancelReceivedStatus(candidate.RuntimeToken);
        end
        function packet=enqueuePacket(obj,ue,direction,id,payload,time)
            obj.requireEnabled(); obj.requireUE(ue); direction=obj.normalizeDirection(direction);
            runtime=obj.runtime(ue,direction,"TX");
            packet=runtime.enqueuePacket(string(id),reshape(payload,1,[]),time);
            key=char(string(ue)+"|"+direction+"|"+string(id));
            if isKey(obj.QueuedOriginalPayloads,key)
                assert(isequal(obj.QueuedOriginalPayloads(key),reshape(payload,1,[])), ...
                    'sixgr:protocol:LineageViolation','Original queued packet bytes changed.');
            else, obj.QueuedOriginalPayloads(key)=reshape(payload,1,[]); end
        end
        function volume=pendingTransmitBytes(obj,ue,direction)
            obj.requireEnabled();obj.requireUE(ue);direction=obj.normalizeDirection(direction);
            if obj.OriginalRRCRequired&&isempty(obj.TxRuntimes{ue,1+double(direction=="UL")})
                volume=struct('PDCPPendingBytes',0,'RLCPayloadBytes',0, ...
                    'AMRetransmissionBytes',0,'EligibleStatusBytes',0,'TotalBSRBytes',0, ...
                    'Source',"original_DRB_not_installed_no_L2_queue");
                return;
            end
            runtime=obj.runtime(ue,direction,"TX");
            volume=runtime.pendingTransmitBytes();
            volume.EligibleStatusBytes=obj.pendingReverseStatusBytes(ue,direction);
            volume.TotalBSRBytes=volume.TotalBSRBytes+volume.EligibleStatusBytes;
        end
        function [bits,e]=prepareQueuedSegment(obj,ue,direction,tbID,tbsBits,time,reserved)
            obj.requireEnabled(); obj.requireUE(ue); direction=obj.normalizeDirection(direction);
            validateattributes(tbsBits,{'numeric'},{'scalar','finite','integer','positive'});
            validateattributes(reserved,{'numeric'},{'scalar','finite','integer','nonnegative'});
            assert(mod(tbsBits,8)==0 && ~isKey(obj.Pending,char(tbID)) && ~isKey(obj.ControlTransports,char(tbID)), ...
                'sixgr:protocol:DuplicateTransportBlockBinding','Require new byte-aligned original TB.');
            capacity=tbsBits/8-reserved-3;
            assert(capacity>=3,'sixgr:protocol:MACPDUCapacityExceeded','Grant cannot hold actual RLC header and payload.');
            if capacity<=254, capacity=capacity+1; end
            assert(~obj.hasUncommittedTransport(ue,direction), ...
                'sixgr:protocol:PendingOriginalMACTransmission', ...
                'Defer a competing bearer preparation until its original pending TX commits or is cancelled.');
            runtime=obj.runtime(ue,direction,"TX"); [pdu,token]=runtime.previewSegment(capacity,time);
            assert(~isempty(fieldnames(pdu)),'sixgr:protocol:MissingQueuedPacket','No original queued L2 segment available.');
            pdu.UEIndex=ue; pdu.TBID=string(tbID); pdu.TransportBlockBits=tbsBits;
            pdu.QueuePreviewToken=token; pdu.QueueCommitted=false;
            pdu.ProtocolFragmentId=string(tbID); pdu.ReservedControlSubPDUBytes=reserved;
            item=struct('LCID',pdu.LCID,'Payload',pdu.Bytes,'OwnerID',"RLC-"+string(tbID));
            mac=sixgr.l2.mac.MACPDUAssembler.assemble(direction,item,tbsBits/8);
            pdu.MACBytes=mac.Bytes; pdu.MACSHA256=mac.SHA256; pdu.MACPaddingBytes=mac.PaddingBytes;
            pdu.MACControlSubPDUBytes=0; pdu.MACSubPDUs=mac.SubPDUs;
            obj.Pending(char(tbID))=pdu; bits=localBytesToBits(mac.Bytes);
            original=obj.QueuedOriginalPayloads(char(string(ue)+"|"+direction+"|"+string(pdu.PacketID)));
            range=pdu.ApplicationOffsetBytes+(1:pdu.ApplicationPayloadBytes);
            e=localEvidence(pdu,original(range),mac.PaddingBytes);
            e.PayloadSHA256=sixgr.protocol.ProtocolHash.bytes(original(range));
            e.PacketSHA256=pdu.PacketSHA256; e.ApplicationOffsetBytes=pdu.ApplicationOffsetBytes;
            e.PacketID=pdu.PacketID; e.SegmentOffset=pdu.SegmentOffset;
            e.SegmentPayloadBytes=pdu.SegmentPayloadBytes;
            e.CompletedTxPacket=pdu.CompletedTxPacket;
        end

        function pending=hasUncommittedTransport(obj,ue,direction)
            pending=false; keys=obj.Pending.keys;
            for k=1:numel(keys)
                p=obj.Pending(keys{k});
                if isfield(p,'QueuePreviewToken')&&p.UEIndex==ue&&string(p.Direction)==upper(string(direction))&&~p.QueueCommitted
                    pending=true; return;
                end
            end
        end
        function binding=originalTransportApplicationBinding(obj,id)
            key=char(string(id));
            if isKey(obj.ControlTransports,key)
                p=obj.ControlTransports(key);
                binding=rmfield(p,{'Preparation','MACBytes','Received','Bytes'});
                binding.Source="retained_original_control_only_preparation_not_PHY_execution_evidence";
                return;
            end
            assert(isKey(obj.Pending,key),'sixgr:protocol:MissingTransportBlockBinding','Original retained transport binding required.');
            p=obj.Pending(key); binding=struct();
            fields=["TBID","PacketID","UEID","UEIndex","BearerID","Direction","ConfigurationEpoch", ...
                "IsRLCRetransmission","RLCFullCount","ApplicationOffsetBytes","ApplicationPayloadBytes", ...
                "SegmentOffset","SegmentPayloadBytes","PacketSHA256","EncodedSHA256","MACSHA256", ...
                "TransportBlockBits","QueueCommitted"];
            for name=fields
                if isfield(p,name), binding.(name)=p.(name); end
            end
            binding.ControlOnly=false;
            binding.TransportKind="RLC_DATA";
            binding.Source="retained_original_protocol_preparation_not_PHY_execution_evidence";
        end
        function validatePreparedTransportBlock(obj,id,time,encodedBits)
            key=char(string(id));
            if isKey(obj.ControlTransports,key)
                p=obj.ControlTransports(key);
                assert(~p.QueueCommitted,'sixgr:protocol:DuplicateTransportBlockCommit','STATUS submits once.');
                if nargin>=4
                    actual=localBitsToBytes(encodedBits,p.TransportBlockBits);
                    assert(isequal(actual(:),p.MACBytes(:)),'sixgr:protocol:OriginalMACCommitMismatch','Actual STATUS MAC bytes changed.');
                end
                if p.TransportKind=="RLC_STATUS"
                    runtime=obj.runtime(p.UEIndex,p.DataDirection,"TX");
                    runtime.validateReverseStatus(p.Preparation,string(id),time);
                end
                return;
            end
            key=char(string(id)); assert(isKey(obj.Pending,key),'sixgr:protocol:MissingTransportBlockBinding','Original TB required.');
            p=obj.Pending(key);
            if nargin>=4
                assert((isnumeric(encodedBits)||islogical(encodedBits))&&isreal(encodedBits)&& ...
                    isvector(encodedBits)&&all(isfinite(encodedBits(:)))&&all(encodedBits(:)==0|encodedBits(:)==1), ...
                    'sixgr:protocol:OriginalMACCommitMismatch','Original finite binary coded bits required before conversion.');
                assert(isequal(int8(encodedBits(:)),localBytesToBits(p.MACBytes)), ...
                    'sixgr:protocol:OriginalMACCommitMismatch','Actual coded MAC bytes differ from the retained original preparation.');
            end
            if ~isfield(p,'QueuePreviewToken'), return; end
            assert(~p.QueueCommitted,'sixgr:protocol:DuplicateTransportBlockCommit','Original new-data TB committed once.');
            runtime=obj.runtime(p.UEIndex,string(p.Direction),"TX");
            original=runtime.validatePreparedSegment(p.QueuePreviewToken,time);
            assert(isequal(original.Bytes,p.Bytes)&&original.PacketID==p.PacketID, ...
                'sixgr:protocol:OriginalSegmentCommitMismatch','Prepared original bytes changed before commit.');
        end
        function commitPreparedTransportBlock(obj,id,time)
            key=char(string(id));
            if isKey(obj.ControlTransports,key)
                obj.validatePreparedTransportBlock(id,time); p=obj.ControlTransports(key);
                if p.TransportKind=="RLC_STATUS"
                    runtime=obj.runtime(p.UEIndex,p.DataDirection,"TX");
                    runtime.commitReverseStatus(p.Preparation,string(id),time);
                end
                p.QueueCommitted=true; obj.ControlTransports(key)=p; return;
            end
            obj.validatePreparedTransportBlock(id,time); key=char(string(id)); p=obj.Pending(key);
            if ~isfield(p,'QueuePreviewToken'), return; end
            runtime=obj.runtime(p.UEIndex,string(p.Direction),"TX");
            original=runtime.commitPreparedSegment(p.QueuePreviewToken,time);
            assert(isequal(original.Bytes,p.Bytes)&&original.PacketID==p.PacketID, ...
                'sixgr:protocol:OriginalSegmentCommitMismatch','Committed original bytes changed.');
            p.QueueCommitted=true; obj.Pending(key)=p;
        end
        function cancelPreparedTransportBlock(obj,id)
            key=char(string(id));
            if isKey(obj.ControlTransports,key)
                p=obj.ControlTransports(key);
                assert(~p.QueueCommitted,'sixgr:protocol:LateMACCancellation','Only unsent STATUS may cancel.');
                if p.TransportKind=="RLC_STATUS"
                    runtime=obj.runtime(p.UEIndex,p.DataDirection,"TX");
                    runtime.cancelReverseStatus(p.Preparation);
                end
                remove(obj.ControlTransports,key); return;
            end
            key=char(string(id)); assert(isKey(obj.Pending,key),'sixgr:protocol:MissingTransportBlockBinding','Original TB required.');
            p=obj.Pending(key);
            assert(isfield(p,'QueuePreviewToken')&&~p.QueueCommitted&&~isKey(obj.Decoded,key), ...
                'sixgr:protocol:LateMACCancellation','Only an untransmitted original preview may cancel.');
            runtime=obj.runtime(p.UEIndex,string(p.Direction),"TX");
            runtime.cancelPreparedSegment(p.QueuePreviewToken);
            remove(obj.Pending,key);
        end

        function [tbBits, evidence] = encodeFragment(obj, ueIndex, direction, ...
                transportBlockId, fragmentId, payload, tbsBits, eventTime, controlSubPDUs, reservedControlBytes)
            arguments
                obj
                ueIndex (1,1) double {mustBeInteger,mustBePositive}
                direction (1,1) string
                transportBlockId (1,1) string
                fragmentId (1,1) string
                payload (1,:) uint8
                tbsBits (1,1) double {mustBeInteger,mustBePositive}
                eventTime (1,1) double {mustBeNonnegative}
                controlSubPDUs struct = struct([])
                reservedControlBytes (1,1) double {mustBeFinite,mustBeInteger,mustBeNonnegative} = 0
            end
            obj.requireEnabled();
            direction = obj.normalizeDirection(direction);
            if mod(tbsBits, 8) ~= 0
                error("sixgr:protocol:NonByteAlignedTransportBlock", ...
                    "Same-waveform protocol integration requires a byte-aligned TBS, not %d bits.", tbsBits);
            end
            obj.requireUE(ueIndex);
            tbKey = char(transportBlockId);
            if isKey(obj.Pending, tbKey)
                error("sixgr:protocol:DuplicateTransportBlockBinding", ...
                    "Transport block %s already owns a protocol fragment.", transportBlockId);
            end

            [controlSubPDUs, controlBytes] = localControlSubPDUs(direction, controlSubPDUs);
            reservedControlBytes=max(reservedControlBytes,controlBytes);
            assert(numel(payload)<=obj.maximumPayloadBytes(tbsBits,reservedControlBytes), ...
                "sixgr:protocol:MACPDUCapacityExceeded", ...
                "Original application payload and control elements must fit before protocol state advances.");
            tx = obj.runtime(ueIndex, direction, "TX");
            pdu = tx.transmit(fragmentId, payload, eventTime);
            tbsBytes = tbsBits / 8;
            sdu = struct("LCID", pdu.LCID, "Payload", pdu.Bytes, ...
                "OwnerID", "RLC-" + fragmentId);
            mac = sixgr.l2.mac.MACPDUAssembler.assemble(direction, ...
                [controlSubPDUs(:); sdu], tbsBytes);
            pdu.MACBytes = mac.Bytes;
            pdu.MACSHA256 = mac.SHA256;
            pdu.TBID = transportBlockId;
            pdu.TransportBlockBits = tbsBits;
            pdu.MACPaddingBytes = mac.PaddingBytes;
            pdu.MACControlSubPDUBytes = controlBytes;
            pdu.ReservedControlSubPDUBytes=reservedControlBytes;
            pdu.MACSubPDUs = mac.SubPDUs;
            pdu.ProtocolFragmentId = fragmentId;
            obj.Pending(tbKey) = pdu;

            tbBits = localBytesToBits(mac.Bytes);
            if numel(tbBits) ~= tbsBits
                error("sixgr:protocol:TransportBlockSizeMismatch", ...
                    "MAC PDU produced %d bits for a %d-bit PHY transport block.", ...
                    numel(tbBits), tbsBits);
            end
            evidence = localEvidence(pdu, payload, mac.PaddingBytes);
        end

        function [delivered, evidence] = deliverDecoded(obj, transportBlockId, ...
                decodedTransportBlockBits, eventTime)
            arguments
                obj
                transportBlockId (1,1) string
                decodedTransportBlockBits
                eventTime (1,1) double {mustBeNonnegative}
            end
            obj.requireEnabled();
            key = char(transportBlockId);
            if isKey(obj.Delivered, key)
                delivered = false;
                evidence = struct("Status", "duplicate_harq_delivery_rejected", ...
                    "TransportBlockId", transportBlockId);
                return;
            end
            if ~isKey(obj.Pending, key)
                error("sixgr:protocol:MissingTransportBlockBinding", ...
                    "Decoded transport block %s has no protocol-PDU binding.", transportBlockId);
            end
            pdu = obj.Pending(key);
            if isfield(pdu,'QueuePreviewToken')
                assert(pdu.QueueCommitted,'sixgr:protocol:DecodeBeforeOriginalTX','Commit original TX before receiver delivery.');
            end
            if isKey(obj.Decoded,key)
                prior=obj.Decoded(key);
                repeated=localBitsToBytes(decodedTransportBlockBits,double(pdu.TransportBlockBits));
                assert(sixgr.l2.mac.MACHash.of(repeated)==prior.DecodedMACSHA256, ...
                    'sixgr:protocol:DecodedTransportBlockMismatch','Repeated TB decode changed bytes.');
                delivered=false; evidence=prior;
                evidence.CompletedTransportBlocks=struct([]); return;
            end
            decodedMACBytes = localBitsToBytes(decodedTransportBlockBits, ...
                double(pdu.TransportBlockBits));
            decodedMACSHA256 = sixgr.l2.mac.MACHash.of(decodedMACBytes);
            if decodedMACSHA256 ~= string(pdu.MACSHA256)
                error("sixgr:protocol:DecodedTransportBlockMismatch", ...
                    ["The decoder output for transport block %s does not match " + ...
                     "the MAC PDU that entered the waveform chain."], transportBlockId);
            end
            demux = sixgr.l2.mac.MACPDUDemultiplexer.decode( ...
                string(pdu.Direction), decodedMACBytes);
            sduMask = string({demux.SubPDUs.Kind}) == "SDU";
            if sum(sduMask) ~= 1 || demux.SubPDUs(find(sduMask,1)).LCID ~= pdu.LCID
                error("sixgr:protocol:DecodedTransportBlockMismatch", ...
                    "Decoded transport block %s does not contain the expected MAC SDU.", ...
                    transportBlockId);
            end
            decodedRLCBytes = uint8(demux.SubPDUs(find(sduMask,1)).Payload);
            decodedRLC_SHA256 = sixgr.protocol.ProtocolHash.bytes(decodedRLCBytes);
            if decodedRLC_SHA256 ~= string(pdu.EncodedSHA256)
                error("sixgr:protocol:DecodedTransportBlockMismatch", ...
                    "Decoded RLC PDU for transport block %s differs from the transmitted PDU.", ...
                    transportBlockId);
            end
            recoveredPDU = pdu;
            recoveredPDU.MACBytes = decodedMACBytes;
            recoveredPDU.Bytes = decodedRLCBytes;
            % ProtocolRuntime owns both Tx and Rx state for one bearer.  The
            % same bearer instance is required so delivery closes the exact
            % lineage node created during transmit.  Crucially, the bytes
            % passed to its receive side are reconstructed from the actual
            % PHY decoder output above, never from the pending Tx copy.
            rx = obj.runtime(localUEIndex(pdu), string(pdu.Direction), "TX");
            evidence = struct("Status", "decoded_awaiting_protocol_reordering", ...
                "TransportBlockId", transportBlockId, ...
                "ProtocolFragmentId", string(pdu.ProtocolFragmentId), ...
                "PacketId", string(pdu.PacketID), ...
                "MACSHA256", string(pdu.MACSHA256), ...
                "DecodedMACSHA256", string(decodedMACSHA256), ...
                "EncodedRLC_SHA256", string(pdu.EncodedSHA256), ...
                "DecodedRLC_SHA256", string(decodedRLC_SHA256), ...
                "PayloadSHA256", string(pdu.PacketSHA256), ...
                "DecodedBitCount", double(numel(decodedTransportBlockBits)), ...
                "DecodedBitExact", true, ...
                "EvidenceSource", "actual_phy_decoder_bits_demuxed_through_strict_mac_rlc_pdcp_sdap");
            evidence.DecodedTime_s=eventTime;
            obj.Decoded(key)=evidence;
            [~,completions,rlcDisposition,pdcpDisposition]=rx.receive(recoveredPDU,eventTime);
            evidence.RLCDisposition=rlcDisposition;
            evidence.PDCPDisposition=pdcpDisposition;
            if any(rlcDisposition==["duplicate_bytes","outside_window"])
                evidence.Status="original_RLC_"+rlcDisposition+"_discarded";
            end
            if pdcpDisposition=="duplicate_or_below_RX_DELIV_discarded"
                evidence.Status="original_PDCP_duplicate_or_below_RX_DELIV_discarded";
            end
            if pdcpDisposition=="integrity_failed_discarded"
                evidence.Status="original_PDCP_integrity_failed_discarded";
            end
            obj.Decoded(key)=evidence;
            released=obj.releaseCompletions(completions);
            delivered=isKey(obj.Delivered,key);
            if delivered,evidence.Status=localDeliveryStatus(true);end
            evidence.CompletedTransportBlocks=released;
        end

        function completed=advance(obj,eventTime)
            % Release only original received bytes whose protocol timer expires.
            validateattributes(eventTime,{'numeric'},{'scalar','real','finite','nonnegative'});
            completed=struct([]);
            for k=1:numel(obj.TxRuntimes)
                runtime=obj.TxRuntimes{k};
                if isempty(runtime), continue; end
                released=obj.releaseCompletions(runtime.advance(eventTime));
                if isempty(completed), completed=released;
                elseif ~isempty(released), completed=[completed;released]; end %#ok<AGROW>
            end
        end

        function time=nextTimerExpiry(obj)
            time=inf;
            for k=1:numel(obj.TxRuntimes)
                runtime=obj.TxRuntimes{k};
                if ~isempty(runtime), time=min(time,runtime.nextTimerExpiry()); end
            end
        end

        function tf=hasInstalledRuntime(obj,ue)
            validateattributes(ue,{'numeric'},{'scalar','real','finite','integer','positive','<=',obj.NumUEs});
            % Pure inventory query: never instantiate a lazy bearer owner.
            tf=any(~cellfun(@isempty,obj.TxRuntimes(ue,:)))||any(~cellfun(@isempty,obj.RxRuntimes(ue,:)));
        end
        function rows=takeSecurityIndications(obj)
            rows=struct([]);
            banks={obj.TxRuntimes,obj.RxRuntimes};
            for b=1:numel(banks)
                bank=banks{b};
                for k=1:numel(bank)
                    runtime=bank{k};if isempty(runtime),continue;end
                    fresh=runtime.takeSecurityIndications();
                    for row=reshape(fresh,1,[])
                        assert(isequaln(row,runtime.originalSecurityIndication(row.IndicationID)), ...
                            'sixgr:pdcp:SecurityObservationMismatch','Original private indication required.');
                        row.UEIndex=mod(k-1,obj.NumUEs)+1;
                        if isempty(rows),rows=row;else,rows(end+1)=row;end
                    end
                end
            end
        end
        function rows=takeUpperLayerIndications(obj)
            rows=struct([]);
            for k=1:numel(obj.TxRuntimes)
                runtime=obj.TxRuntimes{k};if isempty(runtime),continue;end
                fresh=runtime.takeUpperLayerIndications();
                for row=reshape(fresh,1,[])
                    row.UEIndex=mod(k-1,obj.NumUEs)+1;
                    if isempty(rows),rows=row;else,rows(end+1)=row;end %#ok<AGROW>
                end
            end
        end

        function rows=takeDiscardEvents(obj)
            rows=struct([]);
            for k=1:numel(obj.TxRuntimes)
                runtime=obj.TxRuntimes{k};if isempty(runtime),continue;end
                fresh=runtime.takeDiscardEvents();
                for row=reshape(fresh,1,[])
                    row.UEIndex=mod(k-1,obj.NumUEs)+1;
                    row=rmfield(row,'ReceiptID');
                    row.ReceiptID=sixgr.l2.mac.MACHash.of(orderfields(row));
                    key=char(row.ReceiptID);
                    assert(~isKey(obj.DiscardReceipts,key),'sixgr:protocol:DuplicateDiscardReceipt', ...
                        'One original PDCP timer event must be retained once.');
                    obj.DiscardReceipts(key)=row;
                    if isempty(rows),rows=row;else,rows(end+1)=row;end %#ok<AGROW>
                end
            end
        end

        function row=originalDiscardReceipt(obj,id)
            key=char(string(id));
            assert(isKey(obj.DiscardReceipts,key),'sixgr:protocol:DiscardIdentity', ...
                'Original private PDCP/lower-layer discard receipt required.');
            row=obj.DiscardReceipts(key);
        end

function [bits,evidence]=finalizeULControl(obj,transportBlockId,controlSubPDUs,authority)
key=char(string(transportBlockId));
controlOnly=isKey(obj.ControlTransports,key);
assert(controlOnly||isKey(obj.Pending,key),'sixgr:protocol:MissingTransportBlockBinding','Original SDU required.');
if controlOnly, pdu=obj.ControlTransports(key); else, pdu=obj.Pending(key); end
assert(~sixgr.util.structGet(pdu,'QueueCommitted',false),'sixgr:protocol:LateMACFinalization','MAC cannot change after actual TX.');
assert(string(pdu.Direction)=="UL" && ~isKey(obj.Decoded,key) && ~isKey(obj.Delivered,key), ...
    'sixgr:protocol:LateMACFinalization','UL MAC must finalize before original receiver completion.');
assert(isstruct(authority)&&isscalar(authority)&& ...
    string(authority.Stage)=="original_received_DCI_before_first_TX" && ...
    strlength(string(authority.AssignmentDigest))==64 && ...
    strlength(string(authority.OriginalGrantContextID))==64 && ...
    authority.TBSBits==pdu.TransportBlockBits && authority.IsNewData, ...
    'sixgr:protocol:MACFinalizationAuthority','Original received assignment and immutable TBS required.');
% The caller validates received assignment identity, scope, clocks, current
% carrier/PUSCH allocation and original power preview before passing authority.
[controlSubPDUs,controlBytes]=localControlSubPDUs("UL",controlSubPDUs);
assert(controlBytes<=pdu.ReservedControlSubPDUBytes, ...
    'sixgr:protocol:MACControlReservationExceeded','Never resize original SDU/TBS to fit unreserved CE.');
sdu=struct('LCID',pdu.LCID,'Payload',pdu.Bytes,'OwnerID',"RLC-"+string(pdu.ProtocolFragmentId));
items=[controlSubPDUs(:);sdu];
if controlOnly&&pdu.TransportKind=="MAC_CE_PADDING", items=controlSubPDUs(:); end
mac=sixgr.l2.mac.MACPDUAssembler.assemble('UL',items,pdu.TransportBlockBits/8);
receipt=struct('TransportBlockId',string(transportBlockId),'Authority',authority, ...
    'OriginalSDUSHA256',string(pdu.EncodedSHA256),'MACSHA256',mac.SHA256, ...
    'MACControlSubPDUBytes',controlBytes,'MACPaddingBytes',mac.PaddingBytes, ...
    'SubPDUs',mac.SubPDUs,'ApplicationPayloadBits',8*sixgr.util.structGet(pdu,'ApplicationPayloadBytes',pdu.PayloadBytes));
receipt.SHA256=sixgr.l2.mac.MACHash.of(receipt);
if isfield(pdu,'ULMACFinalization')
    assert(isequaln(pdu.ULMACFinalization,receipt),'sixgr:protocol:MACFinalizationConflict', ...
        'An original new-data MAC PDU cannot be finalized twice with different bytes or authority.');
else
    pdu.ULMACFinalization=receipt; pdu.MACBytes=mac.Bytes; pdu.MACSHA256=mac.SHA256;
    pdu.MACPaddingBytes=mac.PaddingBytes; pdu.MACControlSubPDUBytes=controlBytes;
    pdu.MACSubPDUs=mac.SubPDUs;
    if controlOnly, obj.ControlTransports(key)=pdu; else, obj.Pending(key)=pdu; end
end
bits=localBytesToBits(pdu.MACBytes); evidence=receipt;
end

        function [ready,payload,receipt]=applicationRecoveryReceipt(obj,ue,direction,packetID)
            % Authenticate all contributors in the private original/decoded/
            % released registries. A public recovery flag cannot select this path.
            obj.requireEnabled();obj.requireUE(ue);direction=obj.normalizeDirection(direction);
            ready=false;payload=uint8([]);receipt=struct();keys=obj.Pending.keys;
            hits={};hasRecovery=false;
            for k=1:numel(keys)
                p=obj.Pending(keys{k});
                if isfield(p,'QueuePreviewToken')&&p.UEIndex==ue&& ...
                        string(p.Direction)==direction&&string(p.PacketID)==string(packetID)
                    hits{end+1}=keys{k}; %#ok<AGROW>
                    hasRecovery=hasRecovery||isequal(p.IsRLCRetransmission,true);
                end
            end
            if ~hasRecovery,return;end
            contributors=struct([]);owner=struct();
            for k=1:numel(hits)
                key=hits{k};p=obj.Pending(key);
                if ~isKey(obj.Delivered,key),continue;end
                assert(p.QueueCommitted&&isKey(obj.Decoded,key)&&isKey(obj.ReleasedEvidence,key), ...
                    'sixgr:protocol:InvalidRLCApplicationRecovery','Recovery requires original TX, decoder and release records.');
                e=obj.ReleasedEvidence(key);whole=obj.CompletedPayloads(key);
                o=struct('Direction',string(p.Direction),'UEID',string(p.UEID), ...
                    'BearerID',string(p.BearerID),'ConfigurationEpoch',p.ConfigurationEpoch, ...
                    'PacketID',string(p.PacketID),'RLCFullCount',p.RLCFullCount, ...
                    'PayloadBytes',numel(whole),'PayloadSHA256',string(p.PacketSHA256));
                if isempty(fieldnames(owner)),owner=o;payload=whole;
                else,assert(isequaln(owner,o)&&isequal(payload,whole), ...
                    'sixgr:protocol:InvalidRLCApplicationRecovery','Released bearer/count/packet bytes disagree.');end
                part=whole(p.ApplicationOffsetBytes+(1:p.ApplicationPayloadBytes));
                c=rmfield(o,{'PayloadBytes','PayloadSHA256'});
                c.TransportBlockID=string(p.TBID);c.ApplicationOffsetBytes=p.ApplicationOffsetBytes;
                c.ApplicationBytes=part;c.OriginalApplicationFragmentSHA256=e.ApplicationFragmentPayloadSHA256;
                c.OriginalMACSHA256=string(p.MACSHA256);c.DecodedMACSHA256=e.DecodedMACSHA256;
                c.OriginalRLCSHA256=string(p.EncodedSHA256);c.DecodedRLCSHA256=e.DecodedRLC_SHA256;
                c.DecodedBitExact=e.DecodedBitExact;c.ReleasedAfterPDCP=true;
                c.DecoderEvidenceSource=e.EvidenceSource;c.DecodedTime_s=e.DecodedTime_s;
                c.DeliveryTime_s=e.DeliveryTime_s;
                if isempty(contributors),contributors=c;else,contributors(end+1)=c;end %#ok<AGROW>
            end
            if isempty(contributors),return;end
            receipt=sixgr.truth.validateRLCApplicationRecovery(payload,owner,contributors);
            ready=true;
        end

        function [payload,sha256]=reassembleDecodedApplication(obj,transportBlockIds,expectedByteLengths)
            ids=string(transportBlockIds(:)); counts=double(expectedByteLengths(:));
            assert(~isempty(ids)&&numel(ids)==numel(counts)&& ...
                numel(unique(ids))==numel(ids)&&all(~ismissing(ids))&&all(strlength(ids)>0)&& ...
                all(isfinite(counts)&counts>=0&counts==fix(counts)), ...
                'sixgr:protocol:ApplicationReassemblyIdentity','Exact ordered decoded fragments required.');
            first=obj.Pending(char(ids(1)));
            if isfield(first,'QueuePreviewToken')
                for k=1:numel(ids)
                    key=char(ids(k)); pending=obj.Pending(key);
                    assert(string(pending.PacketID)==string(first.PacketID)&& ...
                        pending.UEIndex==first.UEIndex&&string(pending.Direction)==string(first.Direction)&&isKey(obj.Delivered,key)&& ...
                        isKey(obj.CompletedPayloads,key), ...
                        'sixgr:protocol:ApplicationReassemblyBeforeDelivery','Original packet segments must all be released.');
                end
                payload=obj.CompletedPayloads(char(ids(1)));
                assert(sum(counts)==numel(payload),'sixgr:protocol:ApplicationFragmentLength', ...
                    'Original segment application intervals must cover exactly the received packet.');
                sha256=sixgr.protocol.ProtocolHash.bytes(payload); return;
            end
            parts=cell(numel(ids),1);
            for k=1:numel(ids)
                key=char(ids(k));
                assert(isKey(obj.Delivered,key)&&isKey(obj.CompletedPayloads,key), ...
                    'sixgr:protocol:ApplicationReassemblyBeforeDelivery', ...
                    'Only released original receiver payloads may enter application reassembly.');
                parts{k}=obj.CompletedPayloads(key);
                assert(numel(parts{k})==counts(k),'sixgr:protocol:ApplicationFragmentLength', ...
                    'Released fragment length differs from original interval ownership.');
            end
            payload=[parts{:}];
            sha256=sixgr.protocol.ProtocolHash.bytes(payload);
        end

        function bytes = maximumPayloadBytes(obj, tbsBits, reservedControlBytes)
            arguments
                obj
                tbsBits (1,1) double {mustBeInteger,mustBePositive}
                reservedControlBytes (1,1) double {mustBeFinite,mustBeInteger,mustBeNonnegative} = 0
            end
            obj.requireEnabled();
            if mod(tbsBits, 8) ~= 0
                bytes = 0;
                return;
            end
            assert(~obj.OriginalRRCRequired,'sixgr:protocol:OriginalDRBQueuedPathRequired', ...
                'A received DRB uses its actual queued RLC header and grant capacity.');
            pdcpSNBits = double(sixgr.util.structGet(obj.Configuration, "pdcp.sn_bits", NaN));
            rlcSNBits = double(sixgr.util.structGet(obj.Configuration, "rlc.sn_bits", NaN));
            if ~ismember(pdcpSNBits, [12 18]) || ~ismember(rlcSNBits, [12 18])
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Waveform protocol binding requires explicit 12- or 18-bit PDCP/RLC SN lengths.");
            end
            fixedHeaders = 1 + (2 + double(pdcpSNBits == 18)) + ...
                (2 + double(rlcSNBits == 18));
            integrity=upper(string(sixgr.util.structGet(obj.Configuration,"pdcp.integrity_algorithm","")));
            assert(ismember(integrity,["NIA0","128-NIA2"]), ...
                'sixgr:protocol:UnsupportedCapability','Capacity needs an explicit supported integrity algorithm.');
            fixedHeaders=fixedHeaders+4*double(integrity=="128-NIA2");
            tbsBytes = tbsBits / 8 - reservedControlBytes;
            bytes = max(0, tbsBytes - fixedHeaders - 3);
            if bytes + fixedHeaders <= 255
                bytes = min(tbsBytes - fixedHeaders - 2, bytes + 1);
            end
            bytes = max(0, floor(bytes));
        end
    end

    methods (Access = private)
        function out=releaseCompletions(obj,completions)
            out=struct([]);
            keys=obj.Pending.keys;
            for j=1:numel(completions)
                c=completions(j); hits={};
                scopeFields={'UEID','BearerID','Direction','ConfigurationEpoch'};
                assert(all(isfield(c,scopeFields)), ...
                    'sixgr:protocol:CompletionLineage','Completion requires its original full bearer identity.');
                for k=1:numel(keys)
                    pending=obj.Pending(keys{k});
                    if string(pending.PacketID)~=string(c.PacketID), continue; end
                    assert(all(isfield(pending,scopeFields)), ...
                        'sixgr:protocol:CompletionLineage','Retained PDU requires its original full bearer identity.');
                    if string(pending.UEID)==string(c.UEID)&& ...
                            string(pending.BearerID)==string(c.BearerID)&& ...
                            string(pending.Direction)==string(c.Direction)&& ...
                            pending.ConfigurationEpoch==c.ConfigurationEpoch
                        hits{end+1}=keys{k}; %#ok<AGROW>
                    end
                end
                assert(~isempty(hits),'sixgr:protocol:CompletionLineage', ...
                    'A released original packet must own retained transport blocks.');
                releasedCount=0;
                for h=1:numel(hits)
                    key=hits{h};
                    % Unreceived duplicate/resegmented TX blocks do not gain decoder evidence.
                    if ~isKey(obj.Decoded,key)||isKey(obj.Delivered,key), continue; end
                    original=obj.Decoded(key);
                    if any(string(sixgr.util.structGet(original,'RLCDisposition',""))==["duplicate_bytes","outside_window"])
                        continue; % Actual decoder proof is retained, but rejected RLC bytes never gain a PDCP release.
                    end
                    if any(string(sixgr.util.structGet(original,'PDCPDisposition',""))==["duplicate_or_below_RX_DELIV_discarded","integrity_failed_discarded"])
                        continue;
                    end
                    assert(isa(c.Payload,'uint8') && ...
                        sixgr.protocol.ProtocolHash.bytes(c.Payload)==string(c.PayloadSHA256) && ...
                        string(c.PayloadSHA256)==original.PayloadSHA256 && ...
                        isfinite(c.DeliveryTime_s) && c.DeliveryTime_s>=original.DecodedTime_s, ...
                        'sixgr:protocol:CompletionLineage','Released bytes/clock differ from original decoded lineage.');
                    row=original; row.Status="delivered_after_exact_phy_decode";
                    row.DeliveryTime_s=c.DeliveryTime_s; row.PDCPCount=c.PDCPCount;
                    owned=obj.Pending(key);
                    offset=double(sixgr.util.structGet(owned,'ApplicationOffsetBytes',0));
                    count=double(sixgr.util.structGet(owned,'ApplicationPayloadBytes',numel(c.Payload)));
                    assert(offset>=0&&count>=0&&offset+count<=numel(c.Payload), ...
                        'sixgr:protocol:ApplicationFragmentLength','Decoded packet does not cover original segment interval.');
                    row.ApplicationFragmentPayloadSHA256=sixgr.protocol.ProtocolHash.bytes(c.Payload(offset+(1:count)));
                    row.ApplicationPayloadBytes=count;
                    obj.Delivered(key)=true; obj.CompletedPayloads(key)=reshape(c.Payload,1,[]);
                    obj.ReleasedEvidence(key)=row;
                    if isempty(out), out=row; else, out(end+1,1)=row; end %#ok<AGROW>
                    releasedCount=releasedCount+1;
                end
                assert(releasedCount>0,'sixgr:protocol:CompletionWithoutDecode', ...
                    'New protocol completion requires original PHY decoded bytes.');
            end
        end
        function runtime = runtime(obj, ueIndex, direction, endpoint)
            col = 1 + double(direction == "UL");
            if endpoint == "TX"
                bank = obj.TxRuntimes;
            else
                bank = obj.RxRuntimes;
            end
            runtime = bank{ueIndex, col};
            if isempty(runtime)
                assert(~obj.OriginalRRCRequired,'sixgr:protocol:OriginalDRBRequired', ...
                    'No original issued/received DRB owner is installed for this connection.');
                runtime = sixgr.protocol.ProtocolRuntime( ...
                    localRuntimeConfig(obj.Configuration, ueIndex, direction));
                if endpoint == "TX"
                    obj.TxRuntimes{ueIndex, col} = runtime;
                else
                    obj.RxRuntimes{ueIndex, col} = runtime;
                end
            end
        end

        function requireEnabled(obj)
            if ~obj.Enabled
                error("sixgr:protocol:WaveformProtocolBridgeDisabled", ...
                    "Same-waveform protocol bridge is not enabled by strict protocol YAML configuration.");
            end
        end

        function requireUE(obj, ueIndex)
            validateattributes(ueIndex,{'numeric'},{'real','scalar','finite','integer','positive'});
            if ueIndex > obj.NumUEs
                error("sixgr:protocol:InvalidUEIndex", ...
                    "Protocol UE index %d exceeds configured UE count %d.", ueIndex, obj.NumUEs);
            end
        end
    end

    methods (Static, Access = private)
        function value = normalizeDirection(value)
            value = upper(strtrim(string(value)));
            if ~any(value == ["DL","UL"])
                error("sixgr:protocol:UnsupportedDirection", ...
                    "Protocol waveform direction must be DL or UL.");
            end
        end
    end
end

function config = localRuntimeConfig(protocol, ueIndex, direction)
sessions = localStructArray(sixgr.util.structGet(protocol, "traffic.sessions", struct()));
if isempty(sessions)
    error("sixgr:protocol:MissingTrafficSession", ...
        "Same-waveform protocol execution requires protocol.traffic.sessions.");
end
match = false(numel(sessions),1);
for i = 1:numel(sessions)
    configured = upper(string(sixgr.util.structGet(sessions(i), "direction", "")));
    match(i) = configured == direction || configured == "BIDIR";
end
idx = find(match, 1, "first");
if isempty(idx)
    error("sixgr:protocol:MissingTrafficSession", ...
        "No configured protocol traffic session carries %s.", direction);
end
session = sessions(idx);
qfi = double(sixgr.util.structGet(session, "qfi", NaN));
mappings = localStructArray(sixgr.util.structGet(protocol, "sdap.qfi_to_drb", struct()));
drb = NaN;
for i = 1:numel(mappings)
    if double(sixgr.util.structGet(mappings(i), "qfi", NaN)) == qfi
        drb = double(sixgr.util.structGet(mappings(i), "drb_id", NaN));
        break;
    end
end
pdcp = sixgr.util.structGet(protocol, "pdcp", struct());
rlc = sixgr.util.structGet(protocol, "rlc", struct());
config = struct( ...
    "UEID", "UE-" + compose("%03d", ueIndex), ...
    "BearerID", "DRB-" + string(drb), ...
    "Direction", direction, "QFI", qfi, "DRBID", drb, ...
    "PduSessionID", double(sixgr.util.structGet(session, "pdu_session_id", ...
        sixgr.util.structGet(protocol, "sdap.pdu_session_id", NaN))), ...
    "LCID", double(sixgr.util.structGet(protocol, "mac.lcid", NaN)), ...
    "PDCPSNBits", double(sixgr.util.structGet(pdcp, "sn_bits", NaN)), ...
    "RLCSNBits", double(sixgr.util.structGet(rlc, "sn_bits", NaN)), ...
    "ConfigurationEpoch", double(sixgr.util.structGet(protocol, "configuration_epoch", NaN)), ...
    "CipherAlgorithm", string(sixgr.util.structGet(pdcp, "cipher_algorithm", "")), ...
    "IntegrityAlgorithm", string(sixgr.util.structGet(pdcp, "integrity_algorithm", "")), ...
    "PollPDU", double(sixgr.util.structGet(rlc, "poll_pdu", NaN)), ...
    "PollByte", double(sixgr.util.structGet(rlc, "poll_byte", NaN)), ...
    "MaxRetxThreshold", double(sixgr.util.structGet(rlc, "max_retx_threshold", NaN)));
config.SecurityActive = config.CipherAlgorithm ~= "NEA0" || ...
    config.IntegrityAlgorithm ~= "NIA0";
timer=double(sixgr.util.structGet(pdcp,"t_reordering_ms",inf));
assert(isscalar(timer) && ~isnan(timer) && timer>=0, ...
    'sixgr:pdcp:ReorderingStateViolation','Configured t-Reordering must be nonnegative milliseconds.');
config.ReorderingTime_s=timer/1000;
discard=double(sixgr.util.structGet(pdcp,'discard_timer_ms',inf));
assert(isscalar(discard)&&~isnan(discard)&&discard>0, ...
    'sixgr:pdcp:DiscardClock','PDCP discard timer must be positive milliseconds or infinity.');
config.DiscardTime_s=discard/1000;
if isfinite(discard)
    config.SampleRateHz=double(protocol.sample_rate_hz);
    config.ClockEpoch=double(protocol.clock_epoch);
end
config.RLCARQEnabled=logical(sixgr.util.structGet(rlc,"arq_enabled",false));
if config.RLCARQEnabled
    config.SampleRateHz=double(protocol.sample_rate_hz);
    config.ClockEpoch=double(protocol.clock_epoch);
    config.RLCPollRetransmit_s=double(rlc.t_poll_retransmit_ms)/1000;
    config.RLCReassembly_s=double(rlc.t_reassembly_ms)/1000;
    config.RLCStatusProhibit_s=double(rlc.t_status_prohibit_ms)/1000;
end
if config.CipherAlgorithm=="128-NEA2"
    config.CipherKey=localSecurityKey(pdcp,"cipher_key_hex");
end
if config.IntegrityAlgorithm=="128-NIA2"
    config.IntegrityKey=localSecurityKey(pdcp,"integrity_key_hex");
end
end

function bytes=localSecurityKey(cfg,name)
value=string(sixgr.util.structGet(cfg,name,""));
assert(isscalar(value) && ~ismissing(value) && ...
    ~isempty(regexp(char(value),'^[0-9a-fA-F]{32}$','once')), ...
    'sixgr:pdcp:SecurityContextMissing','Active security requires its explicit 128-bit configured key.');
bytes=uint8(hex2dec(reshape(char(value),2,[]).')).';
end

function values = localStructArray(value)
if isempty(value)
    values = repmat(struct(),0,1);
elseif iscell(value)
    values = [value{:}];
elseif isstruct(value)
    values = value(:);
else
    error("sixgr:protocol:UnsupportedCapability", ...
        "Protocol session/mapping configuration must be a struct array.");
end
end

function bits = localBytesToBits(bytes)
bytes = uint8(bytes(:));
matrix = false(numel(bytes), 8);
for bitIndex = 1:8
    matrix(:,bitIndex) = logical(bitget(bytes, 9 - bitIndex));
end
bits = int8(reshape(matrix.', [], 1));
end

function bytes = localBitsToBytes(bits, expectedBitCount)
bits = double(bits(:));
if numel(bits) ~= expectedBitCount
    error("sixgr:protocol:DecodedTransportBlockLengthMismatch", ...
        "PHY decoder returned %d bits for a %d-bit protocol transport block.", ...
        numel(bits), expectedBitCount);
end
if mod(numel(bits), 8) ~= 0 || any(~isfinite(bits)) || ...
        any(bits ~= 0 & bits ~= 1)
    error("sixgr:protocol:InvalidDecodedTransportBlockBits", ...
        "Decoded protocol transport-block data must be a byte-aligned binary vector.");
end
weights = 2.^(7:-1:0);
bytes = uint8(reshape(bits, 8, []).' * weights.');
bytes = bytes(:).';
end

function evidence = localEvidence(pdu, payload, paddingBytes)
evidence = struct( ...
    "ProtocolFragmentId", string(pdu.ProtocolFragmentId), ...
    "PacketId", string(pdu.PacketID), ...
    "PayloadBits", double(numel(payload) * 8), ...
    "PayloadSHA256", string(pdu.PacketSHA256), ...
    "SDAPHeaderHex", localHex(pdu.SDAPHeader), ...
    "PDCPHeaderHex", localHex(pdu.PDCPHeader), ...
    "RLCHeaderHex", localHex(pdu.RLCHeader), ...
    "EncodedRLC_SHA256", string(pdu.EncodedSHA256), ...
    "MACSHA256", string(pdu.MACSHA256), ...
    "MACPDUBytes", double(numel(pdu.MACBytes)), ...
    "MACPaddingBytes", double(paddingBytes), ...
    "MACControlSubPDUBytes", double(pdu.MACControlSubPDUBytes), ...
    "MACSubPDUs", pdu.MACSubPDUs, ...
    "SameWaveformPayloadTruth", true, ...
    "EvidenceSource", "strict_sdap_pdcp_rlc_mac_bytes_bound_to_phy_transport_block");
end

function value = localHex(bytes)
bytes = uint8(bytes(:));
if isempty(bytes)
    value = "";
else
    value = lower(join(compose("%02X", bytes), ""));
end
end

function idx = localUEIndex(pdu)
if isfield(pdu,'UEIndex'), idx=pdu.UEIndex; return; end
token = regexp(char(string(pdu.PacketID)), 'UE-(\d+)', 'tokens', 'once');
if isempty(token)
    error("sixgr:protocol:LineageViolation", ...
        "Protocol packet identity does not contain a UE index.");
end
idx = str2double(token{1});
end

function value = localDeliveryStatus(delivered)
if delivered
    value = "delivered_after_exact_phy_decode";
else
    value = "protocol_duplicate_or_reordering_rejected";
end
end

function [items,total]=localControlSubPDUs(direction,input)
% Original prepared CE octets only; no scalar coercion or inferred payload.
items=repmat(struct('LCID',0,'Payload',uint8.empty(1,0),'OwnerID',""),0,1);
total=0;
for k=1:numel(input)
    x=input(k);
    assert(all(isfield(x,{'LCID','Payload','OwnerID'})), ...
        'sixgr:protocol:InvalidControlSubPDU','Prepared CE ownership is required.');
    schema=sixgr.l2.mac.MACCESchemaRegistry.resolve(direction,x.LCID);
    assert(schema.Kind=="CE" && isa(x.Payload,'uint8') && (isvector(x.Payload)||isempty(x.Payload)) && ...
        isscalar(string(x.OwnerID)) && strlength(string(x.OwnerID))>0, ...
        'sixgr:protocol:InvalidControlSubPDU','Control elements require exact uint8 bytes and an owner.');
    payload=reshape(x.Payload,1,[]);
    header=sixgr.l2.mac.MACSubheaderCodec.encode(direction,x.LCID,numel(payload));
    items(end+1,1)=struct('LCID',double(x.LCID),'Payload',payload,'OwnerID',string(x.OwnerID)); %#ok<AGROW>
    total=total+numel(header)+numel(payload);
end
end
