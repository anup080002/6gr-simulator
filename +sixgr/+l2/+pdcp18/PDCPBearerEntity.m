classdef PDCPBearerEntity < handle
    %PDCPBEARERENTITY Exact bounded PDCP data/security/count authority.
    properties (SetAccess=private)
        UEID (1,1) string
        BearerID (1,1) string
        Bearer (1,1) double
        Direction (1,1) double
        BearerType (1,1) string
        SNBits (1,1) double
        ConfigurationEpoch (1,1) double
        CipherAlgorithm (1,1) string
        IntegrityAlgorithm (1,1) string
        TX sixgr.l2.pdcp18.PDCPCountState
        RX sixgr.l2.pdcp18.PDCPReorderingState
        SecurityActive (1,1) logical=false
        TXIntegrityActive (1,1) logical=false
        RXIntegrityActive (1,1) logical=false
        TXCipheringActive (1,1) logical=false
        RXCipheringActive (1,1) logical=false
        DuplicateCount (1,1) double=0
        SDAPHeaderPresent (1,1) logical=false
        Active (1,1) logical=true
    end
    properties (Access=private)
        CipherKey uint8
        IntegrityKey uint8
        Delivered cell={}
        BufferedPayloads
        DiscardState=[]
        PendingTransmitDiscards struct=struct([])
        ExplicitCipherKey (1,1) logical=false
        ExplicitIntegrityKey (1,1) logical=false
        TXSecurityContext struct=struct()
        RXSecurityContext struct=struct()
        PendingRXSecurityContext struct=struct()
        SecurityPreviews
        SecurityGeneration (1,1) double=0
        TXSecurityProcedure struct=struct()
        RXSecurityProcedure struct=struct()
    end
    methods
        function identity=endpointSecurityIdentity(obj,endpoint)
            endpoint=upper(string(endpoint));
            assert(isscalar(endpoint)&&any(endpoint==["TX","RX"]), ...
                'sixgr:pdcp:SecurityActivation','An explicit TX or RX endpoint is required.');
            if endpoint=="TX",context=obj.TXSecurityContext;
            else,context=obj.RXSecurityContext;end
            identity=struct('ContextID',"",'IntegrityAlgorithm',obj.IntegrityAlgorithm, ...
                'CipherAlgorithm',obj.CipherAlgorithm,'Source',"explicit_configured_component_security");
            if ~isempty(fieldnames(context))
                identity.ContextID=string(context.ContextID);
                identity.IntegrityAlgorithm=string(context.IntegrityAlgorithm);
                identity.CipherAlgorithm=string(context.CipherAlgorithm);
                identity.Source="original_endpoint_security_context";
            end
        end

        function obj=PDCPBearerEntity(config)
            required=["UEID","BearerID","Bearer","Direction","BearerType", ...
                "SNBits","ConfigurationEpoch","CipherAlgorithm", ...
                "IntegrityAlgorithm"];
            if ~all(isfield(config,required))
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "PDCP bearer configuration is incomplete.");
            end
            obj.UEID=string(config.UEID);obj.BearerID=string(config.BearerID);
            obj.Bearer=double(config.Bearer);obj.Direction=double(config.Direction);
            obj.BearerType=upper(string(config.BearerType));
            obj.SNBits=double(config.SNBits);
            obj.ConfigurationEpoch=double(config.ConfigurationEpoch);
            obj.CipherAlgorithm=upper(string(config.CipherAlgorithm));
            obj.IntegrityAlgorithm=upper(string(config.IntegrityAlgorithm));
            if ~ismember(obj.CipherAlgorithm,["NEA0","128-NEA2"]) || ...
                    ~ismember(obj.IntegrityAlgorithm,["NIA0","128-NIA2"])
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Unsupported strict PDCP security algorithm.");
            end
            initialCount=double(localField(config,"InitialCount",0));
            obj.TX=sixgr.l2.pdcp18.PDCPCountState(obj.SNBits, ...
                floor(initialCount/2^obj.SNBits),mod(initialCount,2^obj.SNBits));
            obj.RX=sixgr.l2.pdcp18.PDCPReorderingState(obj.SNBits,initialCount, ...
                double(localField(config,"ReorderingTime_s",inf)), ...
                double(localField(config,"SampleRateHz",NaN)),double(localField(config,"ClockEpoch",NaN)));
            obj.SDAPHeaderPresent=logical(localField(config,"SDAPHeaderPresent",false));
            assert(any(obj.BearerType==["SRB","DRB"]) && ...
                (obj.BearerType~="SRB" || (obj.SNBits==12 && ~obj.SDAPHeaderPresent)), ...
                'sixgr:pdcp:MalformedPDU','SRB requires12-bit SN and has no SDAP header.');
            obj.BufferedPayloads=containers.Map('KeyType','double','ValueType','any');
            discardTime=double(localField(config,'DiscardTime_s',inf));
            assert(isscalar(discardTime)&&~isnan(discardTime)&&discardTime>0, ...
                'sixgr:pdcp:DiscardClock','Discard timer must be a positive duration or infinity.');
            if isfinite(discardTime)
                assert(obj.BearerType=="DRB",'sixgr:pdcp:DiscardClock','Configured TX discard timer applies to DRBs.');
                obj.DiscardState=sixgr.l2.pdcp18.PDCPDiscardTimerState( ...
                    config.SampleRateHz,config.ClockEpoch,discardTime);
            end
            obj.SecurityPreviews=containers.Map('KeyType','char','ValueType','any');
            obj.ExplicitCipherKey=isfield(config,'CipherKey')&&isa(config.CipherKey,'uint8')&&numel(config.CipherKey)==16;
            obj.ExplicitIntegrityKey=isfield(config,'IntegrityKey')&&isa(config.IntegrityKey,'uint8')&&numel(config.IntegrityKey)==16;
            obj.CipherKey=uint8(localField(config,"CipherKey",zeros(1,16)));
            obj.IntegrityKey=uint8(localField(config,"IntegrityKey",zeros(1,16)));
            if numel(obj.CipherKey)~=16 || numel(obj.IntegrityKey)~=16
                error("sixgr:pdcp:SecurityContextMissing", ...
                    "PDCP security keys must be 128 bits.");
            end
        end
        function activateSecurity(obj)
            % Explicit configured component boundary; no received RRC claim.
            assert(obj.Active,'sixgr:pdcp:ReleasedBearer','Released bearer cannot activate security.');
            assert(isempty(fieldnames(obj.TXSecurityContext))&&isempty(fieldnames(obj.PendingRXSecurityContext)), ...
                'sixgr:pdcp:SecurityActivation','A staged procedure cannot use configured component activation.');
            assert((obj.CipherAlgorithm=="NEA0"||obj.ExplicitCipherKey)&& ...
                (obj.IntegrityAlgorithm=="NIA0"||obj.ExplicitIntegrityKey), ...
                'sixgr:pdcp:SecurityContextMissing','Non-null security requires original explicit uint8 keys.');
            obj.TXIntegrityActive=true;obj.RXIntegrityActive=true;
            obj.TXCipheringActive=true;obj.RXCipheringActive=true;
            obj.SecurityActive=true;obj.SecurityGeneration=obj.SecurityGeneration+1;
        end
        function stageSecurityContext(obj,endpoint,context)
            % Core key derivation is an explicitly declared input boundary.
            % This method does not claim NAS/AKA or activate either endpoint.
            endpoint=upper(string(endpoint));obj.validateSecurityContext(context);
            assert(obj.Active&&any(endpoint==["TX","RX"]), ...
                'sixgr:pdcp:SecurityContextMissing','Invalid active security endpoint.');
            if endpoint=="TX"
                assert(~obj.TXIntegrityActive&&~obj.TXCipheringActive, ...
                    'sixgr:pdcp:SecurityActivation','Active TX key replacement requires reconfiguration.');
                obj.TXSecurityContext=context;
            else
                assert(~obj.RXIntegrityActive&&~obj.RXCipheringActive, ...
                    'sixgr:pdcp:SecurityActivation','Active RX key replacement requires reconfiguration.');
                obj.PendingRXSecurityContext=context;
            end
            obj.SecurityGeneration=obj.SecurityGeneration+1;
        end

        function activateTransmitIntegrity(obj,contextID,receipt)
            obj.validateTransmitIntegrity(contextID,receipt);
            obj.TXSecurityProcedure=receipt;
            obj.TXIntegrityActive=true;obj.SecurityGeneration=obj.SecurityGeneration+1;
            obj.updateSecurityActive();
        end

        function validateTransmitIntegrity(obj,contextID,receipt)
            context=obj.TXSecurityContext;
            obj.validateSecurityReceipt(context,contextID,receipt,"TX");
            assert(any(string(receipt.Purpose)==["security_command_issued","security_command_verified"]), ...
                'sixgr:pdcp:SecurityActivation','TX integrity needs an issued or verified original security command.');
            assert(~obj.TXIntegrityActive&&~obj.TXCipheringActive, ...
                'sixgr:pdcp:SecurityActivation','TX integrity is already active.');
        end

        function [payload,token]=previewInitialIntegrityReceive(obj,pdu,time)
            assert(obj.Active&&obj.BearerType=="SRB"&&~obj.RXIntegrityActive&&~obj.RXCipheringActive, ...
                'sixgr:pdcp:SecurityActivation','Initial security verification requires an inactive SRB receiver.');
            context=obj.PendingRXSecurityContext;obj.validateSecurityContext(context);
            assert(context.IntegrityAlgorithm=="128-NIA2", ...
                'sixgr:pdcp:SecurityContextMissing','Initial normal-service SRB security requires actual supported integrity.');
            sample=time*context.SampleRateHz;
            assert(isfinite(time)&&isscalar(time)&&time>=0&&abs(sample-round(sample))<=max(1e-7,8*eps(sample)), ...
                'sixgr:pdcp:SecurityClock','Security observation requires its original sample boundary.');
            snapshot=obj.RX.snapshot();preview=obj.RX.copy();preview.advance(time);
            [payload,~,count]=obj.decodeVerified(pdu,preview,true,false,context);
            assert(~preview.alreadyReceived(count),'sixgr:pdcp:SecurityReplay','Initial security PDU is duplicate or below RX_DELIV.');
            header=sixgr.l2.pdcp18.PDCPHeaderCodec.decode(obj.BearerType,obj.SNBits,pdu);
            ready=preview.receive(header.SN,time);
            assert(any(ready==count),'sixgr:pdcp:InitialSecurityNotDeliverable', ...
                'An initial security command cannot activate or reach RRC before its PDCP delivery boundary.');
            token=string(java.util.UUID.randomUUID());
            obj.SecurityPreviews(char(token))=struct('PDU',pdu,'Payload',payload,'Count',count, ...
                'Time',time,'AtSample',round(sample),'Context',context,'RXSnapshot',snapshot, ...
                'Generation',obj.SecurityGeneration,'PDCPPDUSHA256',sixgr.protocol.ProtocolHash.bytes(pdu), ...
                'RRCPayloadSHA256',sixgr.protocol.ProtocolHash.bytes(payload));
        end

        function validateInitialIntegrityReceive(obj,token,receipt)
            key=char(string(token));
            assert(isKey(obj.SecurityPreviews,key),'sixgr:pdcp:SecurityReplay','Missing or already consumed security observation.');
            original=obj.SecurityPreviews(key);
            assert(obj.Active&&~obj.RXIntegrityActive&&~obj.RXCipheringActive&& ...
                original.Generation==obj.SecurityGeneration&&isequaln(original.RXSnapshot,obj.RX.snapshot())&& ...
                isequaln(original.Context,obj.PendingRXSecurityContext), ...
                'sixgr:pdcp:StaleSecurityObservation','Original security receiver/context state has changed.');
            obj.validateSecurityReceipt(original.Context,original.Context.ContextID,receipt,"RX");
            assert(isfield(receipt,'PDCPCount')&&any(string(receipt.Purpose)==["security_command_verified","security_complete_verified"])&& ...
                string(receipt.PDCPPDUSHA256)==original.PDCPPDUSHA256&& ...
                string(receipt.RRCPayloadSHA256)==original.RRCPayloadSHA256&& ...
                receipt.AtSample==original.AtSample&&receipt.PDCPCount==original.Count, ...
                'sixgr:pdcp:SecurityActivation','Validated RRC result differs from the original authenticated PDU or clock.');
        end

        function [payloads,counts]=previewInitialIntegrityCompletion(obj,token,receipt)
            obj.validateInitialIntegrityReceive(token,receipt);
            original=obj.SecurityPreviews(char(string(token)));preview=obj.RX.copy();
            counts=preview.advance(original.Time);
            header=sixgr.l2.pdcp18.PDCPHeaderCodec.decode(obj.BearerType,obj.SNBits,original.PDU);
            counts=[counts preview.receive(header.SN,original.Time)];
            payloads=cell(1,numel(counts));
            for k=1:numel(counts)
                if counts(k)==original.Count,payloads{k}=original.Payload;
                else
                    assert(isKey(obj.BufferedPayloads,counts(k)), ...
                        'sixgr:pdcp:StaleSecurityObservation','Projected completion lacks original buffered bytes.');
                    payloads{k}=obj.BufferedPayloads(counts(k));
                end
            end
        end

        function [delivered,counts]=commitInitialIntegrityReceive(obj,token,receipt)
            obj.validateInitialIntegrityReceive(token,receipt);
            key=char(string(token));original=obj.SecurityPreviews(key);
            % The RRC adapter validates the exact ASN.1 transaction/algorithm
            % before this commit. Hash agreement alone is not an RF receipt.
            obj.RXSecurityContext=original.Context;obj.RXSecurityProcedure=receipt;obj.RXIntegrityActive=true;
            [delivered,counts]=obj.receive(original.PDU,original.Time);
            remove(obj.SecurityPreviews,key);obj.updateSecurityActive();
        end

        function cancelInitialIntegrityReceive(obj,token)
            key=char(string(token));
            assert(isKey(obj.SecurityPreviews,key),'sixgr:pdcp:SecurityReplay','Unknown or already consumed security observation.');
            remove(obj.SecurityPreviews,key);
        end

        function activateCiphering(obj,endpoint,contextID,receipt)
            obj.validateCiphering(endpoint,contextID,receipt);
            endpoint=upper(string(endpoint));
            if endpoint=="TX",obj.TXCipheringActive=true;else,obj.RXCipheringActive=true;end
            obj.SecurityGeneration=obj.SecurityGeneration+1;obj.updateSecurityActive();
        end

        function validateCiphering(obj,endpoint,contextID,receipt)
            endpoint=upper(string(endpoint));
            assert(any(endpoint==["TX","RX"]),'sixgr:pdcp:SecurityActivation','Unknown ciphering endpoint.');
            if endpoint=="TX",context=obj.TXSecurityContext;active=obj.TXIntegrityActive;cipher=obj.TXCipheringActive;prior=obj.TXSecurityProcedure;
            else,context=obj.RXSecurityContext;active=obj.RXIntegrityActive;cipher=obj.RXCipheringActive;prior=obj.RXSecurityProcedure;end
            obj.validateSecurityReceipt(context,contextID,receipt,endpoint);
            assert(active&&~cipher&&~isempty(fieldnames(prior))&& ...
                receipt.RRCTransactionID==prior.RRCTransactionID&&receipt.AtSample>=prior.AtSample&& ...
                any(string(receipt.Purpose)==["security_complete_submitted","security_complete_verified"]), ...
                'sixgr:pdcp:SecurityActivation','Ciphering follows the original unciphered Complete submission/verification.');
        end

        function validateCipheringAfterInitialReceive(obj,token,receiveReceipt,cipherReceipt)
            obj.validateInitialIntegrityReceive(token,receiveReceipt);
            original=obj.SecurityPreviews(char(string(token)));context=original.Context;
            obj.validateSecurityReceipt(context,context.ContextID,cipherReceipt,"RX");
            assert(receiveReceipt.RRCTransactionID==cipherReceipt.RRCTransactionID&& ...
                cipherReceipt.AtSample>=receiveReceipt.AtSample&& ...
                string(receiveReceipt.Purpose)=="security_complete_verified"&& ...
                string(cipherReceipt.Purpose)=="security_complete_verified", ...
                'sixgr:pdcp:SecurityActivation','Initial RX ciphering needs the same verified Complete.');
        end

        function validatePeerSecurityContexts(obj,peer,endpoint,peerEndpoint)
            % Keys are compared privately and are never returned in receipts.
            assert(isa(peer,'sixgr.l2.pdcp18.PDCPBearerEntity')&&obj.Active&&peer.Active&& ...
                obj.BearerType=="SRB"&&peer.BearerType=="SRB"&&obj.Bearer==peer.Bearer&& ...
                obj.UEID==peer.UEID&&obj.BearerID==peer.BearerID&& ...
                obj.ConfigurationEpoch==peer.ConfigurationEpoch&&obj.Direction~=peer.Direction, ...
                'sixgr:pdcp:SecurityPairScope','One original SRB with opposite directions is required.');
            a=obj.pairedContext(endpoint);b=peer.pairedContext(peerEndpoint);
            obj.validateSecurityContext(a);peer.validateSecurityContext(b);
            names={'CipherAlgorithm','IntegrityAlgorithm','CipherKey','IntegrityKey', ...
                'SampleRateHz','ClockEpoch','KeySource'};
            for k=1:numel(names)
                assert(isequaln(a.(names{k}),b.(names{k})), ...
                    'sixgr:pdcp:SecurityPairScope','Directional security contexts disagree.');
            end
        end

        function pdu=transmit(obj,sdu,time)
            if nargin<3,time=0;end
            assert(obj.Active,'sixgr:pdcp:ReleasedBearer','Released PDCP bearer cannot transmit.');
            sdu=uint8(sdu(:).');
            assert(numel(sdu)<=9000,'sixgr:pdcp:SDUSizeExceeded', ...
                'TS38.323 V18.5.0 4.3.1 limits the PDCP SDU to9000 bytes.');
            count=double(obj.TX.current());sn=double(obj.TX.SN);
            header=sixgr.l2.pdcp18.PDCPHeaderCodec.encode( ...
                obj.BearerType,obj.SNBits,sn);
            % TS 38.323 V18.5.0 5.8/5.9: protect plaintext first;
            % cipher data and MAC-I, excluding the SDAP header/control PDU.
            payload=sdu;
            macI=uint8([]);
            if obj.BearerType=="SRB", macI=zeros(1,4,'uint8'); end
            if obj.TXIntegrityActive && obj.endpointAlgorithm("TX","IntegrityAlgorithm")=="128-NIA2"
                macI=sixgr.l2.pdcp18.PDCPSecurity128.nia2( ...
                    obj.endpointKey("TX","IntegrityKey"),count,obj.Bearer,obj.Direction, ...
                    [header payload],8*numel([header payload]));
            end
            body=uint8([payload macI]);
            clearBytes=obj.clearSDAPBytes(payload);
            body=obj.applyCipher(body,clearBytes,count,"TX");
            pdu=uint8([header body]);
            if ~isempty(obj.DiscardState)
                obj.advanceTransmit(time);
                obj.DiscardState=obj.DiscardState.retain(count,sdu,pdu,obj.discardSample(time));
            end
            obj.TX.advance();
        end
        function [delivered,counts]=receive(obj,pdu,time)
            assert(obj.Active,'sixgr:pdcp:ReleasedBearer','Released PDCP bearer cannot receive.');
            assert(obj.RXIntegrityActive||isempty(fieldnames(obj.PendingRXSecurityContext)), ...
                'sixgr:pdcp:InitialSecurityVerificationRequired','Staged initial security requires explicit verify/decode/commit.');
            if nargin<3,time=obj.RX.LastTime_s;end
            % Verify against an isolated clock/COUNT preview. Invalid integrity
            % must not consume timer deliveries or mutate the live RX window.
            preview=obj.RX.copy();preview.advance(time);
            [payload,sn,count]=obj.decodeVerified(pdu,preview,obj.RXIntegrityActive,obj.RXCipheringActive,obj.RXSecurityContext);
            [delivered,counts]=obj.advance(time);
            if ~obj.RX.alreadyReceived(count),obj.BufferedPayloads(count)=payload;end
            ready=obj.RX.receive(sn,time);obj.DuplicateCount=obj.RX.DuplicateCount;
            delivered=[delivered obj.releasePayloads(ready)];counts=[counts ready];
            obj.SecurityGeneration=obj.SecurityGeneration+1;
        end
        function [delivered,counts]=advance(obj,time)
            if ~obj.Active,delivered={};counts=[];return;end
            obj.advanceTransmit(time);
            counts=obj.RX.advance(time);
            delivered=obj.releasePayloads(counts);
        end
        function rows=takeTransmitDiscards(obj)
            rows=obj.PendingTransmitDiscards;obj.PendingTransmitDiscards=struct([]);
        end
        function disposition=confirmLowerLayerDelivery(obj,count,pduHash,time)
            disposition="discard_timer_not_configured";
            if isempty(obj.DiscardState),return;end
            % Equal-sample ordering policy: expiry precedes ACK processing.
            % This simulator tie rule is not prescribed by TS38.323. A
            % later ACK never changes the original expiry or drops sent RLC bytes.
            obj.advanceTransmit(time);
            [obj.DiscardState,disposition]=obj.DiscardState.confirmLowerLayerDelivery(count,pduHash,obj.discardSample(time));
        end
        function time=nextDiscardExpiry(obj)
            time=inf;
            if obj.Active&&~isempty(obj.DiscardState)
                time=obj.DiscardState.nextTimerExpiry()/obj.DiscardState.SampleRateHz;
            end
        end
        function sdus=pullSDUs(obj),sdus=obj.Delivered;obj.Delivered={};end
        function [payloads,counts]=release(obj)
            % TS38.323 5.1.3: release drains received DRB SDUs in COUNT order.
            counts=[];payloads={};
            if obj.Active && obj.BearerType=="DRB"
                counts=sort(cell2mat(obj.BufferedPayloads.keys));
                payloads=obj.releasePayloads(counts);
            end
            obj.Active=false;obj.BufferedPayloads=containers.Map('KeyType','double','ValueType','any');
            obj.SecurityPreviews=containers.Map('KeyType','char','ValueType','any');
            obj.SecurityGeneration=obj.SecurityGeneration+1;
            if ~isempty(obj.DiscardState),obj.DiscardState=obj.DiscardState.release();end
        end
    end
    methods (Access=private)
        function context=pairedContext(obj,endpoint)
            endpoint=upper(string(endpoint));
            assert(any(endpoint==["TX","RX"]),'sixgr:pdcp:SecurityPairScope','Unknown endpoint.');
            if endpoint=="TX",context=obj.TXSecurityContext;
            elseif obj.RXIntegrityActive,context=obj.RXSecurityContext;
            else,context=obj.PendingRXSecurityContext;end
        end
        function sample=discardSample(obj,time)
            value=time*obj.DiscardState.SampleRateHz;sample=round(value);
            assert(isnumeric(time)&&isscalar(time)&&isfinite(time)&&time>=0&& ...
                abs(value-sample)<=max(1e-7,8*eps(value)), ...
                'sixgr:pdcp:DiscardClock','TX discard time requires an original sample boundary.');
        end
        function advanceTransmit(obj,time)
            if isempty(obj.DiscardState)||~obj.Active,return;end
            [obj.DiscardState,rows]=obj.DiscardState.advance(obj.discardSample(time));
            if isempty(rows),return;end
            if isempty(obj.PendingTransmitDiscards),obj.PendingTransmitDiscards=rows;
            else,obj.PendingTransmitDiscards=[obj.PendingTransmitDiscards rows];end
        end
        function n=clearSDAPBytes(obj,payload)
            n=0;
            if ~obj.SDAPHeaderPresent, return; end
            assert(~isempty(payload),'sixgr:pdcp:MalformedPDU','Configured SDAP header is missing.');
            n=1;
            if obj.Direction==0 && bitget(payload(1),8)==0
                n=numel(payload); % UL SDAP control PDU, not user data.
            end
        end
        function validateSecurityContext(obj,c)
            required={'ContractVersion','ContextID','UEID','BearerID','Direction','ConfigurationEpoch', ...
                'CipherAlgorithm','IntegrityAlgorithm','CipherKey','IntegrityKey','SampleRateHz','ClockEpoch','KeySource'};
            assert(isstruct(c)&&isscalar(c)&&all(isfield(c,required)), ...
                'sixgr:pdcp:SecurityContextMissing','Explicit scoped security context is incomplete.');
            assert(string(c.ContractVersion)=="PDCP_endpoint_security/v1"&&strlength(string(c.ContextID))>0&& ...
                string(c.UEID)==obj.UEID&&string(c.BearerID)==obj.BearerID&& ...
                c.Direction==obj.Direction&&c.ConfigurationEpoch==obj.ConfigurationEpoch&& ...
                any(string(c.CipherAlgorithm)==["NEA0","128-NEA2"])&&any(string(c.IntegrityAlgorithm)==["NIA0","128-NIA2"])&& ...
                string(c.KeySource)=="configured_preestablished_core_key"&& ...
                isa(c.CipherKey,'uint8')&&isrow(c.CipherKey)&&numel(c.CipherKey)==16&& ...
                isa(c.IntegrityKey,'uint8')&&isrow(c.IntegrityKey)&&numel(c.IntegrityKey)==16&& ...
                isscalar(c.SampleRateHz)&&isfinite(c.SampleRateHz)&&c.SampleRateHz>0&& ...
                isscalar(c.ClockEpoch)&&isfinite(c.ClockEpoch)&&c.ClockEpoch>=0&&c.ClockEpoch==fix(c.ClockEpoch), ...
                'sixgr:pdcp:SecurityContextMissing','Security keys, algorithms, scope or original clock disagree.');
        end

        function validateSecurityReceipt(obj,c,contextID,r,endpoint)
            obj.validateSecurityContext(c);
            required={'ContractVersion','ContextID','UEID','BearerID','Direction','ConfigurationEpoch', ...
                'Endpoint','Purpose','RRCTransactionID','RRCPayloadSHA256','PDCPPDUSHA256', ...
                'OriginalObservationSHA256','AtSample','SampleRateHz','ClockEpoch','EvidenceBoundary'};
            assert(isstruct(r)&&isscalar(r)&&all(isfield(r,required)), ...
                'sixgr:pdcp:SecurityActivation','Original RRC security boundary is incomplete.');
            hashes=[string(r.RRCPayloadSHA256),string(r.OriginalObservationSHA256)];
            hashValid=true;
            for k=1:numel(hashes),hashValid=hashValid&&~isempty(regexp(char(hashes(k)),'^[0-9a-f]{64}$','once'));end
            assert(obj.Active&&string(r.ContractVersion)=="validated_RRC_security_boundary/v1"&& ...
                string(r.ContextID)==string(contextID)&&string(contextID)==string(c.ContextID)&& ...
                string(r.UEID)==obj.UEID&&string(r.BearerID)==obj.BearerID&& ...
                r.Direction==obj.Direction&&r.ConfigurationEpoch==obj.ConfigurationEpoch&& ...
                string(r.Endpoint)==endpoint&&ismember(r.RRCTransactionID,0:3)&& ...
                r.SampleRateHz==c.SampleRateHz&&r.ClockEpoch==c.ClockEpoch&& ...
                isscalar(r.AtSample)&&isfinite(r.AtSample)&&r.AtSample>=0&&r.AtSample==fix(r.AtSample)&& ...
                hashValid&&any(string(r.EvidenceBoundary)==["declared_component","original_shared_receiver","original_RRC_submission"]), ...
                'sixgr:pdcp:SecurityActivation','RRC security boundary scope, clock or original message identity disagrees.');
        end

        function [payload,sn,count]=decodeVerified(obj,pdu,preview,integrity,cipher,context)
            assert(isa(pdu,'uint8')&&isrow(pdu)&&~isempty(pdu), ...
                'sixgr:pdcp:MalformedPDU','PDCP reception requires original byte-vector octets.');
            decoded=sixgr.l2.pdcp18.PDCPHeaderCodec.decode(obj.BearerType,obj.SNBits,pdu);
            sn=decoded.SN;count=preview.inferCount(sn);
            assert(count>=0&&count<=2^32-1,'sixgr:pdcp:ReorderingStateViolation','Received COUNT is outside32 bits.');
            body=decoded.Payload;
            cipherAlgorithm=obj.CipherAlgorithm;integrityAlgorithm=obj.IntegrityAlgorithm;
            if ~isempty(fieldnames(context))
                cipherAlgorithm=string(context.CipherAlgorithm);integrityAlgorithm=string(context.IntegrityAlgorithm);
            end
            integrityBytes=4*double(obj.BearerType=="SRB"||(integrity&&integrityAlgorithm=="128-NIA2"));
            assert(numel(body)>=integrityBytes,'sixgr:pdcp:IntegrityFailure','PDCP PDU has no MAC-I.');
            clearBytes=obj.clearSDAPBytes(body(1:end-integrityBytes));
            if isempty(fieldnames(context)),cipherKey=obj.CipherKey;integrityKey=obj.IntegrityKey;
            else,cipherKey=context.CipherKey;integrityKey=context.IntegrityKey;end
            if cipher&&cipherAlgorithm=="128-NEA2"
                tail=sixgr.l2.pdcp18.PDCPSecurity128.nea2(cipherKey,count,obj.Bearer,obj.Direction, ...
                    body(clearBytes+1:end),8*(numel(body)-clearBytes));
                body=uint8([body(1:clearBytes) tail]);
            end
            payload=body(1:end-integrityBytes);
            if integrity&&integrityAlgorithm=="128-NIA2"
                header=pdu(1:decoded.HeaderBytes);
                sixgr.l2.pdcp18.PDCPSecurity128.verifyNIA2(integrityKey,count,obj.Bearer,obj.Direction, ...
                    [header payload],8*numel([header payload]),body(end-3:end));
            end
        end

        function algorithm=endpointAlgorithm(obj,endpoint,name)
            if endpoint=="TX",context=obj.TXSecurityContext;else,context=obj.RXSecurityContext;end
            if isempty(fieldnames(context)),algorithm=obj.(name);else,algorithm=string(context.(name));end
        end

        function key=endpointKey(obj,endpoint,name)
            if endpoint=="TX",context=obj.TXSecurityContext;else,context=obj.RXSecurityContext;end
            if isempty(fieldnames(context)),key=obj.(name);else,key=context.(name);end
        end

        function body=applyCipher(obj,body,clearBytes,count,endpoint)
            if endpoint=="TX",active=obj.TXCipheringActive;else,active=obj.RXCipheringActive;end
            if active&&obj.endpointAlgorithm(endpoint,"CipherAlgorithm")=="128-NEA2"
                encrypted=sixgr.l2.pdcp18.PDCPSecurity128.nea2( ...
                    obj.endpointKey(endpoint,"CipherKey"),count,obj.Bearer,obj.Direction, ...
                    body(clearBytes+1:end),8*(numel(body)-clearBytes));
                body=uint8([body(1:clearBytes) encrypted]);
            end
        end

        function updateSecurityActive(obj)
            obj.SecurityActive=obj.TXIntegrityActive&&obj.RXIntegrityActive&&obj.TXCipheringActive&&obj.RXCipheringActive;
        end

        function payloads=releasePayloads(obj,counts)
            payloads=cell(1,numel(counts));
            for k=1:numel(counts)
                assert(isKey(obj.BufferedPayloads,counts(k)), ...
                    'sixgr:pdcp:ReorderingStateViolation','Delivered COUNT has no original decoded payload.');
                payloads{k}=obj.BufferedPayloads(counts(k));
                remove(obj.BufferedPayloads,counts(k));
                obj.Delivered{end+1}=payloads{k};
            end
        end
    end
end
function value=localField(config,name,defaultValue)
if isfield(config,name),value=config.(name);else,value=defaultValue;end
end
