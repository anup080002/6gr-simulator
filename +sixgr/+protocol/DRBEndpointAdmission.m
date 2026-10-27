classdef DRBEndpointAdmission
    % Endpoint knowledge gate; callers validate private original PHY/PDCP proof.
    % Hashes are lineage, not execution proof. No Runtime/COUNT state is owned.
    properties (SetAccess=private)
        Scope struct
        Mode string
        RXEnabled logical=false
        TXEnabled logical=false
        IssuedReceipt struct=struct()
        ReceivedReceipt struct=struct()
        CompleteReceipt struct=struct()
        LastSample double=0
    end
    methods
        function obj=DRBEndpointAdmission(scope,mode)
            assert(isstruct(scope)&&isscalar(scope)&&all(isfield(scope,localScopeFields())), ...
                'sixgr:protocol:DRBAdmissionScope','Original connection, bearer, execution and clock required.');
            localText(mode);obj.Mode=string(mode);
            assert(obj.Mode=="original_reconfiguration_required", ...
                'sixgr:protocol:DRBAdmissionPolicy','This owner requires original reconfiguration.');
            for n=["ExecutionRunID","UEID","BearerID"],localText(scope.(n));end
            localIntegerFields(scope,["ServingCell","RNTI","DRBID","LCID","ConfigurationEpoch","ClockEpoch"]);
            assert(scope.ServingCell>=1&&scope.RNTI>=1&&scope.RNTI<=65522&& ...
                scope.DRBID>=1&&scope.DRBID<=32&&scope.LCID>=4&&scope.LCID<=32, ...
                'sixgr:protocol:DRBAdmissionScope','Invalid original cell/C-RNTI/DRB/LCID domain.');
            assert(isnumeric(scope.SampleRateHz)&&isreal(scope.SampleRateHz)&&isscalar(scope.SampleRateHz)&& ...
                isfinite(scope.SampleRateHz)&&scope.SampleRateHz>0, ...
                'sixgr:protocol:DRBAdmissionScope','Original positive sample rate required.');
            localText(scope.Direction);
            assert(any(string(scope.Direction)==["UL","DL"]),'sixgr:protocol:DRBAdmissionScope','Use UL or DL.');
            localHashes(scope,"ProtocolConfigurationSHA256");obj.Scope=scope;
        end
        function obj=admitIssued(obj,r,sample)
            localClock(obj,sample);localReceipt(obj,r,"issued_NR_DRB_reconfiguration/v1");
            fields=["TransmitComponentID","TransmitEnqueueReceiptSHA256","OriginalComponentSampleSHA256", ...
                "TransmitObservationSHA256","PhysicalTransmissionReceiptSHA256","ProtectedPDCPPDUSHA256", ...
                "SecurityContextID","IntegrityProtected","TransmitStartSample","TransmitEndSampleExclusive","IssuedAtSample"];
            localFields(r,fields);localText(r.TransmitComponentID);localText(r.SecurityContextID);
            localHashes(r,fields(2:6));localTrue(r.IntegrityProtected);
            localIntegerFields(r,["TransmitStartSample","TransmitEndSampleExclusive","IssuedAtSample"]);
            assert(r.TransmitStartSample<r.TransmitEndSampleExclusive&&r.TransmitEndSampleExclusive<=r.IssuedAtSample&& ...
                r.IssuedAtSample<=sample,'sixgr:protocol:DRBAdmissionClock','Require completed original protected transmission.');
            if ~isempty(fieldnames(obj.IssuedReceipt))
                localSame(r,obj.IssuedReceipt);obj.LastSample=sample;return;
            end
            assert(~obj.RXEnabled&&~obj.TXEnabled,'sixgr:protocol:DRBAdmissionConflict','Initial endpoint already admitted.');
            obj.IssuedReceipt=r;obj.LastSample=sample;
            % gNB may receive UL after issuing the configuration. It does not
            % infer UE reception and cannot transmit DL DRB data yet.
            if string(obj.Scope.Direction)=="UL",obj.RXEnabled=true;end
        end
        function obj=admitReceived(obj,r,sample)
            localClock(obj,sample);localReceived(obj,r,sample,"received_NR_DRB_reconfiguration/v1");
            assert(string(r.ProtectedPDCPPDUSHA256)==string(obj.IssuedReceipt.ProtectedPDCPPDUSHA256), ...
                'sixgr:protocol:DRBAdmissionConflict','Received reconfiguration must retain original protected PDCP bytes.');
            if ~isempty(fieldnames(obj.ReceivedReceipt))
                localSame(r,obj.ReceivedReceipt);obj.LastSample=sample;return;
            end
            obj.ReceivedReceipt=r;obj.LastSample=sample;
            if string(obj.Scope.Direction)=="UL",obj.TXEnabled=true;else,obj.RXEnabled=true;end
        end
        function obj=admitComplete(obj,r,sample)
            localClock(obj,sample);localReceived(obj,r,sample,"received_NR_DRB_reconfiguration_complete/v1");
            localFields(r,"RRCReconfigurationCompleteSHA256");localHashes(r,"RRCReconfigurationCompleteSHA256");
            % Deliberately no ReceivedReceipt lookup: gNB knows the issued
            % transaction and its own protected Complete reception only.
            if ~isempty(fieldnames(obj.CompleteReceipt))
                localSame(r,obj.CompleteReceipt);obj.LastSample=sample;return;
            end
            obj.CompleteReceipt=r;obj.LastSample=sample;
            if string(obj.Scope.Direction)=="DL",obj.TXEnabled=true;end
            % Waiting for Complete before gNB DL TX is a conservative
            % simulator sequencing policy, not a universal NR requirement.
        end
        function require(obj,endpoint)
            localText(endpoint);endpoint=upper(string(endpoint));
            assert(any(endpoint==["TX","RX"]),'sixgr:protocol:DRBAdmissionEndpoint','Use TX or RX.');
            assert((endpoint=="TX"&&obj.TXEnabled)||(endpoint=="RX"&&obj.RXEnabled), ...
                'sixgr:protocol:DRBEndpointNotAdmitted','Endpoint lacks its original admission event.');
        end
    end
