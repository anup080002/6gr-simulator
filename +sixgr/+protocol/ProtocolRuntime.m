classdef ProtocolRuntime < handle
    %PROTOCOLRUNTIME Bounded connected-mode SDAP/PDCP/RLC execution path.
    %
    % This runtime deliberately owns protocol identities and never infers
    % grant-level truth.  The returned RLC PDU can be handed to the MAC/PHY
    % layer by a caller-provided callback.

    properties (SetAccess = private)
        UEID (1,1) string
        BearerID (1,1) string
        QFI (1,1) double
        PDCPSNBits (1,1) double
        RLCSNBits (1,1) double
        ConfigurationEpoch (1,1) double
        Direction (1,1) string
        DRBID (1,1) double
        PduSessionID (1,1) double
        LCID (1,1) double
        BearerType (1,1) string="DRB"
        SRBID (1,1) double=1
        Events sixgr.protocol.ProtocolEventStore
        Lineage sixgr.protocol.ProtocolLineageLedger
        PacketsTransmitted (1,1) double = 0
        PacketsDelivered (1,1) double = 0
        DuplicateDiscards (1,1) double = 0
        Active (1,1) logical=true
    end

    properties (Access = private)
        SDAPEntity sixgr.l2.sdap18.SDAPEntity
        PDCPEntity sixgr.l2.pdcp18.PDCPBearerEntity
        RLCEntity sixgr.l2.rlc18.RLCAMEntity
        Delivered containers.Map
        MACSubmit
        ReceivedPacketByCount
        TransmitPackets cell={}
        ActiveTransmitPacket struct=struct()
        EnqueuedPackets
        TransmitMode (1,1) string=""
        PreparedSegments
        TransmittedPacketsByRLCCount
        UpperLayerIndications struct=struct([])
        DiscardEvents struct=struct([])
        InitialSecurityReceivePending (1,1) logical=false
        InitialSecurityObservations
        EndpointAdmission
        EndpointLastTime_s (1,1) double=0
        SecurityFailureReceipts
        PendingSecurityIndications struct=struct([])
        SecurityObservationClock struct=struct()
        SecurityObservationContext struct=struct()
        OriginalConnectionScope struct=struct()
        LowerLayerSubmissionReceipts
        OriginalSRBDeliveryReceipts
        ReceivedWireEvidenceByCount
    end

    methods
        function obj = ProtocolRuntime(config, options)
            arguments
                config (1,1) struct
                options.MACSubmit = []
            end
            required = ["UEID","BearerID","QFI","PDCPSNBits", ...
                "RLCSNBits","ConfigurationEpoch"];
            if ~all(isfield(config, required))
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Protocol runtime configuration is incomplete.");
            end
            obj.UEID = string(config.UEID);
            obj.BearerID = string(config.BearerID);
            obj.QFI = double(config.QFI);
            obj.PDCPSNBits = double(config.PDCPSNBits);
            obj.RLCSNBits = double(config.RLCSNBits);
            obj.ConfigurationEpoch = double(config.ConfigurationEpoch);
            obj.Direction = upper(string(localField(config,"Direction","UL")));
            obj.BearerType=upper(string(localField(config,"BearerType","DRB")));
            obj.SRBID=double(localField(config,"SRBID",1));
            assert(any(obj.BearerType==["DRB","SRB"]) && ...
                (obj.BearerType~="SRB" || (obj.PDCPSNBits==12 && obj.RLCSNBits==12 && ...
                ismember(obj.SRBID,[1 2 3]))),'sixgr:protocol:UnsupportedCapability', ...
                'Supported SRB uses explicitSRB1..3 with PDCP12 and RLC AM12.');
            if ~any(obj.Direction == ["DL","UL"])
                error("sixgr:protocol:UnsupportedDirection", ...
                    "Protocol runtime direction must be DL or UL, not '%s'.", ...
                    obj.Direction);
            end
            obj.DRBID = double(localField(config,"DRBID",1));
            obj.PduSessionID = double(localField(config,"PduSessionID",1));
            obj.LCID = double(localField(config,"LCID",4));
            if ~(isscalar(obj.LCID) && isfinite(obj.LCID) && ...
                    obj.LCID >= 1 && obj.LCID <= 32 && obj.LCID == fix(obj.LCID))
                error("sixgr:protocol:InvalidLCID", ...
                    "Protocol runtime LCID must be an integer in [1, 32].");
            end
            mapping = struct("QFI",obj.QFI,"DRBID",obj.DRBID);
            % TS38.323 5.8: the five-bit security BEARER is RB identity-1.
            assert(ismember(obj.DRBID,1:32),'sixgr:protocol:UnsupportedCapability','DRB identity must be1..32.');
            securityBearer=obj.DRBID-1;
            if obj.BearerType=="DRB"
                obj.SDAPEntity = sixgr.l2.sdap18.SDAPEntity(struct( ...
                "UEID",obj.UEID,"Direction",obj.Direction, ...
                "PduSessionID",obj.PduSessionID, ...
                "DefaultDRBID",obj.DRBID,"ConfigurationEpoch", ...
                obj.ConfigurationEpoch,"Mappings",mapping));
            else
                assert(obj.LCID==obj.SRBID,'sixgr:protocol:UnsupportedCapability','SRB LCID must match its installed mapping.');
                securityBearer=obj.SRBID-1;
            end
            admissionMode=string(localField(config,'EndpointAdmissionMode',"component_preconfigured_both"));
            admissionScope=localField(config,'EndpointAdmissionScope',struct());
            if admissionMode=="original_reconfiguration_required"
                obj.EndpointAdmission=sixgr.protocol.DRBEndpointAdmission(admissionScope,admissionMode);
                assert(obj.BearerType=="DRB"&&all(isfield(config,{'SampleRateHz','ClockEpoch'})), ...
                    'sixgr:protocol:DRBAdmissionScope','Original DRB requires the native protocol clock.');
                base=config;fields=intersect(fieldnames(base), ...
                    {'EndpointAdmissionMode','EndpointAdmissionScope','OriginalConnectionScope'});
                base=rmfield(base,fields);
                assert(string(admissionScope.UEID)==obj.UEID&&string(admissionScope.BearerID)==obj.BearerID&& ...
                    admissionScope.DRBID==obj.DRBID&&admissionScope.LCID==obj.LCID&& ...
                    string(admissionScope.Direction)==obj.Direction&& ...
                    admissionScope.ConfigurationEpoch==obj.ConfigurationEpoch&& ...
                    admissionScope.SampleRateHz==config.SampleRateHz&&admissionScope.ClockEpoch==config.ClockEpoch&& ...
                    string(admissionScope.ProtocolConfigurationSHA256)==sixgr.l2.mac.MACHash.of(orderfields(base)), ...
                    'sixgr:protocol:DRBAdmissionScope','Original DRB scope must bind this exact constructed configuration.');
            else
                obj.EndpointAdmission=sixgr.protocol.SRB1EndpointAdmission(admissionScope,admissionMode);
            end
            if admissionMode=="original_setup_required"
                assert(obj.BearerType=="SRB"&&obj.SRBID==1&&any(obj.Direction==["DL","UL"]), ...
                    'sixgr:protocol:SRB1AdmissionScope','Received Setup gating applies to the initial directional SRB1 owner.');
                assert(all(isfield(config,{'SampleRateHz','ClockEpoch'})), ...
                    'sixgr:protocol:SRB1AdmissionScope','Original Setup admission requires the native protocol clock.');
                base=config;removeNames=intersect(fieldnames(base),{'EndpointAdmissionMode','EndpointAdmissionScope','OriginalConnectionScope'});
                base=rmfield(base,removeNames);
                expectedHash=sixgr.l2.mac.MACHash.of(orderfields(base));
                assert(string(admissionScope.UEID)==obj.UEID&&admissionScope.SRBID==obj.SRBID&& ...
                    admissionScope.LCID==obj.LCID&&string(admissionScope.Direction)==obj.Direction&& ...
                    admissionScope.ConfigurationEpoch==obj.ConfigurationEpoch&& ...
                    admissionScope.SampleRateHz==config.SampleRateHz&&admissionScope.ClockEpoch==config.ClockEpoch&& ...
                    string(admissionScope.ProtocolConfigurationSHA256)==expectedHash, ...
                    'sixgr:protocol:SRB1AdmissionScope','Original Setup scope must bind the exact constructed protocol configuration.');
            end
            obj.PDCPEntity = sixgr.l2.pdcp18.PDCPBearerEntity(struct( ...
                "UEID",obj.UEID,"BearerID",obj.BearerID,"Bearer",securityBearer, ...
                "Direction",double(obj.Direction == "DL"), ...
                "BearerType",obj.BearerType,"SNBits", ...
                obj.PDCPSNBits,"ConfigurationEpoch", ...
                obj.ConfigurationEpoch,"CipherAlgorithm", ...
                string(localField(config,"CipherAlgorithm","NEA0")), ...
                "IntegrityAlgorithm", ...
                string(localField(config,"IntegrityAlgorithm","NIA0")), ...
                "CipherKey",uint8(localField(config,"CipherKey",zeros(1,16))), ...
                "IntegrityKey",uint8(localField(config, ...
                "IntegrityKey",zeros(1,16))),"SDAPHeaderPresent",obj.BearerType=="DRB", ...
                "ReorderingTime_s",double(localField(config,"ReorderingTime_s",inf)), ...
                "DiscardTime_s",double(localField(config,"DiscardTime_s",inf)), ...
                "SampleRateHz",double(localField(config,"SampleRateHz",NaN)), ...
                "ClockEpoch",double(localField(config,"ClockEpoch",NaN))));
            if logical(localField(config,"SecurityActive",false))
                assert((string(localField(config,'CipherAlgorithm',"NEA0"))=="NEA0"|| ...
                    (isfield(config,'CipherKey')&&isa(config.CipherKey,'uint8')&&numel(config.CipherKey)==16))&& ...
                    (string(localField(config,'IntegrityAlgorithm',"NIA0"))=="NIA0"|| ...
                    (isfield(config,'IntegrityKey')&&isa(config.IntegrityKey,'uint8')&&numel(config.IntegrityKey)==16)), ...
                    'sixgr:pdcp:SecurityContextMissing','Configured non-null security requires explicit original key octets.');
                obj.PDCPEntity.activateSecurity();
            end
            rlcConfig=struct( ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "Direction",obj.Direction,"ConfigurationEpoch", ...
                obj.ConfigurationEpoch,"SNBits",obj.RLCSNBits, ...
                "PollPDU",double(localField(config,"PollPDU",16)), ...
                "PollByte",double(localField(config,"PollByte",65536)), ...
                "MaxRetxThreshold",double(localField(config, ...
                "MaxRetxThreshold",8)));
            rlcConfig.ARQEnabled=logical(localField(config,'RLCARQEnabled',false));
            if rlcConfig.ARQEnabled
                fs=double(config.SampleRateHz);
                durations=[config.RLCPollRetransmit_s config.RLCReassembly_s config.RLCStatusProhibit_s];
                samples=durations*fs;
                assert(all(isfinite(samples)&samples>=0) && all(abs(samples-round(samples))<=max(1e-7,8*eps(samples))), ...
                    'sixgr:rlc:ARQClock','Configured RLC timers must align to the original sample clock.');
                rlcConfig.ARQConfig=struct('SampleRateHz',fs,'ClockEpoch',config.ClockEpoch, ...
                    'PollRetransmitSamples',round(samples(1)),'ReassemblySamples',round(samples(2)), ...
                    'StatusProhibitSamples',round(samples(3)));
            end
            obj.RLCEntity = sixgr.l2.rlc18.RLCAMEntity(rlcConfig);
            obj.Events = sixgr.protocol.ProtocolEventStore();
            obj.Lineage = sixgr.protocol.ProtocolLineageLedger();
            obj.Delivered = containers.Map('KeyType','char','ValueType','logical');
            obj.ReceivedPacketByCount = containers.Map('KeyType','double','ValueType','any');
            obj.EnqueuedPackets=containers.Map('KeyType','char','ValueType','any');
            obj.PreparedSegments=containers.Map('KeyType','char','ValueType','any');
            obj.TransmittedPacketsByRLCCount=containers.Map('KeyType','double','ValueType','any');
            obj.MACSubmit = options.MACSubmit;
            obj.InitialSecurityObservations=containers.Map('KeyType','char','ValueType','any');
            obj.SecurityFailureReceipts=containers.Map('KeyType','char','ValueType','any');
            obj.LowerLayerSubmissionReceipts=containers.Map('KeyType','char','ValueType','any');
            obj.OriginalSRBDeliveryReceipts=containers.Map('KeyType','char','ValueType','any');
            obj.ReceivedWireEvidenceByCount=containers.Map('KeyType','double','ValueType','any');
            obj.OriginalConnectionScope=localField(config,'OriginalConnectionScope',struct());
            if ~isempty(fieldnames(obj.OriginalConnectionScope))
                c=obj.OriginalConnectionScope;
                required={'ExecutionRunID','UEID','BearerID','ServingCell','RNTI','ConfigurationEpoch', ...
                    'ProtocolConfigurationSHA256','SampleRateHz','ClockEpoch'};
                assert(isstruct(c)&&isscalar(c)&&all(isfield(c,required))&& ...
                    all(isfield(config,{'SampleRateHz','ClockEpoch'})), ...
                    'sixgr:protocol:OriginalSubmissionScope','Complete original connection and clock scope required.');
                base=config;removeNames=intersect(fieldnames(base), ...
                    {'EndpointAdmissionMode','EndpointAdmissionScope','OriginalConnectionScope'});
                base=rmfield(base,removeNames);
                assert(strlength(string(c.ExecutionRunID))>0&&string(c.UEID)==obj.UEID&& ...
                    string(c.BearerID)==obj.BearerID&&c.ConfigurationEpoch==obj.ConfigurationEpoch&& ...
                    c.SampleRateHz==config.SampleRateHz&&c.ClockEpoch==config.ClockEpoch&& ...
                    isscalar(c.ServingCell)&&isfinite(c.ServingCell)&&c.ServingCell>=1&&c.ServingCell==fix(c.ServingCell)&& ...
                    isscalar(c.RNTI)&&isfinite(c.RNTI)&&c.RNTI>=1&&c.RNTI<=65522&&c.RNTI==fix(c.RNTI)&& ...
                    string(c.ProtocolConfigurationSHA256)==sixgr.l2.mac.MACHash.of(orderfields(base)), ...
                    'sixgr:protocol:OriginalSubmissionScope','Connection scope disagrees with the exact runtime configuration.');
            end
            obj.SecurityObservationContext=struct('IntegrityAlgorithm',string(localField(config,'IntegrityAlgorithm',"NIA0")), ...
                'ContextID',"",'Source',"explicit_configured_component_security");
            obj.SecurityObservationClock=struct('SampleRateHz',double(localField(config,'SampleRateHz',NaN)), ...
                'ClockEpoch',double(localField(config,'ClockEpoch',NaN)));
        end

        function state=endpointAdmissionState(obj)
            a=obj.EndpointAdmission;
            state=struct('Mode',a.Mode,'RXEnabled',a.RXEnabled,'TXEnabled',a.TXEnabled, ...
                'LastSample',a.LastSample,'LastRuntimeTime_s',obj.EndpointLastTime_s);
        end

        function next=validateIssuedSetup(obj,receipt,currentSample)
            obj.validateAdmissionClock(currentSample);
            next=obj.EndpointAdmission.admitIssued(receipt,currentSample);
        end

        function admitIssuedSetup(obj,receipt,currentSample)
            next=obj.validateIssuedSetup(receipt,currentSample);
            obj.EndpointAdmission=next;
            obj.EndpointLastTime_s=currentSample/next.Scope.SampleRateHz;
        end

        function next=validateReceivedSetup(obj,receipt,currentSample)
            obj.validateAdmissionClock(currentSample);
            next=obj.EndpointAdmission.admitReceived(receipt,currentSample);
        end

        function admitReceivedSetup(obj,receipt,currentSample)
            next=obj.validateReceivedSetup(receipt,currentSample);
            obj.EndpointAdmission=next;
            obj.EndpointLastTime_s=currentSample/next.Scope.SampleRateHz;
        end

        function scope=endpointAdmissionScope(obj)
            scope=obj.EndpointAdmission.Scope;
        end

        function receipt=originalIssuedReconfigurationReceipt(obj)
            a=obj.EndpointAdmission;
            assert(a.Mode=="original_reconfiguration_required"&&~isempty(fieldnames(a.IssuedReceipt)), ...
                'sixgr:protocol:DRBIssuedReconfigurationRequired','Original issued DRB configuration is required.');
            receipt=a.IssuedReceipt;
        end

        function next=validateIssuedReconfiguration(obj,receipt,currentSample)
            obj.validateAdmissionClock(currentSample,"original_reconfiguration_required");
            next=obj.EndpointAdmission.admitIssued(receipt,currentSample);
        end

        function admitIssuedReconfiguration(obj,receipt,currentSample)
            next=obj.validateIssuedReconfiguration(receipt,currentSample);
            obj.EndpointAdmission=next;
            obj.EndpointLastTime_s=currentSample/next.Scope.SampleRateHz;
        end

        function next=validateReceivedReconfiguration(obj,receipt,currentSample)
            obj.validateAdmissionClock(currentSample,"original_reconfiguration_required");
            next=obj.EndpointAdmission.admitReceived(receipt,currentSample);
        end

        function admitReceivedReconfiguration(obj,receipt,currentSample)
            next=obj.validateReceivedReconfiguration(receipt,currentSample);
            obj.EndpointAdmission=next;
            obj.EndpointLastTime_s=currentSample/next.Scope.SampleRateHz;
        end

        function next=validateReceivedReconfigurationComplete(obj,receipt,currentSample)
            obj.validateAdmissionClock(currentSample,"original_reconfiguration_required");
            next=obj.EndpointAdmission.admitComplete(receipt,currentSample);
        end

        function admitReceivedReconfigurationComplete(obj,receipt,currentSample)
            next=obj.validateReceivedReconfigurationComplete(receipt,currentSample);
            obj.EndpointAdmission=next;
            obj.EndpointLastTime_s=currentSample/next.Scope.SampleRateHz;
        end

        function stageSecurityContext(obj,endpoint,context)
            assert(obj.Active,'sixgr:protocol:ReleasedBearer','Released bearer cannot stage security.');
            obj.EndpointAdmission.require(endpoint);
            clock=obj.SecurityObservationClock;
            if isfinite(clock.SampleRateHz)&&isfinite(clock.ClockEpoch)
                assert(isstruct(context)&&isscalar(context)&&all(isfield(context,{'SampleRateHz','ClockEpoch'}))&& ...
                    isequal(context.SampleRateHz,clock.SampleRateHz)&&isequal(context.ClockEpoch,clock.ClockEpoch), ...
                    'sixgr:protocol:SecurityActivationClock','Staged security must retain the original protocol sample clock.');
            end
            obj.PDCPEntity.stageSecurityContext(endpoint,context);
            if upper(string(endpoint))=="RX"
                obj.InitialSecurityReceivePending=true;
                obj.SecurityObservationContext=struct('IntegrityAlgorithm',string(context.IntegrityAlgorithm), ...
                    'ContextID',string(context.ContextID),'Source',"staged_original_endpoint_context");
                obj.SecurityObservationClock=struct('SampleRateHz',double(context.SampleRateHz),'ClockEpoch',double(context.ClockEpoch));
            end
        end

        function validateTransmitIntegrity(obj,contextID,receipt)
            assert(obj.Active,'sixgr:protocol:ReleasedBearer','Released bearer cannot activate security.');
            obj.EndpointAdmission.require('TX');
            obj.PDCPEntity.validateTransmitIntegrity(contextID,receipt);
            obj.validateSecurityEventClock(receipt);
        end

        function activateTransmitIntegrity(obj,contextID,receipt)
            obj.validateTransmitIntegrity(contextID,receipt);
            obj.PDCPEntity.activateTransmitIntegrity(contextID,receipt);
            obj.EndpointLastTime_s=receipt.AtSample/receipt.SampleRateHz;
        end

        function validateCiphering(obj,endpoint,contextID,receipt)
            assert(obj.Active,'sixgr:protocol:ReleasedBearer','Released bearer cannot activate security.');
            obj.EndpointAdmission.require(endpoint);
            obj.PDCPEntity.validateCiphering(endpoint,contextID,receipt);
            obj.validateSecurityEventClock(receipt);
        end

        function activateCiphering(obj,endpoint,contextID,receipt)
            obj.validateCiphering(endpoint,contextID,receipt);
            obj.PDCPEntity.activateCiphering(endpoint,contextID,receipt);
            obj.EndpointLastTime_s=receipt.AtSample/receipt.SampleRateHz;
        end

        function state=securityState(obj)
            p=obj.PDCPEntity;
            state=struct('TXIntegrityActive',p.TXIntegrityActive,'RXIntegrityActive',p.RXIntegrityActive, ...
                'TXCipheringActive',p.TXCipheringActive,'RXCipheringActive',p.RXCipheringActive, ...
                'TXCount',double(p.TX.current()),'RXState',p.RX.snapshot());
        end

        function cancelInitialIntegrityReceive(obj,token)
            key=char(string(token));
            assert(isKey(obj.InitialSecurityObservations,key), ...
                'sixgr:pdcp:SecurityReplay','No original pending security observation.');
            obj.PDCPEntity.cancelInitialIntegrityReceive(token);
            remove(obj.InitialSecurityObservations,key);
        end

        function validateInitialIntegrityReceive(obj,token,receipt)
            assert(obj.Active,'sixgr:protocol:ReleasedBearer','Released bearer cannot activate security.');
            obj.EndpointAdmission.require('RX');
            key=char(string(token));
            assert(isKey(obj.InitialSecurityObservations,key), ...
                'sixgr:pdcp:SecurityReplay','No original reassembled security observation for this runtime.');
            original=obj.InitialSecurityObservations(key);pdu=original.OriginalPDU;count=original.PDCPCount;
            if isKey(obj.ReceivedPacketByCount,count)
                prior=obj.ReceivedPacketByCount(count);
                assert(string(prior.PacketID)==string(pdu.PacketID), ...
                    'sixgr:protocol:LineageViolation','Security COUNT is owned by another received packet.');
            end
            obj.PDCPEntity.validateInitialIntegrityReceive(token,receipt);
            obj.validateSecurityEventClock(receipt);
            [payloads,counts]=obj.PDCPEntity.previewInitialIntegrityCompletion(token,receipt);
            packetIDs=strings(1,numel(counts));
            for k=1:numel(counts)
                if counts(k)==count,candidate=pdu;
                else
                    assert(isKey(obj.ReceivedPacketByCount,counts(k)), ...
                        'sixgr:protocol:LineageViolation','Projected completion lacks its original packet owner.');
                    candidate=obj.ReceivedPacketByCount(counts(k));
                end
                assert(obj.BearerType=="SRB"&&isfield(candidate,'PacketID')&&isfield(candidate,'PacketSHA256')&& ...
                    sixgr.protocol.ProtocolHash.bytes(payloads{k})==string(candidate.PacketSHA256)&& ...
                    ~isKey(obj.Delivered,char(string(candidate.PacketID))), ...
                    'sixgr:protocol:LineageViolation','Projected original SRB completion has invalid or already delivered bytes.');
                obj.Lineage.validateDelivery(candidate.PacketID,payloads{k});
                packetIDs(k)=string(candidate.PacketID);
            end
            assert(numel(unique(packetIDs))==numel(packetIDs), ...
                'sixgr:protocol:LineageViolation','One security commit cannot deliver the same packet twice.');
        end

        function completions=commitInitialIntegrityReceive(obj,token,receipt)
            obj.validateInitialIntegrityReceive(token,receipt);
            key=char(string(token));original=obj.InitialSecurityObservations(key);
            pdu=original.OriginalPDU;count=original.PDCPCount;
            [payloads,counts]=obj.PDCPEntity.commitInitialIntegrityReceive(token,receipt);
            obj.ReceivedPacketByCount(count)=pdu;
            obj.retainReceivedWireEvidence(count,original.PDCPPDUSHA256,original.AvailableTime_s);
            obj.InitialSecurityReceivePending=false;
            remove(obj.InitialSecurityObservations,key);
            completions=obj.completeReceived(payloads,counts,original.AvailableTime_s);
        end

        function completions=commitReceivedSecurityCommand(obj,token,rxReceipt,ul,ulContextID,txReceipt)
            % Preflight both directional endpoints before either is changed.
            obj.validateSecurityPair(ul,"DL","UL",rxReceipt,txReceipt,"security_command_verified");
            obj.validateInitialIntegrityReceive(token,rxReceipt);
            ul.validateTransmitIntegrity(ulContextID,txReceipt);
            obj.PDCPEntity.validatePeerSecurityContexts(ul.PDCPEntity,'RX','TX');
            completions=obj.commitInitialIntegrityReceive(token,rxReceipt);
            ul.activateTransmitIntegrity(ulContextID,txReceipt);
        end

        function activateSubmittedSecurityComplete(obj,ulContextID,txReceipt,dl,dlContextID,rxReceipt)
            % Original lower-layer submission is supplied by the RRC adapter.
            % This does not invent an RF transmission or peer reception.
            obj.validateSecurityPair(dl,"UL","DL",txReceipt,rxReceipt,"security_complete_submitted");
            obj.validateCiphering('TX',ulContextID,txReceipt);
            dl.validateCiphering('RX',dlContextID,rxReceipt);
            obj.PDCPEntity.validatePeerSecurityContexts(dl.PDCPEntity,'TX','RX');
            obj.activateCiphering('TX',ulContextID,txReceipt);
            dl.activateCiphering('RX',dlContextID,rxReceipt);
        end

        function completions=commitReceivedSecurityComplete(obj,token,rxReceipt,dl,dlContextID,txReceipt)
            obj.validateSecurityPair(dl,"UL","DL",rxReceipt,txReceipt,"security_complete_verified");
            obj.validateInitialIntegrityReceive(token,rxReceipt);
            obj.PDCPEntity.validateCipheringAfterInitialReceive(token,rxReceipt,rxReceipt);
            dl.validateCiphering('TX',dlContextID,txReceipt);
            obj.PDCPEntity.validatePeerSecurityContexts(dl.PDCPEntity,'RX','TX');
            completions=obj.commitInitialIntegrityReceive(token,rxReceipt);
            obj.activateCiphering('RX',rxReceipt.ContextID,rxReceipt);
            dl.activateCiphering('TX',dlContextID,txReceipt);
        end

        function receipt=originalReceivedSRBDelivery(obj,packetID)
            key=char(string(packetID));
            assert(isKey(obj.OriginalSRBDeliveryReceipts,key), ...
                'sixgr:protocol:OriginalDeliveryMissing','No original scoped decoded SRB delivery exists.');
            receipt=obj.OriginalSRBDeliveryReceipts(key);
        end

        function validateOriginalReceivedSRBDelivery(obj,receipt)
            assert(isstruct(receipt)&&isscalar(receipt)&&isfield(receipt,'PacketID'), ...
                'sixgr:protocol:OriginalDeliveryMismatch','Original private SRB delivery is required.');
            assert(isequaln(receipt,obj.originalReceivedSRBDelivery(receipt.PacketID)), ...
                'sixgr:protocol:OriginalDeliveryMismatch','Original decoded SRB delivery changed.');
        end

        function receipt=originalLowerLayerSubmission(obj,packetID)
            key=char(string(packetID));
            assert(isKey(obj.LowerLayerSubmissionReceipts,key), ...
                'sixgr:protocol:OriginalSubmissionMissing','No original scoped PDCP-to-RLC submission exists for this packet.');
            receipt=obj.LowerLayerSubmissionReceipts(key);
        end

        function validateOriginalLowerLayerSubmission(obj,receipt)
            assert(isstruct(receipt)&&isscalar(receipt)&&isfield(receipt,'PacketID'), ...
                'sixgr:protocol:OriginalSubmissionMismatch','An original private submission is required.');
            assert(isequaln(receipt,obj.originalLowerLayerSubmission(receipt.PacketID)), ...
                'sixgr:protocol:OriginalSubmissionMismatch','Original lower-layer submission changed.');
        end

        function packet=enqueuePacket(obj,packetID,payload,time)
            arguments
                obj
                packetID (1,1) string
                payload (1,:) uint8
                time (1,1) double {mustBeFinite,mustBeNonnegative}
            end
            obj.requireEndpointAt('TX',time);
            assert(obj.Active,'sixgr:protocol:ReleasedBearer','Released bearer cannot accept packets.');
            assert(obj.TransmitMode~="legacy_fragment", ...
                'sixgr:protocol:MixedTransmitOwnership','Queued packets and legacy fragments require distinct bearer owners.');
            obj.TransmitMode="queued_packet";
            hash=sixgr.protocol.ProtocolHash.bytes(payload); key=char(packetID);
            if isKey(obj.EnqueuedPackets,key)
                packet=obj.EnqueuedPackets(key);
                assert(packet.PacketSHA256==hash && packet.PacketBytes==numel(payload), ...
                    'sixgr:protocol:LineageViolation','Re-enqueued packet identity has different original bytes.');
                return;
            end
            assert(~isempty(payload),'sixgr:protocol:EmptyApplicationPacket','Application packet cannot be empty.');
            [sdap,sdapHeader]=obj.encodeUpperPayload(payload);
            count=double(obj.PDCPEntity.TX.current());
            encoded=obj.PDCPEntity.transmit(sdap,time);
            obj.processPDCPDiscards();
            headerBytes=2+double(obj.PDCPSNBits==18);
            packet=struct('PacketID',packetID,'PacketSHA256',hash, ...
                'PacketBytes',numel(payload),'PayloadBytes',numel(payload), ...
                'EnqueueTime_s',time,'PDCPCount',count,'PDCPSN',mod(count,2^obj.PDCPSNBits), ...
                'PDCPHeader',encoded(1:headerBytes),'SDAPHeader',sdapHeader, ...
                'ApplicationStartByte',headerBytes+numel(sdapHeader),'RLCSDUBytes',numel(encoded), ...
                'Direction',obj.Direction,'LCID',obj.LCID,'DRBID',obj.DRBID,'QFI',obj.QFI, ...
                'PduSessionID',obj.PduSessionID,'UEID',obj.UEID,'BearerID',obj.BearerID, ...
                'ConfigurationEpoch',obj.ConfigurationEpoch);
            obj.Lineage.addPacket(struct('PacketID',packetID,'PacketBytes',numel(payload),'PayloadSHA256',hash));
            if obj.BearerType=="DRB", obj.Lineage.addNode("SDAP-"+packetID,packetID,"SDAP",numel(sdap)); end
            obj.Lineage.addNode("PDCP-"+string(count),packetID,"PDCP",numel(encoded));
            packet.RLCQueueID=obj.RLCEntity.addSDU(encoded);
            packet.PDCPPDUSHA256=sixgr.protocol.ProtocolHash.bytes(encoded);
            obj.TransmitPackets{end+1}=packet; obj.EnqueuedPackets(key)=packet;
            obj.retainLowerLayerSubmission(packet,encoded,time);
            obj.PacketsTransmitted=obj.PacketsTransmitted+1;
            obj.Events.append(time,"RLC","ORIGINAL_SDU_QUEUED", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID,"ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("PacketID",packetID,"PDCPCount",count,"RLCSDUBytes",numel(encoded)));
        end

        function pdu=prepareSegment(obj,maxRLCBytes,time)
            [pdu,token]=obj.previewSegment(maxRLCBytes,time);
            if ~isempty(fieldnames(pdu)), pdu=obj.commitPreparedSegment(token,time); end
        end

        function [pdu,token]=previewSegment(obj,maxRLCBytes,time)
            arguments
                obj
                maxRLCBytes (1,1) double {mustBePositive}
                time (1,1) double {mustBeFinite,mustBeNonnegative}
            end
            obj.requireEndpointAt('TX',time);
            assert(obj.TransmitMode=="queued_packet", ...
                'sixgr:protocol:MissingQueuedPacket','Enqueue original application bytes before segmentation.');
            pdu=struct();
            token=struct();
            retx=obj.RLCEntity.pendingRetransmissionBytes()>0;
            if retx
                packet=struct();
            elseif isempty(fieldnames(obj.ActiveTransmitPacket))
                if isempty(obj.TransmitPackets), return; end
                packet=obj.TransmitPackets{1};
            else
                packet=obj.ActiveTransmitPacket;
            end
            [parts,segment,token]=obj.RLCEntity.previewPDU(maxRLCBytes);
            if isempty(parts), return; end
            if retx
                assert(isKey(obj.TransmittedPacketsByRLCCount,segment.FullCount), ...
                    'sixgr:protocol:MissingOriginalRLCPacket','RLC retx must retain its original packet/PDCP owner.');
                packet=obj.TransmittedPacketsByRLCCount(segment.FullCount);
            end
            assert(segment.QueueID==packet.RLCQueueID, ...
                'sixgr:protocol:OriginalRLCQueueIdentity','Segmentation must retain its original packet owner across count compaction.');
            assert(time>=packet.EnqueueTime_s,'sixgr:protocol:TransmitBeforeArrival','Grant precedes original SDU arrival.');
            start=segment.Offset; stop=start+segment.PayloadBytes;
            appStart=packet.ApplicationStartByte; appEnd=appStart+packet.PacketBytes;
            appOffset=max(0,min(packet.PacketBytes,start-appStart));
            appBytes=max(0,min(stop,appEnd)-max(start,appStart));
            pdu=packet;
            pdu.Bytes=parts{1}; pdu.EncodedSHA256=sixgr.protocol.ProtocolHash.bytes(parts{1});
            pdu.RLCSN=segment.SN; pdu.RLCHeaderBytes=segment.HeaderBytes;
            pdu.RLCFullCount=segment.FullCount; pdu.IsRLCRetransmission=segment.IsRetransmission;
            pdu.RLCHeader=parts{1}(1:segment.HeaderBytes);
            pdu.SegmentOffset=start; pdu.SegmentPayloadBytes=segment.PayloadBytes;
            pdu.ApplicationOffsetBytes=appOffset; pdu.ApplicationPayloadBytes=appBytes;
            pdu.CompletedTxPacket=segment.Complete;
            pdu.MACBytes=uint8([]); pdu.MACSHA256="";
            obj.PreparedSegments(char(token.ID))=struct('Token',token,'PDU',pdu,'PreparedAt_s',time);
        end

        function pdu=validatePreparedSegment(obj,token,time)
            obj.requireEndpointAt('TX',time);
            assert(isstruct(token) && isfield(token,'ID') && isKey(obj.PreparedSegments,char(token.ID)), ...
                'sixgr:protocol:StaleTransmitPreparation','Unknown, stale, or already committed segment.');
            entry=obj.PreparedSegments(char(token.ID));
            assert(isequaln(token,entry.Token) && isscalar(time) && isfinite(time) && time>=entry.PreparedAt_s, ...
                'sixgr:protocol:StaleTransmitPreparation','Original segment token or transmit time changed.');
            pdu=entry.PDU;
            if pdu.IsRLCRetransmission
                original=obj.TransmittedPacketsByRLCCount(pdu.RLCFullCount);
                assert(original.PacketID==pdu.PacketID,'sixgr:protocol:StaleTransmitPreparation','RLC retx original owner changed.');
            elseif isempty(fieldnames(obj.ActiveTransmitPacket))
                assert(~isempty(obj.TransmitPackets) && obj.TransmitPackets{1}.PacketID==pdu.PacketID, ...
                    'sixgr:protocol:StaleTransmitPreparation','Original application packet head changed.');
            else
                assert(obj.ActiveTransmitPacket.PacketID==pdu.PacketID, ...
                    'sixgr:protocol:StaleTransmitPreparation','Active segmented packet changed.');
            end
            obj.RLCEntity.validatePreparedPDU(token);
        end
        function pdu=commitPreparedSegment(obj,token,time)
            obj.validatePreparedSegment(token,time);
            entry=obj.PreparedSegments(char(token.ID)); pdu=entry.PDU;
            obj.RLCEntity.commitPreparedPDU(token,time);
            obj.collectRLCIndications();
            if ~pdu.IsRLCRetransmission && isempty(fieldnames(obj.ActiveTransmitPacket))
                obj.ActiveTransmitPacket=obj.TransmitPackets{1}; obj.TransmitPackets(1)=[];
                obj.TransmittedPacketsByRLCCount(pdu.RLCFullCount)=obj.ActiveTransmitPacket;
                obj.Lineage.addNode("RLC-"+pdu.PacketID,pdu.PacketID,"RLC",pdu.RLCSDUBytes);
            end
            if ~pdu.IsRLCRetransmission && pdu.CompletedTxPacket, obj.ActiveTransmitPacket=struct(); end
            obj.PreparedSegments=containers.Map('KeyType','char','ValueType','any');
            obj.Events.append(time,"RLC","SEGMENT_TX_COMMITTED","UEID",obj.UEID, ...
                "BearerID",obj.BearerID,"ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("PacketID",pdu.PacketID,"SN",pdu.RLCSN, ...
                "Offset",pdu.SegmentOffset,"Bytes",numel(pdu.Bytes)));
        end

        function volume=pendingTransmitBytes(obj)
            bytes=obj.RLCEntity.pendingPayloadBytes();
            retx=obj.RLCEntity.pendingRetransmissionBytes();
            volume=struct('PDCPPendingBytes',0,'RLCPayloadBytes',bytes, ...
                'AMRetransmissionBytes',retx,'EligibleStatusBytes',0,'TotalBSRBytes',bytes+retx, ...
                'Source',"original_queued_rlc_sdu_bytes_excluding_rlc_and_mac_headers");
        end
        function cancelPreparedSegment(obj,token)
            assert(isfield(token,'ID')&&isKey(obj.PreparedSegments,char(token.ID)), ...
                'sixgr:protocol:StaleTransmitPreparation','Unknown original segment preparation.');
            obj.RLCEntity.cancelPreparedPDU(token);remove(obj.PreparedSegments,char(token.ID));
        end
        function bytes=pendingReverseStatusBytes(obj)
            bytes=obj.RLCEntity.pendingStatusBytes();
        end
        function p=prepareReverseStatus(obj,budget,time)
            obj.requireEndpointAt('RX',time);
            p=obj.RLCEntity.prepareStatus(budget,time);
            obj.collectRLCIndications();
        end
        function commitReverseStatus(obj,p,id,time)
            obj.requireEndpointAt('RX',time);
            obj.RLCEntity.commitStatus(p,id,time);
            obj.collectRLCIndications();
        end
        function validateReverseStatus(obj,p,id,time)
            obj.requireEndpointAt('RX',time);
            obj.RLCEntity.validateStatus(p,id,time);
        end
        function cancelReverseStatus(obj,p)
            obj.RLCEntity.cancelStatus(p);
        end
        function disposition=receiveReverseStatus(obj,bytes,id,time)
            obj.requireEndpointAt('TX',time);
            disposition=obj.RLCEntity.receiveStatus(bytes,id,time);
            obj.collectRLCIndications();
        end
        function token=previewReceivedStatus(obj,bytes,id,time)
            obj.requireEndpointAt('TX',time);
            token=obj.RLCEntity.previewReceivedStatus(bytes,id,time);
        end
        function validateReceivedStatus(obj,token)
            obj.EndpointAdmission.require('TX');
            obj.RLCEntity.validateReceivedStatus(token);
        end
        function disposition=commitReceivedStatus(obj,token)
            obj.EndpointAdmission.require('TX');
            disposition=obj.RLCEntity.commitReceivedStatus(token);
            obj.collectRLCIndications();
        end
        function cancelReceivedStatus(obj,token)
            obj.RLCEntity.cancelReceivedStatus(token);
        end

        function pdu = transmit(obj, packetID, payload, time)
            arguments
                obj
                packetID (1,1) string
                payload (1,:) uint8
                time (1,1) double {mustBeNonnegative}
            end
            obj.requireEndpointAt('TX',time);
            assert(obj.TransmitMode~="queued_packet", ...
                'sixgr:protocol:MixedTransmitOwnership','Queued packets cannot be bypassed by fragment transmission.');
            obj.TransmitMode="legacy_fragment";
            assert(~obj.RLCEntity.ARQEnabled,'sixgr:protocol:UnsupportedCapability', ...
                'ARQ-enabled bearers must enqueue whole original SDUs and use actual segment commits.');
            packetHash = sixgr.protocol.ProtocolHash.bytes(payload);
            packet = struct("PacketID",packetID, ...
                "PacketBytes",numel(payload),"PayloadSHA256",packetHash);
            obj.Lineage.addPacket(packet);

            [sdapPDU,sdapHeader] = obj.encodeUpperPayload(payload);
            count = double(obj.PDCPEntity.TX.current());
            pdcpSN = double(obj.PDCPEntity.TX.SN);
            pdcpPDU = obj.PDCPEntity.transmit(sdapPDU,time);
            obj.processPDCPDiscards();
            pdcpHeaderBytes = 2+double(obj.PDCPSNBits==18);
            pdcpHeader = pdcpPDU(1:pdcpHeaderBytes);
            rlcSN = obj.RLCEntity.State.TX_NEXT;
            queueID=obj.RLCEntity.addSDU(pdcpPDU);
            encoded = obj.RLCEntity.buildPDUs(inf,time);
            if numel(encoded)~=1
                error("sixgr:rlc:MalformedPDU", ...
                    "Connected-mode packet did not produce one RLC PDU.");
            end
            rlcPDU = encoded{1};
            rlcHeaderBytes = 2+double(obj.RLCSNBits==18);
            rlcHeader = rlcPDU(1:rlcHeaderBytes);

            sdapID = "SDAP-" + packetID;
            pdcpID = "PDCP-" + string(count);
            rlcID = "RLC-" + string(rlcSN);
            macID = "MAC-" + packetID;
            tbID = "TB-" + packetID;
            if obj.BearerType=="DRB", obj.Lineage.addNode(sdapID,packetID,"SDAP",numel(sdapPDU)); end
            obj.Lineage.addNode(pdcpID,packetID,"PDCP",numel(pdcpPDU));
            obj.Lineage.addNode(rlcID,packetID,"RLC",numel(rlcPDU));
            macHeaderBytes=2+double(numel(rlcPDU)>255);
            mac=sixgr.l2.mac.MACPDUAssembler.assemble(obj.Direction, ...
                struct("LCID",obj.LCID,"Payload",rlcPDU,"OwnerID",rlcID), ...
                numel(rlcPDU)+macHeaderBytes);
            obj.Lineage.addNode(macID,packetID,"MAC",numel(mac.Bytes));
            obj.Lineage.addNode(tbID,packetID,"HARQ_TB",numel(mac.Bytes));
            upperLayer="SDAP"; if obj.BearerType=="SRB", upperLayer="RRC"; end
            event = obj.Events.append(time,upperLayer,"SDU_ACCEPTED", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("PacketID",packetID,"QFI",obj.QFI));
            event = obj.Events.append(time,"PDCP","PDU_ENCODED", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "SourceEventID",event.EventID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("COUNT",count,"SN",pdcpSN));
            obj.Events.append(time,"RLC","PDU_ENCODED", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "SourceEventID",event.EventID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("SN",rlcSN,"Bytes",numel(rlcPDU)));
            obj.Events.append(time,"MAC","TB_ASSEMBLED", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("TBID",tbID,"HARQAttempt",1, ...
                "Bytes",numel(mac.Bytes)));

            pdu = struct("PacketID",packetID,"PacketSHA256",packetHash, ...
                "SDAPHeader",sdapHeader,"PDCPHeader",pdcpHeader, ...
                "RLCHeader",rlcHeader,"PDCPCount",count,"RLCSN",rlcSN, ...
                "Bytes",rlcPDU,"PayloadBytes",numel(payload), ...
                "EncodedSHA256",sixgr.protocol.ProtocolHash.bytes(rlcPDU), ...
                "MACBytes",mac.Bytes,"MACSHA256",mac.SHA256, ...
                "TBID",tbID,"HARQAttempt",1,"Direction",obj.Direction, ...
                "LCID",obj.LCID,"DRBID",obj.DRBID, ...
                "PduSessionID",obj.PduSessionID,"UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch);
            pdu.RLCQueueID=queueID;pdu.PacketBytes=numel(payload);
            pdu.PDCPPDUSHA256=sixgr.protocol.ProtocolHash.bytes(pdcpPDU);
            obj.EnqueuedPackets(char(packetID))=pdu;
            obj.PacketsTransmitted = obj.PacketsTransmitted + 1;
            if ~isempty(obj.MACSubmit)
                obj.MACSubmit(pdu);
            end
        end

        function [delivered,completions,rlcDisposition,pdcpDisposition,securityObservation] = receive(obj, pdu, time)
            arguments
                obj
                pdu (1,1) struct
                time (1,1) double {mustBeNonnegative}
            end
            obj.requireEndpointAt('RX',time);
            if sixgr.protocol.ProtocolHash.bytes(pdu.Bytes) ~= ...
                    string(pdu.EncodedSHA256)
                error("sixgr:protocol:LineageViolation", ...
                    "Received RLC PDU digest does not match its identity.");
            end
            if sixgr.l2.mac.MACHash.of(pdu.MACBytes) ~= ...
                    string(pdu.MACSHA256)
                error("sixgr:protocol:LineageViolation", ...
                    "Received MAC PDU digest does not match its TB identity.");
            end
            demux=sixgr.l2.mac.MACPDUDemultiplexer.decode(obj.Direction,pdu.MACBytes);
            matches=arrayfun(@(row) string(row.Kind)=="SDU" && row.LCID==obj.LCID,demux.SubPDUs);
            if sum(matches)~=1 || ~isequal(demux.SubPDUs(matches).Payload,pdu.Bytes)
                error("sixgr:protocol:LineageViolation", ...
                    "MAC demultiplexing changed RLC PDU ownership.");
            end
            completions=obj.advance(time);
            rlcDisposition=obj.RLCEntity.receivePDU(demux.SubPDUs(matches).Payload,time);
            pdcpDisposition="not_reassembled";securityObservation=struct();
            pdcpPDUs = obj.RLCEntity.pullSDUs();
            if numel(pdcpPDUs)>1
                error("sixgr:rlc:MalformedPDU", ...
                    "One transport binding cannot claim multiple reassembled packet identities.");
            end
            if ~isempty(pdcpPDUs)
                header=sixgr.l2.pdcp18.PDCPHeaderCodec.decode(obj.BearerType,obj.PDCPSNBits,pdcpPDUs{1});
                count=obj.PDCPEntity.RX.inferCount(header.SN);
                newCount=~obj.PDCPEntity.RX.alreadyReceived(count);
                if obj.InitialSecurityReceivePending
                    try
                        [payload,token]=obj.PDCPEntity.previewInitialIntegrityReceive(pdcpPDUs{1},time);
                    catch ex
                        if string(ex.identifier)~="sixgr:pdcp:IntegrityFailure",rethrow(ex);end
                        pdcpDisposition="initial_security_integrity_failed_discarded";
                        securityObservation=struct('Status',pdcpDisposition,'Token',"", ...
                            'PDCPPDUSHA256',sixgr.protocol.ProtocolHash.bytes(pdcpPDUs{1}), ...
                            'PDCPCount',count,'AvailableTime_s',time,'ErrorIdentifier',string(ex.identifier));
                        delivered=any(string({completions.PacketID})==string(pdu.PacketID));
                        return;
                    end
                    securityObservation=struct('Status',"authenticated_RRC_validation_pending",'Token',token, ...
                        'Payload',payload,'PDCPPDUSHA256',sixgr.protocol.ProtocolHash.bytes(pdcpPDUs{1}), ...
                        'RRCPayloadSHA256',sixgr.protocol.ProtocolHash.bytes(payload),'PDCPCount',count, ...
                        'AvailableTime_s',time,'UEID',obj.UEID,'BearerID',obj.BearerID, ...
                        'Direction',obj.Direction,'ConfigurationEpoch',obj.ConfigurationEpoch);
                    original=securityObservation;original.OriginalPDU=pdu;
                    obj.InitialSecurityObservations(char(token))=original;
                    pdcpDisposition="authenticated_RRC_validation_pending";
                    delivered=any(string({completions.PacketID})==string(pdu.PacketID));
                    return;
                end
                try
                    [sdapPDUs,counts]=obj.PDCPEntity.receive(pdcpPDUs{1},time);
                catch ex
                    if string(ex.identifier)~="sixgr:pdcp:IntegrityFailure",rethrow(ex);end
                    % Earlier explicit clock-event releases remain returned;
                    % this current PDU never enters the received COUNT map.
                    pdcpDisposition="integrity_failed_discarded";
                    obj.retainIntegrityFailure(pdu,pdcpPDUs{1},count,time,ex.identifier);
                    delivered=any(string({completions.PacketID})==string(pdu.PacketID));
                    return;
                end
                if ~newCount,pdcpDisposition="duplicate_or_below_RX_DELIV_discarded";
                elseif any(counts==count),pdcpDisposition="released";
                else,pdcpDisposition="accepted_reordering_pending";end
                if newCount && ~isKey(obj.Delivered,char(string(pdu.PacketID)))
                    obj.retainReceivedWireEvidence(count,sixgr.protocol.ProtocolHash.bytes(pdcpPDUs{1}),time);
                    if isKey(obj.ReceivedPacketByCount,count)
                        prior=obj.ReceivedPacketByCount(count);
                        assert(string(prior.PacketID)==string(pdu.PacketID), ...
                            'sixgr:protocol:LineageViolation','One received COUNT cannot own different packets.');
                    else
                        obj.ReceivedPacketByCount(count)=pdu;
                    end
                end
                completions=[completions obj.completeReceived(sdapPDUs,counts,time)];
            end
            obj.DuplicateDiscards=obj.PDCPEntity.DuplicateCount;
            delivered=any(string({completions.PacketID})==string(pdu.PacketID));
        end

        function completions=advance(obj,time)
            obj.observeEndpointClock(time);
            obj.RLCEntity.advance(time);
            obj.collectRLCIndications();
            [sdapPDUs,counts]=obj.PDCPEntity.advance(time);
            obj.processPDCPDiscards();
            completions=obj.completeReceived(sdapPDUs,counts,time);
        end

        function time=nextTimerExpiry(obj)
            if ~obj.Active,time=inf;return;end
            time=min([obj.PDCPEntity.RX.TimerExpiry_s,obj.RLCEntity.nextTimerExpiry(),obj.PDCPEntity.nextDiscardExpiry()]);
        end
        function completions=release(obj,time)
            completions=obj.advance(time);
            [payloads,counts]=obj.PDCPEntity.release();
            completions=[completions obj.completeReceived(payloads,counts,time)];
            obj.RLCEntity.release();obj.Active=false;
            obj.InitialSecurityReceivePending=false;
            obj.InitialSecurityObservations=containers.Map('KeyType','char','ValueType','any');
            obj.TransmitPackets={};obj.ActiveTransmitPacket=struct();
            obj.PreparedSegments=containers.Map('KeyType','char','ValueType','any');
        end

        function value = conservation(obj)
            value = obj.Lineage.conservation();
        end
        function rows=takeSecurityIndications(obj)
            rows=obj.PendingSecurityIndications;obj.PendingSecurityIndications=struct([]);
        end
        function row=originalSecurityIndication(obj,id)
            key=char(string(id));
            assert(isKey(obj.SecurityFailureReceipts,key),'sixgr:pdcp:SecurityObservationMissing','Original private indication required.');
            row=obj.SecurityFailureReceipts(key);
        end
        function rows=takeUpperLayerIndications(obj)
            rows=obj.UpperLayerIndications;obj.UpperLayerIndications=struct([]);
        end
        function rows=takeDiscardEvents(obj)
            rows=obj.DiscardEvents;obj.DiscardEvents=struct([]);
        end
    end
    methods (Access=private)
        function retainReceivedWireEvidence(obj,count,pduHash,time)
            if obj.BearerType~="SRB"||isempty(fieldnames(obj.OriginalConnectionScope)),return;end
            c=obj.OriginalConnectionScope;sample=round(time*c.SampleRateHz);
            assert(abs(time*c.SampleRateHz-sample)<=max(1e-7,8*eps(time*c.SampleRateHz)), ...
                'sixgr:protocol:OriginalDeliveryClock','Original received SRB requires its native sample clock.');
            security=obj.PDCPEntity.endpointSecurityIdentity("RX");
            row=struct('PDCPPDUSHA256',string(pduHash),'ReceivedAtSample',sample, ...
                'RXIntegrityActive',obj.PDCPEntity.RXIntegrityActive, ...
                'RXCipheringActive',obj.PDCPEntity.RXCipheringActive, ...
                'IntegrityAlgorithm',security.IntegrityAlgorithm,'SecurityContextID',security.ContextID);
            row.IntegrityVerified=row.RXIntegrityActive&&row.IntegrityAlgorithm=="128-NIA2";
            assert(~isKey(obj.ReceivedWireEvidenceByCount,count), ...
                'sixgr:protocol:OriginalDeliveryMismatch','One accepted SRB COUNT must retain one original wire receipt.');
            obj.ReceivedWireEvidenceByCount(count)=row;
        end

        function retainOriginalSRBDelivery(obj,pdu,payload,count,time)
            if obj.BearerType~="SRB"||isempty(fieldnames(obj.OriginalConnectionScope)),return;end
            assert(isKey(obj.ReceivedWireEvidenceByCount,count), ...
                'sixgr:protocol:OriginalDeliveryMissing','Original decoded SRB wire evidence required.');
            wire=obj.ReceivedWireEvidenceByCount(count);row=obj.OriginalConnectionScope;
            row.ContractVersion="original_PDCP_to_RRC_delivery/v1";
            row.PacketID=string(pdu.PacketID);row.Direction=obj.Direction;row.LCID=obj.LCID;
            row.Payload=payload;row.PDCPCount=count;row.PDCPPDUSHA256=wire.PDCPPDUSHA256;
            row.RRCPayloadSHA256=sixgr.protocol.ProtocolHash.bytes(payload);
            value=time*row.SampleRateHz;row.AvailableAtSample=round(value);
            assert(abs(value-row.AvailableAtSample)<=max(1e-7,8*eps(value))&& ...
                row.AvailableAtSample>=wire.ReceivedAtSample, ...
                'sixgr:protocol:OriginalDeliveryClock','PDCP delivery cannot predate original reception.');
            row.ReceivedAtSample=wire.ReceivedAtSample;
            row.TransportBlockID=string(localField(pdu,'TBID',""));
            row.OriginalMACSHA256=string(pdu.MACSHA256);row.OriginalRLCEncodedSHA256=string(pdu.EncodedSHA256);
            row.RXIntegrityActive=wire.RXIntegrityActive;row.RXCipheringActive=wire.RXCipheringActive;
            row.IntegrityAlgorithm=wire.IntegrityAlgorithm;row.IntegrityVerified=wire.IntegrityVerified;
            row.SecurityContextID=wire.SecurityContextID;
            row.Source="original_RLC_PDCP_receiver_completion";
            row.OriginalDeliverySHA256=sixgr.l2.mac.MACHash.of(orderfields(row));key=char(row.PacketID);
            assert(~isKey(obj.OriginalSRBDeliveryReceipts,key), ...
                'sixgr:protocol:OriginalDeliveryMismatch','One original SRB packet delivers once.');
            obj.OriginalSRBDeliveryReceipts(key)=row;remove(obj.ReceivedWireEvidenceByCount,count);
        end
        function validateSecurityEventClock(obj,r)
            assert(isstruct(r)&&isscalar(r)&&all(isfield(r,{'AtSample','SampleRateHz'}))&& ...
                isnumeric(r.AtSample)&&isscalar(r.AtSample)&&isfinite(r.AtSample)&&r.AtSample>=0&& ...
                r.AtSample==fix(r.AtSample)&&isnumeric(r.SampleRateHz)&&isscalar(r.SampleRateHz)&& ...
                isfinite(r.SampleRateHz)&&r.SampleRateHz>0&& ...
                r.AtSample>=round(obj.EndpointLastTime_s*r.SampleRateHz), ...
                'sixgr:protocol:SecurityActivationClock','Security cannot activate before an already executed runtime event.');
        end
        function retainLowerLayerSubmission(obj,packet,encoded,time)
            if isempty(fieldnames(obj.OriginalConnectionScope)),return;end
            c=obj.OriginalConnectionScope;sample=time*c.SampleRateHz;
            assert(isfinite(sample)&&sample>=0&&abs(sample-round(sample))<=max(1e-7,8*eps(sample)), ...
                'sixgr:protocol:OriginalSubmissionScope','Original lower-layer handoff needs its native sample clock.');
            row=c;row.ContractVersion="original_PDCP_to_RLC_submission/v1";
            row.PacketID=packet.PacketID;row.Direction=obj.Direction;row.LCID=obj.LCID;
            row.RLCQueueID=packet.RLCQueueID;row.PDCPCount=packet.PDCPCount;
            row.PDCPPDU=encoded;row.PDCPPDUSHA256=packet.PDCPPDUSHA256;
            row.SubmittedAtSample=round(sample);
            row.TXIntegrityActive=obj.PDCPEntity.TXIntegrityActive;
            row.TXCipheringActive=obj.PDCPEntity.TXCipheringActive;
            security=obj.PDCPEntity.endpointSecurityIdentity("TX");
            row.SecurityContextID=security.ContextID;row.IntegrityAlgorithm=security.IntegrityAlgorithm;
            row.CipherAlgorithm=security.CipherAlgorithm;
            row.Source="original_RLCEntity_addSDU_handoff";
            row.SubmissionID=sixgr.l2.mac.MACHash.of(orderfields(row));
            row.OriginalSubmissionSHA256=sixgr.l2.mac.MACHash.of(orderfields(row));
            key=char(packet.PacketID);
            assert(~isKey(obj.LowerLayerSubmissionReceipts,key), ...
                'sixgr:protocol:DuplicateOriginalSubmission','One packet has one original PDCP-to-RLC handoff.');
            obj.LowerLayerSubmissionReceipts(key)=row;
        end
        function validateSecurityPair(obj,peer,direction,peerDirection,a,b,purpose)
            assert(isa(peer,'sixgr.protocol.ProtocolRuntime')&&obj.Active&&peer.Active&& ...
                obj.BearerType=="SRB"&&peer.BearerType=="SRB"&&obj.LCID==1&&peer.LCID==1&& ...
                obj.UEID==peer.UEID&&obj.BearerID==peer.BearerID&& ...
                obj.ConfigurationEpoch==peer.ConfigurationEpoch&& ...
                obj.Direction==direction&&peer.Direction==peerDirection, ...
                'sixgr:protocol:SecurityPairScope','Original SRB1 directional owners disagree.');
            fields={'RRCTransactionID','RRCPayloadSHA256','PDCPPDUSHA256', ...
                'OriginalObservationSHA256','AtSample','SampleRateHz','ClockEpoch','EvidenceBoundary'};
            assert(isstruct(a)&&isscalar(a)&&isstruct(b)&&isscalar(b)&& ...
                all(isfield(a,[fields,{'Purpose'}]))&&all(isfield(b,[fields,{'Purpose'}]))&& ...
                string(a.Purpose)==purpose&&string(b.Purpose)==purpose, ...
                'sixgr:protocol:SecurityPairScope','Original matching RRC procedure receipts are required.');
            for k=1:numel(fields)
                assert(isequaln(a.(fields{k}),b.(fields{k})), ...
                    'sixgr:protocol:SecurityPairScope','Directional receipts describe different original procedures.');
            end
        end
        function validateAdmissionClock(obj,sample,mode)
            if nargin<3,mode="original_setup_required";end
            assert(obj.Active,'sixgr:protocol:ReleasedBearer','Released runtime cannot be admitted again.');
            a=obj.EndpointAdmission;
            id='sixgr:protocol:SRB1AdmissionClock';
            if mode=="original_reconfiguration_required",id='sixgr:protocol:DRBAdmissionClock';end
            assert(a.Mode==mode&&isnumeric(sample)&&isscalar(sample)&& ...
                isfinite(sample)&&sample>=0&&sample==fix(sample)&& ...
                sample>=round(obj.EndpointLastTime_s*a.Scope.SampleRateHz), ...
                id,'Admission cannot predate the original runtime event clock.');
        end

        function requireEndpointAt(obj,endpoint,time)
            assert(obj.Active,'sixgr:protocol:ReleasedBearer','Released runtime cannot execute an endpoint.');
            obj.EndpointAdmission.require(endpoint);
            obj.observeEndpointClock(time);
        end

        function observeEndpointClock(obj,time)
            a=obj.EndpointAdmission;
            if any(a.Mode==["original_setup_required","original_reconfiguration_required"])
                fs=a.Scope.SampleRateHz;minimum=a.LastSample;id='sixgr:protocol:SRB1AdmissionClock';
                if a.Mode=="original_reconfiguration_required",id='sixgr:protocol:DRBAdmissionClock';end
            elseif ~isempty(fieldnames(obj.OriginalConnectionScope))
                fs=obj.OriginalConnectionScope.SampleRateHz;minimum=0;id='sixgr:protocol:OriginalSubmissionScope';
            else,return;end
            value=time*fs;sample=round(value);
            assert(isnumeric(time)&&isscalar(time)&&isfinite(time)&&time>=0&& ...
                abs(value-sample)<=max(1e-7,8*eps(value))&&sample>=minimum&& ...
                sample>=round(obj.EndpointLastTime_s*fs), ...
                id,'Endpoint execution needs its original monotonic sample clock.');
            obj.EndpointLastTime_s=sample/fs;
        end


        function retainIntegrityFailure(obj,pdu,bytes,count,time,errorID)
            fs=obj.SecurityObservationClock.SampleRateHz;epoch=obj.SecurityObservationClock.ClockEpoch;
            sample=NaN;qualified=isfinite(fs)&&fs>0&&isfinite(epoch)&&epoch>=0&&epoch==fix(epoch);
            if qualified
                sample=round(time*fs);
                assert(abs(time*fs-sample)<=max(1e-7,8*eps(time*fs)), ...
                    'sixgr:pdcp:SecurityClock','Original receive time must preserve its configured sample clock.');
            end
            row=struct('Kind',"PDCP_INTEGRITY_FAILURE",'UEID',obj.UEID,'BearerID',obj.BearerID, ...
                'Direction',obj.Direction,'ConfigurationEpoch',obj.ConfigurationEpoch, ...
                'PacketID',string(pdu.PacketID),'TransportBlockID',string(localField(pdu,'TBID',"")), ...
                'MACSHA256',string(pdu.MACSHA256),'RLCEncodedSHA256',string(pdu.EncodedSHA256), ...
                'PDCPPDUSHA256',sixgr.protocol.ProtocolHash.bytes(bytes),'InferredPDCPCount',count, ...
                'PDCPCountAccepted',false,'AvailableTime_s',time,'Sample',sample,'SampleRateHz',fs, ...
                'ClockEpoch',epoch,'SampleClockQualified',qualified,'ErrorIdentifier',string(errorID), ...
                'IntegrityAlgorithm',obj.SecurityObservationContext.IntegrityAlgorithm, ...
                'SecurityContextID',obj.SecurityObservationContext.ContextID, ...
                'SecurityContextSource',obj.SecurityObservationContext.Source, ...
                'Disposition',"integrity_failed_discarded",'ApplicationBytesDelivered',0, ...
                'TerminalApplicationDrop',false,'Source',"original_reassembled_PDCP_integrity_verification");
            row.IndicationID=sixgr.l2.mac.MACHash.of(orderfields(row));key=char(row.IndicationID);
            if isKey(obj.SecurityFailureReceipts,key)
                assert(isequaln(obj.SecurityFailureReceipts(key),row));return;
            end
            obj.SecurityFailureReceipts(key)=row;
            if isempty(obj.PendingSecurityIndications),obj.PendingSecurityIndications=row;
            else,obj.PendingSecurityIndications(end+1)=row;end
            obj.Events.append(time,"PDCP","INTEGRITY_FAILURE_INDICATION", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID,"ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "SourceEventID",row.IndicationID,"Payload",row);
        end
        function collectRLCIndications(obj)
            obj.collectRLCAcknowledgements();
            rows=obj.RLCEntity.takeUpperLayerIndications();
            for row=reshape(rows,1,[])
                obj.Events.append(row.Sample/row.SampleRateHz,"RLC","MAX_RETRANSMISSION_INDICATION", ...
                    "UEID",obj.UEID,"BearerID",obj.BearerID,"ConfigurationEpoch",obj.ConfigurationEpoch, ...
                    "SourceEventID",row.SourceEventID,"Payload",row);
                if isempty(obj.UpperLayerIndications),obj.UpperLayerIndications=row;
                else,obj.UpperLayerIndications(end+1)=row;end
            end
        end
        function collectRLCAcknowledgements(obj)
            rows=obj.RLCEntity.takeSDUAcknowledgements();
            for r=reshape(rows,1,[])
                packets=values(obj.EnqueuedPackets);
                hit=find(cellfun(@(p)isfield(p,'RLCQueueID')&&p.RLCQueueID==r.QueueID,packets));
                assert(isscalar(hit),'sixgr:protocol:SDUAcknowledgement','Original acknowledged SDU must join one queued PDCP packet.');
                p=packets{hit};
                assert(p.PDCPPDUSHA256==r.PayloadSHA256&&p.ConfigurationEpoch==r.ConfigurationEpoch, ...
                    'sixgr:protocol:SDUAcknowledgement','Original lower-layer COUNT/bytes/configuration changed.');
                time=r.AcknowledgedAtSample/r.SampleRateHz;
                obj.PDCPEntity.confirmLowerLayerDelivery(p.PDCPCount,r.PayloadSHA256,time);
                obj.processPDCPDiscards();
                obj.Events.append(time,"RLC","ORIGINAL_SDU_ACKNOWLEDGED", ...
                    "UEID",obj.UEID,"BearerID",obj.BearerID,"ConfigurationEpoch",obj.ConfigurationEpoch, ...
                    "SourceEventID",r.STATUSReceiptID,"Payload",r);
            end
        end
        function processPDCPDiscards(obj)
            rows=obj.PDCPEntity.takeTransmitDiscards();
            for r=reshape(rows,1,[])
                packets=values(obj.EnqueuedPackets);
                hit=find(cellfun(@(p)p.PDCPCount==r.PDCPCount,packets));
                assert(isscalar(hit),'sixgr:protocol:DiscardIdentity','Original expired COUNT must own one queued packet.');
                p=packets{hit};
                assert(p.PDCPPDUSHA256==r.PDUSHA256, ...
                    'sixgr:protocol:DiscardIdentity','Discard request changed original PDCP bytes.');
                lower=obj.RLCEntity.discardUnsubmittedSDU(p.RLCQueueID);
                assert(lower.PayloadSHA256==p.PDCPPDUSHA256, ...
                    'sixgr:protocol:DiscardIdentity','Lower-layer discard changed original SDU bytes.');
                dropped=0;
                if lower.Discarded
                    queued=find(cellfun(@(q)q.RLCQueueID==p.RLCQueueID,obj.TransmitPackets));
                    assert(isscalar(queued)&& ...
                        (isempty(fieldnames(obj.ActiveTransmitPacket))||obj.ActiveTransmitPacket.RLCQueueID~=p.RLCQueueID), ...
                        'sixgr:protocol:DiscardIdentity','Only a wholly unsubmitted original queued packet may be removed.');
                    obj.TransmitPackets(queued)=[];obj.Lineage.drop(p.PacketID);dropped=p.PacketBytes;
                    p.DiscardedBeforeMACSubmission=true;obj.EnqueuedPackets(char(p.PacketID))=p;
                end
                e=struct('UEID',obj.UEID,'BearerID',obj.BearerID,'Direction',obj.Direction, ...
                    'ConfigurationEpoch',obj.ConfigurationEpoch,'PacketID',p.PacketID, ...
                    'PacketizationMode',obj.TransmitMode, ...
                    'PayloadSHA256',p.PacketSHA256,'PacketBytes',p.PacketBytes,'PDCPCount',p.PDCPCount, ...
                    'RLCQueueID',p.RLCQueueID,'PDCPPDUSHA256',p.PDCPPDUSHA256, ...
                    'DeadlineSample',r.DeadlineSample,'ObservedAtSample',r.ObservedAtSample, ...
                    'SampleRateHz',r.SampleRateHz,'ClockEpoch',r.ClockEpoch,'Source',r.Source, ...
                    'LowerLayerDisposition',lower.Disposition,'ApplicationBytesDropped',dropped);
                e.ReceiptID=sixgr.l2.mac.MACHash.of(orderfields(e));
                if isempty(obj.DiscardEvents),obj.DiscardEvents=e;else,obj.DiscardEvents(end+1)=e;end
                obj.Events.append(r.ObservedAtSample/r.SampleRateHz,"PDCP","TX_DISCARD_TIMER_EXPIRED", ...
                    "UEID",obj.UEID,"BearerID",obj.BearerID,"ConfigurationEpoch",obj.ConfigurationEpoch, ...
                    "SourceEventID",e.ReceiptID,"Payload",e);
            end
        end
        function [encoded,header]=encodeUpperPayload(obj,payload)
            if obj.BearerType=="SRB"
                encoded=payload; header=uint8([]);
            else
                [encoded,~]=obj.SDAPEntity.transmit(obj.QFI,payload); header=encoded(1);
            end
        end
        function records=completeReceived(obj,sdapPDUs,counts,time)
            records=repmat(struct('PacketID',"",'Payload',uint8([]), ...
                'PayloadSHA256',"",'PDCPCount',NaN,'DeliveryTime_s',NaN, ...
                'UEID',obj.UEID,'BearerID',obj.BearerID,'Direction',obj.Direction, ...
                'ConfigurationEpoch',obj.ConfigurationEpoch),1,0);
            for k=1:numel(counts)
                assert(isKey(obj.ReceivedPacketByCount,counts(k)), ...
                    'sixgr:protocol:LineageViolation','Delivered COUNT has no received packet owner.');
                pdu=obj.ReceivedPacketByCount(counts(k));
                if obj.BearerType=="SRB", payload=sdapPDUs{k};
                else, payload=obj.SDAPEntity.receive(sdapPDUs{k}); end
                hash=sixgr.protocol.ProtocolHash.bytes(payload);
                assert(hash==string(pdu.PacketSHA256), ...
                    'sixgr:protocol:LineageViolation','Decoded payload differs from original application bytes.');
                key=char(string(pdu.PacketID));
                assert(~isKey(obj.Delivered,key),'sixgr:protocol:LineageViolation','Packet delivered twice.');
                obj.retainOriginalSRBDelivery(pdu,payload,counts(k),time);
                obj.Delivered(key)=true; obj.Lineage.deliver(string(pdu.PacketID));
                obj.PacketsDelivered=obj.PacketsDelivered+1;
                remove(obj.ReceivedPacketByCount,counts(k));
                records(end+1)=struct('PacketID',string(pdu.PacketID),'Payload',payload, ...
                    'PayloadSHA256',hash,'PDCPCount',counts(k),'DeliveryTime_s',time, ...
                    'UEID',obj.UEID,'BearerID',obj.BearerID,'Direction',obj.Direction, ...
                    'ConfigurationEpoch',obj.ConfigurationEpoch); %#ok<AGROW>
                obj.Events.append(time,"PDCP","SDU_DELIVERED","UEID",obj.UEID, ...
                    "BearerID",obj.BearerID,"ConfigurationEpoch",obj.ConfigurationEpoch, ...
                    "Payload",struct("PacketID",pdu.PacketID,"PayloadBytes",numel(payload),"COUNT",counts(k)));
            end
        end
    end
end

function value=localField(config,name,defaultValue)
if isfield(config,name)
    value=config.(name);
else
    value=defaultValue;
end
end
