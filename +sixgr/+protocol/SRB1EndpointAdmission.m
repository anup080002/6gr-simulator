classdef SRB1EndpointAdmission
    % Endpoint gate only. Physical adapters must validate original captures.
    % Receipt hashes bind lineage; they are not physical execution proof.
    properties (SetAccess=private)
        Scope struct
        Mode string
        RXEnabled logical=false
        TXEnabled logical=false
        IssuedReceipt struct=struct()
        ReceivedReceipt struct=struct()
        LastSample double=0
    end
    methods
        function obj=SRB1EndpointAdmission(scope,mode)
            obj.Scope=scope;obj.Mode=string(mode);
            assert(isscalar(obj.Mode)&&any(obj.Mode==["component_preconfigured_both","original_setup_required"]), ...
                'sixgr:protocol:SRB1AdmissionPolicy','Declare the endpoint admission policy.');
            if obj.Mode=="component_preconfigured_both"
                obj.RXEnabled=true;obj.TXEnabled=true;return;
            end
            names=localScopeFields();
            assert(isstruct(scope)&&isscalar(scope)&&all(isfield(scope,names)), ...
                'sixgr:protocol:SRB1AdmissionScope','Retain original execution, connection and clock scope.');
            localText(scope.ExecutionRunID);localText(scope.UEID);
            for name=["ConfigurationEpoch","ClockEpoch"]
                localSampleFields(scope,name);
            end
            assert(isnumeric(scope.SampleRateHz)&&isscalar(scope.SampleRateHz)&& ...
                isfinite(scope.SampleRateHz)&&scope.SampleRateHz>0,'sixgr:protocol:SRB1AdmissionScope','Require the original positive sample rate.');
            localSampleFields(scope,["ServingCell","RNTI"]);
            assert(scope.ServingCell>=1&&scope.RNTI>=1&&scope.RNTI<=65522, ...
                'sixgr:protocol:SRB1AdmissionScope','Require a serving cell and a valid C-RNTI.');
            localHashes(scope,"ProtocolConfigurationSHA256");
            assert(isequal(scope.SRBID,1)&&isequal(scope.LCID,1)&&any(string(scope.Direction)==["UL","DL"]), ...
                'sixgr:protocol:SRB1AdmissionScope','This owner supports one original UL or DL SRB1 direction.');
        end
        function obj=admitIssued(obj,r,sample)
            localClock(obj,sample);obj.LastSample=sample;localReceipt(obj,r,"issued_NR_SRB1_setup/v1");
            fields=["TransmitComponentID","TransmitEnqueueReceiptSHA256", ...
                "OriginalComponentSampleSHA256","TransmitObservationSHA256", ...
                "PhysicalTransmissionReceiptSHA256","TransmitStartSample", ...
                "TransmitEndSampleExclusive","IssuedAtSample"];
            localFields(r,fields);localText(r.TransmitComponentID);
            localSampleFields(r,["TransmitStartSample","TransmitEndSampleExclusive","IssuedAtSample"]);
            assert(r.TransmitStartSample<r.TransmitEndSampleExclusive && ...
                r.TransmitEndSampleExclusive<=r.IssuedAtSample && r.IssuedAtSample<=sample, ...
                'sixgr:protocol:SRB1AdmissionClock','Admission requires completed original TX, never enqueue-only authority.');
            localHashes(r,fields(2:5));
            if ~isempty(fieldnames(obj.IssuedReceipt))
                assert(isequaln(r,obj.IssuedReceipt),'sixgr:protocol:SRB1AdmissionConflict', ...
                    'An existing issued Setup cannot be replaced.');return;
            end
            assert(~obj.RXEnabled && ~obj.TXEnabled,'sixgr:protocol:SRB1AdmissionConflict','Initial issued Setup requires unadmitted endpoints.');
            obj.IssuedReceipt=r;
            if string(obj.Scope.Direction)=="UL",obj.RXEnabled=true;else,obj.TXEnabled=true;end
        end
        function obj=admitReceived(obj,r,sample)
            localClock(obj,sample);obj.LastSample=sample;localReceipt(obj,r,"received_NR_SRB1_setup/v1");
            issuedEnabled=(string(obj.Scope.Direction)=="UL"&&obj.RXEnabled)|| ...
                (string(obj.Scope.Direction)=="DL"&&obj.TXEnabled);
            assert(issuedEnabled && ~isempty(fieldnames(obj.IssuedReceipt)), ...
                'sixgr:protocol:SRB1IssuedSetupRequired','Join the original issued Setup before UE activation.');
            fields=["IssuedSetupReceiptSHA256","ReceiverObservationID","ReceiverObservationSHA256", ...
                "ReceivedMACPayloadSHA256","ObservationStartSample","ObservationEndSampleExclusive", ...
                "AvailableAtSample","OriginalRARObservationSHA256","OriginalContentionObservationSHA256"];
            localFields(r,fields);localText(r.ReceiverObservationID);localHashes(r,fields([1 3 4 8 9]));
            localSampleFields(r,["ObservationStartSample","ObservationEndSampleExclusive","AvailableAtSample"]);
            issued=obj.IssuedReceipt;
            assert(string(r.IssuedSetupReceiptSHA256)==string(issued.SHA256) && ...
                isequal(r.RRCTransactionID,issued.RRCTransactionID) && ...
                string(r.RRCSetupSHA256)==string(issued.RRCSetupSHA256), ...
                'sixgr:protocol:SRB1AdmissionConflict','Received Setup must match this original issued configuration.');
            assert(r.ObservationStartSample<r.ObservationEndSampleExclusive && ...
                r.ObservationEndSampleExclusive<=r.AvailableAtSample && ...
                r.AvailableAtSample<=sample && r.AvailableAtSample>=issued.IssuedAtSample, ...
                'sixgr:protocol:SRB1AdmissionClock','Retain original received coverage and causal delivery.');
            if ~isempty(fieldnames(obj.ReceivedReceipt))
                assert(isequaln(r,obj.ReceivedReceipt),'sixgr:protocol:SRB1AdmissionConflict', ...
                    'Activation cannot replace a different original receipt.');return;
            end
            receivedEnabled=(string(obj.Scope.Direction)=="UL"&&obj.TXEnabled)|| ...
                (string(obj.Scope.Direction)=="DL"&&obj.RXEnabled);
            assert(~receivedEnabled,'sixgr:protocol:SRB1AdmissionConflict','Initial received Setup cannot replace an active endpoint.');
            obj.ReceivedReceipt=r;
            if string(obj.Scope.Direction)=="UL",obj.TXEnabled=true;else,obj.RXEnabled=true;end
        end
        function require(obj,endpoint)
            endpoint=upper(string(endpoint));
            assert(isscalar(endpoint)&&any(endpoint==["TX","RX"]),'sixgr:protocol:SRB1AdmissionEndpoint','Require TX or RX endpoint.');
            assert((endpoint=="TX"&&obj.TXEnabled)||(endpoint=="RX"&&obj.RXEnabled), ...
                'sixgr:protocol:SRB1EndpointNotAdmitted','Endpoint lacks original Setup admission.');
        end
    end
