classdef ReceivedPHRState < handle
    % Receiver-owned single-entry PHR. No TX payload input.
    % Caller must supply the original decoder result and receive-owner scope.
    properties (SetAccess=private)
        Scope struct
        Reports cell = cell(0,1)
        LogicalTBIDs string = strings(0,1)
        DecodedMACSHA256 string = strings(0,1)
    end
    methods
        function obj=ReceivedPHRState(scope)
            validateScope(scope); obj.Scope=scope;
        end
        function [candidate,status]=previewAdmission(obj,bits,rx)
            shadow=sixgr.l2.mac.ReceivedPHRState(obj.Scope);
            shadow.Reports=obj.Reports; shadow.LogicalTBIDs=obj.LogicalTBIDs;
            shadow.DecodedMACSHA256=obj.DecodedMACSHA256;
            status=shadow.admit(bits,rx);
            candidate=struct('BaseSHA256',obj.stateDigest(),'Scope',obj.Scope, ...
                'Reports',{shadow.Reports},'LogicalTBIDs',shadow.LogicalTBIDs, ...
                'DecodedMACSHA256',shadow.DecodedMACSHA256);
            candidate.SHA256=sixgr.l2.mac.MACHash.of(candidate);
        end
        function validateAdmission(obj,candidate)
            assert(isequaln(candidate.Scope,obj.Scope)&&candidate.BaseSHA256==obj.stateDigest()&& ...
                candidate.SHA256==sixgr.l2.mac.MACHash.of(rmfield(candidate,'SHA256')), ...
                'sixgr:mac:PHRAdmissionConflict','Received PHR admission changed before commit.');
        end
        function commitAdmission(obj,candidate)
            obj.validateAdmission(candidate);
            obj.Reports=candidate.Reports; obj.LogicalTBIDs=candidate.LogicalTBIDs;
            obj.DecodedMACSHA256=candidate.DecodedMACSHA256;
        end
        function status=admit(obj,decodedBits,rx)
            validateScope(rx.Scope);
            assert(isequaln(rx.Scope,obj.Scope),'sixgr:mac:PHRReceiveScope', ...
                'Original received UE/cell/RNTI/run/configuration scope differs.');
            assert(islogical(rx.CRCPass)&&isscalar(rx.CRCPass), ...
                'sixgr:mac:PHRCRCOutcome','CRC must be an explicit original decoder outcome.');
            assert(string(rx.Direction)=="UL",'sixgr:mac:PHRDirection','PHR is UL MAC.');
            validateattributes(rx.ObservationEndSampleExclusive,{'numeric'}, ...
                {'scalar','real','finite','integer','nonnegative'});
            validateattributes(rx.AvailableSample,{'numeric'}, ...
                {'scalar','real','finite','integer','>=',rx.ObservationEndSampleExclusive});
            validateattributes(rx.OriginalTransmissionStartSample,{'numeric'}, ...
                {'scalar','real','finite','integer','nonnegative','<=',rx.ObservationEndSampleExclusive});
            context=string(rx.ReferenceGrantContextID);
            assert(isscalar(context)&&~ismissing(context)&&strlength(context)>0, ...
                'sixgr:mac:PHRReferenceGrant','Original new-data grant reference required.');
            id=string(rx.LogicalTBID); source=string(rx.TransmissionID);
            assert(isscalar(id)&&strlength(id)>0&&~ismissing(id)&& ...
                isscalar(source)&&strlength(source)>0&&~ismissing(source), ...
                'sixgr:mac:PHRReceiveIdentity','Original decoded TB and attempt identities required.');
            if ~rx.CRCPass, status="decoder_crc_failed_no_state_update"; return; end
            assert((isnumeric(decodedBits)||islogical(decodedBits))&&isreal(decodedBits)&& ...
                isvector(decodedBits)&&~isempty(decodedBits)&&mod(numel(decodedBits),8)==0&& ...
                all(isfinite(decodedBits(:)))&&all(decodedBits(:)==0|decodedBits(:)==1), ...
                'sixgr:mac:PHRDecodedBits','Require the original complete binary decoded MAC TB.');
            bytes=uint8(double(reshape(decodedBits,8,[]).')*(2.^(7:-1:0)).');
            macHash=sixgr.l2.mac.MACHash.of(bytes(:).');
            seen=find(obj.LogicalTBIDs==id);
            if ~isempty(seen)
                assert(isscalar(seen)&&obj.DecodedMACSHA256(seen)==macHash, ...
                    'sixgr:mac:PHRTBConflict','One logical TB cannot decode to different bytes.');
                status="duplicate_success_no_state_update"; return;
            end
            mac=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',bytes);
            % Existing generic demux casts bytes and does not validate every
            % reserved header bit. Inputs are already binary; check headers
            % here before interpreting the bounded single-entry subset.
            for k=1:numel(mac.SubPDUs)
                item=mac.SubPDUs(k); h=bytes(item.HeaderOffset+1);
                assert(bitand(h,uint8(128))==0,'sixgr:mac:PHRReservedHeader','MAC R bit must be zero.');
                if item.HeaderLength==1
                    assert(bitand(h,uint8(64))==0,'sixgr:mac:PHRReservedHeader','Fixed subheader R bit must be zero.');
                end
            end
            if mac.PaddingBytes>0
                at=numel(bytes)-mac.PaddingBytes+1;
                assert(bytes(at)==63,'sixgr:mac:PHRReservedHeader','Padding header must be canonical.');
            end
            if isempty(mac.SubPDUs), status="no_single_entry_phr"; return; end
            chosen=find([mac.SubPDUs.LCID]==57);
            assert(numel(chosen)<=1,'sixgr:mac:DuplicatePHRCE','Single PCell report cannot be duplicated in one MAC PDU.');
            if isempty(chosen), status="no_single_entry_phr"; return; end
            item=mac.SubPDUs(chosen);
            [~,~,~,report]=sixgr.l2.mac.BSR_PHR.decodeSingleEntryPHR(item.Payload);
            report.PHType="Type1_PCell"; report.Scope=rx.Scope;
            report.LogicalTBID=id; report.TransmissionID=source;
            report.ObservationEndSampleExclusive=rx.ObservationEndSampleExclusive;
            report.AvailableSample=rx.AvailableSample;
            report.OriginalTransmissionStartSample=rx.OriginalTransmissionStartSample;
            report.ReferenceGrantContextID=context;
            if isfield(rx,'ReferenceAllocation'), report.ReferenceAllocation=rx.ReferenceAllocation; end
            report.DecodedMACSHA256=macHash; report.PayloadSHA256=item.PayloadSHA256;
            report.DecodedBitCount=numel(decodedBits);
            report.ReceiptSHA256=sixgr.l2.mac.MACHash.of(report);
            obj.Reports{end+1,1}=report;
            obj.LogicalTBIDs(end+1,1)=id; obj.DecodedMACSHA256(end+1,1)=macHash;
            status="received_original_crc_confirmed_single_entry_phr";
        end
        function out=eligible(obj,scope,decisionSample,maxAgeSamples)
            validateScope(scope);
            validateattributes(decisionSample,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            validateattributes(maxAgeSamples,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            out=struct('Usable',false,'Reason',"no_received_phr",'Report',struct());
            if ~isequaln(scope,obj.Scope), out.Reason="wrong_received_identity_or_generation"; return; end
            if isempty(obj.Reports), return; end
            clocks=cellfun(@(x)x.AvailableSample,obj.Reports);
            candidates=find(clocks<=decisionSample);
            if isempty(candidates), out.Reason="received_phr_not_yet_available"; return; end
            % Delayed decoding must not replace a newer original PH observation.
            originalClocks=cellfun(@(x)x.OriginalTransmissionStartSample,obj.Reports);
            [~,i]=max(originalClocks(candidates)); report=obj.Reports{candidates(i)};
            if decisionSample-report.OriginalTransmissionStartSample>maxAgeSamples
                out.Reason="received_phr_expired"; return;
            end
            out.Usable=true; out.Reason="original_received_quantized_interval"; out.Report=report;
        end
    end
    methods (Access=private)
        function h=stateDigest(obj)
            h=sixgr.l2.mac.MACHash.of(struct('Scope',obj.Scope,'Reports',{obj.Reports}, ...
                'LogicalTBIDs',obj.LogicalTBIDs,'DecodedMACSHA256',obj.DecodedMACSHA256));
        end
    end
end

function validateScope(s)
assert(isstruct(s)&&isscalar(s),'sixgr:mac:PHRScope','Scalar original receive scope required.');
for field=["RunID","ExecutionID","ConfigHash"]
    x=string(s.(field)); assert(isscalar(x)&&~ismissing(x)&&strlength(x)>0, ...
        'sixgr:mac:PHRScope','Original run/config identity required.');
end
for field=["UEID","CellID","RNTI","SampleRateHz"]
    validateattributes(s.(field),{'numeric'},{'scalar','real','finite','integer','positive'});
end
validateattributes(s.ConfigurationEpoch,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
end