end
function localReceived(obj,r,sample,contract)
localReceipt(obj,r,contract);
assert(~isempty(fieldnames(obj.IssuedReceipt)),'sixgr:protocol:DRBIssuedReconfigurationRequired', ...
    'Join this original issued transaction before admitting a receiver event.');
fields=["IssuedReconfigurationReceiptSHA256","ReceiverObservationID","ReceiverObservationSHA256", ...
    "ReceivedMACPayloadSHA256","ProtectedPDCPPDUSHA256","SecurityContextID","IntegrityVerified", ...
    "ObservationStartSample","ObservationEndSampleExclusive","AvailableAtSample"];
localFields(r,fields);localText(r.ReceiverObservationID);localText(r.SecurityContextID);
localHashes(r,fields([1 3 4 5]));localTrue(r.IntegrityVerified);
localIntegerFields(r,fields(8:10));i=obj.IssuedReceipt;
assert(string(r.IssuedReconfigurationReceiptSHA256)==string(i.SHA256)&& ...
    r.RRCTransactionID==i.RRCTransactionID&&string(r.RRCReconfigurationSHA256)==string(i.RRCReconfigurationSHA256)&& ...
    string(r.ConnectionReceiptSHA256)==string(i.ConnectionReceiptSHA256), ...
    'sixgr:protocol:DRBAdmissionConflict','Original transaction/message/connection generation differs.');
assert(r.ObservationStartSample<r.ObservationEndSampleExclusive&& ...
    r.ObservationEndSampleExclusive<=r.AvailableAtSample&&r.AvailableAtSample<=sample&& ...
    r.AvailableAtSample>=i.IssuedAtSample, ...
    'sixgr:protocol:DRBAdmissionClock','Original receive coverage and available sample must be causal.');
end
function localReceipt(obj,r,contract)
localFields(r,[localScopeFields(),"ContractVersion","RRCTransactionID", ...
    "RRCReconfigurationSHA256","ConnectionReceiptSHA256","SHA256"]);
localText(r.ContractVersion);
assert(string(r.ContractVersion)==contract,'sixgr:protocol:DRBAdmissionContract','Receipt kind differs.');
for n=localScopeFields()
    assert(isequaln(r.(n),obj.Scope.(n)),'sixgr:protocol:DRBAdmissionScope','Original scope differs: %s.',n);
end
localIntegerFields(r,"RRCTransactionID");
assert(r.RRCTransactionID<=3,'sixgr:protocol:DRBAdmissionReceipt','RRC transaction ID must be0..3.');
localHashes(r,["RRCReconfigurationSHA256","ConnectionReceiptSHA256","SHA256"]);
assert(string(r.SHA256)==string(sixgr.l2.mac.MACHash.of(rmfield(r,'SHA256'))), ...
    'sixgr:protocol:DRBAdmissionDigest','Original receipt lineage changed; physical proof remains caller-owned.');
end
function fields=localScopeFields()
fields=["ExecutionRunID","UEID","BearerID","ServingCell","RNTI","DRBID","LCID","Direction", ...
    "ConfigurationEpoch","ClockEpoch","SampleRateHz","ProtocolConfigurationSHA256"];
end
function localClock(obj,sample)
localInteger(sample);
assert(sample>=obj.LastSample,'sixgr:protocol:DRBAdmissionClock','Admission clock cannot move backwards.');
end
function localSame(a,b)
assert(isequaln(a,b),'sixgr:protocol:DRBAdmissionConflict','Cannot replace an original admission receipt.');
end
function localFields(r,names)
assert(isstruct(r)&&isscalar(r)&&all(isfield(r,names)), ...
    'sixgr:protocol:DRBAdmissionReceipt','Missing original admission operands.');
end
function localIntegerFields(r,names)
for n=names,localInteger(r.(n));end
end
function localInteger(x)
assert(isnumeric(x)&&isreal(x)&&isscalar(x)&&isfinite(x)&&x>=0&&x<=flintmax&&x==fix(x), ...
    'sixgr:protocol:DRBAdmissionClock','Exact nonnegative finite numeric integer required.');
end
function localText(x)
assert((ischar(x)&&isrow(x)||isstring(x)&&isscalar(x))&& ...
    ~ismissing(string(x))&&strlength(strtrim(string(x)))>0, ...
    'sixgr:protocol:DRBAdmissionScope','Original identity must be nonempty scalar text.');
end
function localHashes(r,names)
for n=names
    localText(r.(n));v=string(r.(n));
    assert(~isempty(regexp(char(v),'^[0-9a-f]{64}$','once')), ...
        'sixgr:protocol:DRBAdmissionDigest','Require original lowercase SHA256: %s.',n);
end
end
function localTrue(v)
assert(islogical(v)&&isscalar(v)&&v,'sixgr:protocol:DRBAdmissionProtection', ...
    'Caller must retain an actual original protected-PDCP outcome, not a truthy numeric flag.');
end