end
function localClock(obj,sample)
localSamples(sample);
assert(isscalar(sample)&&sample>=obj.LastSample,'sixgr:protocol:SRB1AdmissionClock','Admission clock cannot move backwards.');
assert(obj.Mode=="original_setup_required",'sixgr:protocol:SRB1AdmissionPolicy','Original Setup admission needs its explicit policy.');
end
function names=localScopeFields()
names=["ExecutionRunID","UEID","ServingCell","RNTI","SRBID","LCID","Direction", ...
    "ConfigurationEpoch","ClockEpoch","SampleRateHz","ProtocolConfigurationSHA256"];
end
function localReceipt(obj,r,contract)
localFields(r,[localScopeFields(),"ContractVersion","RRCTransactionID","RRCSetupSHA256","SHA256"]);
assert(string(r.ContractVersion)==contract,'sixgr:protocol:SRB1AdmissionContract','Original receipt contract differs.');
for name=localScopeFields()
    assert(isequaln(r.(name),obj.Scope.(name)),'sixgr:protocol:SRB1AdmissionScope', ...
        'Original endpoint scope differs: %s.',name);
end
localSampleFields(r,"RRCTransactionID");
assert(r.RRCTransactionID<=3,'sixgr:protocol:SRB1AdmissionReceipt','RRC transaction identity must be 0 through 3.');
localHashes(r,["ProtocolConfigurationSHA256","RRCSetupSHA256","SHA256"]);
unsigned=rmfield(r,'SHA256');
assert(string(r.SHA256)==string(sixgr.l2.mac.MACHash.of(unsigned)), ...
    'sixgr:protocol:SRB1AdmissionDigest','Receipt lineage changed; adapters still own physical proof.');
end
function localFields(r,names)
assert(isstruct(r)&&isscalar(r)&&all(isfield(r,names)), ...
    'sixgr:protocol:SRB1AdmissionReceipt','Missing original admission operands.');
end
function localHashes(r,names)
for name=names
    value=string(r.(name));
    assert(isscalar(value)&&~ismissing(value)&&~isempty(regexp(char(value),'^[0-9a-f]{64}$','once')), ...
        'sixgr:protocol:SRB1AdmissionDigest','Missing original receipt hash: %s.',name);
end
end
function localSamples(values)
assert(isnumeric(values)&&all(isfinite(values)&values>=0&values==fix(values),'all'), ...
    'sixgr:protocol:SRB1AdmissionClock','Original sample indices must be finite nonnegative integers.');
end

function localSampleFields(r,names)
for name=names
    assert(isnumeric(r.(name))&&isscalar(r.(name)), 'sixgr:protocol:SRB1AdmissionClock','Clock operand must be a numeric scalar.');
    localSamples(r.(name));
end
end

function localText(value)
assert((ischar(value)&&isrow(value)||isstring(value)&&isscalar(value))&& ...
    ~ismissing(string(value))&&strlength(strtrim(string(value)))>0, ...
    'sixgr:protocol:SRB1AdmissionScope','Original execution and observation identities cannot be blank.');
end
