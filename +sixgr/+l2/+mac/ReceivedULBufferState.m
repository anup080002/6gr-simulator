classdef ReceivedULBufferState < handle
    % gNB demand from original received SR/BSR; never UE queue memory.
    properties (SetAccess=private)
        Scope struct
        SR cell = {}
        BSR cell = {}
        Debits cell = {}
    end
    methods
        function obj=ReceivedULBufferState(scope)
            obj.Scope=scope;
            for f=["RunID","ExecutionID","ConfigHash"]
                assert(isfield(scope,f)&&isscalar(string(scope.(f)))&&~ismissing(string(scope.(f)))&& ...
                    strlength(string(scope.(f)))>0,'sixgr:mac:ULBufferScope','Original identity required.');
            end
            for f=["UEID","CellID","RNTI","ConfigurationEpoch","SampleRateHz"]
                validateattributes(scope.(f),{'numeric'},{'scalar','real','finite','integer','positive'});
            end
        end
        function changed=admitSR(obj,row,scope)
            obj.checkScope(scope); changed=false;
            assert(row.UEIndex==scope.UEID && row.RNTI==scope.RNTI && row.ServingCell==scope.CellID, ...
                'sixgr:mac:ULBufferScope','Received SR belongs to a different UE/cell/RNTI.');
            validateattributes(row.AvailableAtSample,{'numeric'},{'scalar','finite','integer','nonnegative'});
            assert(strlength(string(row.ObservationID))>0 && strlength(string(row.ReceiverContextDigest))==64 && ...
                strlength(string(row.ReceiverAssignmentDigest))==64,'sixgr:mac:SRReceiverAuthority','Original receiver context required.');
            if ~(isequal(row.PositiveSRDetected,true)&&isequal(row.ReceiverUsable,true)&&isequal(row.DTXFlag,false)), return; end
            if any(cellfun(@(x)string(x.ObservationID)==string(row.ObservationID),obj.SR)), return; end
            obj.SR{end+1}=row; changed=true;
        end
        function [candidate,status]=previewAdmission(obj,bits,rx)
            shadow=sixgr.l2.mac.ReceivedULBufferState(obj.Scope);
            shadow.SR=obj.SR; shadow.BSR=obj.BSR; shadow.Debits=obj.Debits;
            status=shadow.admitBSR(bits,rx);
            if rx.CRCPass, shadow.recordDecodedSDU(rx); end
            candidate=struct('BaseSHA256',obj.stateDigest(),'Scope',obj.Scope, ...
                'SR',{shadow.SR},'BSR',{shadow.BSR},'Debits',{shadow.Debits});
            candidate.SHA256=sixgr.l2.mac.MACHash.of(candidate);
        end
        function validateAdmission(obj,candidate)
            assert(isequaln(candidate.Scope,obj.Scope)&&candidate.BaseSHA256==obj.stateDigest()&& ...
                candidate.SHA256==sixgr.l2.mac.MACHash.of(rmfield(candidate,'SHA256')), ...
                'sixgr:mac:BSRAdmissionConflict','Received BSR admission changed before commit.');
        end
        function commitAdmission(obj,candidate)
            obj.validateAdmission(candidate);
            obj.SR=candidate.SR; obj.BSR=candidate.BSR; obj.Debits=candidate.Debits;
        end
        function status=admitBSR(obj,bits,rx)
            obj.checkScope(rx.Scope);
            assert(string(rx.Direction)=="UL",'sixgr:mac:BSRDirection','BSR is received UL MAC.');
            validateattributes(rx.ObservationEndSampleExclusive,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            validateattributes(rx.AvailableSample,{'numeric'},{'scalar','real','finite','integer','>=',rx.ObservationEndSampleExclusive});
            assert(islogical(rx.CRCPass)&&isscalar(rx.CRCPass),'sixgr:mac:BSRCRC','Original decoder CRC required.');
            status="decoder_crc_failed_no_update"; if ~rx.CRCPass, return; end
            assert(isnumeric(bits)||islogical(bits),'sixgr:mac:BSRDecodedBits','Original bits required.');
            assert(isreal(bits)&&isvector(bits)&&~isempty(bits)&&mod(numel(bits),8)==0&&all(isfinite(bits(:)))&&all(bits(:)==0|bits(:)==1), ...
                'sixgr:mac:BSRDecodedBits','Complete binary decoded MAC TB required.');
            validateattributes(rx.OriginalTransmissionStartSample,{'numeric'},{'scalar','finite','integer','nonnegative'});
            assert(rx.OriginalTransmissionStartSample<=rx.ObservationEndSampleExclusive, ...
                'sixgr:mac:BSRClock','Original MAC transmission cannot follow its received observation.');
            validateattributes(rx.AvailableSample,{'numeric'},{'scalar','finite','integer','>=',rx.OriginalTransmissionStartSample});
            id=string(rx.LogicalTBID); assert(isscalar(id)&&strlength(id)>0,'sixgr:mac:BSRTBIdentity','Original TB required.');
            bytes=uint8(double(reshape(bits,8,[]).')*(2.^(7:-1:0)).');
            mac=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',bytes);
            for k=1:numel(obj.BSR)
                if obj.BSR{k}.LogicalTBID==id
                    assert(obj.BSR{k}.DecodedMACSHA256==mac.SHA256,'sixgr:mac:BSRTBConflict','Repeated TB changed decoded bytes.');
                    status="duplicate_success_no_update"; return;
                end
            end
            selected=find(ismember([mac.SubPDUs.LCID],[59 60 61 62]));
            assert(numel(selected)<=1,'sixgr:mac:DuplicateBSR','One base BSR per MAC PDU.');
            status="no_received_bsr"; if isempty(selected), return; end
            item=mac.SubPDUs(selected);
            assert(ismember(item.LCID,[61 62]),'sixgr:mac:TruncatedBSRContextRequired', ...
                'Truncated BSR requires installed logical-channel priority context.');
            report=sixgr.l2.mac.BSR_PHR.decodeBSR(item.LCID,item.Payload);
            % A full BSR covers all LCGs; absent groups have no buffered data.
            report.LowerExclusive(~report.BufferSizeFieldPresent)=0;
            report.UpperInclusive(~report.BufferSizeFieldPresent)=0;
            report.LogicalTBID=id; report.DecodedMACSHA256=mac.SHA256;
            report.OriginalTransmissionStartSample=rx.OriginalTransmissionStartSample;
            report.AvailableSample=rx.AvailableSample; report.Scope=rx.Scope;
            report.ReceiptSHA256=sixgr.l2.mac.MACHash.of(report);
            obj.BSR{end+1}=report; status="received_original_crc_confirmed_bsr";
        end
        function recordDecodedSDU(obj,rx)
            obj.checkScope(rx.Scope);
            assert(isequal(rx.CRCPass,true),'sixgr:mac:ULDebitCRC','Only CRC-confirmed decoded SDU bytes may debit received demand.');
            id=string(rx.LogicalTBID); startSample=rx.OriginalTransmissionStartSample;
            sduBytes=rx.DecodedRLCPayloadBytes;
            statusBytes=sixgr.util.structGet(rx,'DecodedRLCStatusBytes',0);
            validateattributes(startSample,{'numeric'},{'scalar','finite','integer','nonnegative'});
            validateattributes(sduBytes,{'numeric'},{'scalar','finite','integer','nonnegative'});
            validateattributes(statusBytes,{'numeric'},{'scalar','finite','integer','nonnegative'});
            id=string(id); assert(isscalar(id)&&strlength(id)>0,'sixgr:mac:ULDebitIdentity','Original new-data TX ID required.');
            validateattributes(rx.AvailableSample,{'numeric'},{'scalar','finite','integer','>=',startSample});
            row=struct('TransmissionID',id,'StartSample',startSample,'SDUBytes',sduBytes, ...
                'RLCStatusBytes',statusBytes,'ReceivedL2DebitBytes',sduBytes+statusBytes, ...
                'AvailableSample',rx.AvailableSample,'DecodedMACSHA256',string(rx.DecodedMACSHA256));
            for k=1:numel(obj.Debits)
                if obj.Debits{k}.TransmissionID==id
                    old=obj.Debits{k};
                    assert(old.StartSample==startSample&&old.SDUBytes==sduBytes&& ...
                        sixgr.util.structGet(old,'RLCStatusBytes',0)==statusBytes&&old.DecodedMACSHA256==row.DecodedMACSHA256, ...
                        'sixgr:mac:ULDebitConflict','One decoded logical TB debit cannot change.'); return;
                end
            end
            obj.Debits{end+1}=row;
        end
        function out=estimate(obj,scope,at,maxAge,probeBytes)
            obj.checkScope(scope);
            validateattributes(at,{'numeric'},{'scalar','finite','integer','nonnegative'});
            validateattributes(maxAge,{'numeric'},{'scalar','finite','integer','nonnegative'});
            validateattributes(probeBytes,{'numeric'},{'scalar','finite','integer','positive'});
            out=struct('BudgetBytes',0,'Source',"no_received_demand",'ReportedLowerBytes',NaN, ...
                'ReportedUpperBytes',NaN,'ReceiptSHA256',"",'BacklogExact',false);
            eligible=find(cellfun(@(x)x.AvailableSample<=at && at-x.OriginalTransmissionStartSample<=maxAge,obj.BSR));
            reference=-Inf;
            if ~isempty(eligible)
                [~,j]=max(cellfun(@(x)x.OriginalTransmissionStartSample,obj.BSR(eligible)));
                r=obj.BSR{eligible(j)}; reference=r.OriginalTransmissionStartSample;
                lo=r.LowerExclusive; hi=r.UpperInclusive;
                minimum=sum((lo+1).*(hi>0));
                used=sum(cellfun(@(x)(x.SDUBytes+sixgr.util.structGet(x,'RLCStatusBytes',0))* ...
                    (x.StartSample>reference&&x.AvailableSample<=at),obj.Debits));
                out.BudgetBytes=max(0,minimum-used); out.Source="received_BSR_lower_bound_policy";
                out.ReportedLowerBytes=sum(lo); out.ReportedUpperBytes=sum(hi); out.ReceiptSHA256=r.ReceiptSHA256;
            end
            sr=find(cellfun(@(x)x.AvailableAtSample<=at && at-x.AvailableAtSample<=maxAge && x.AvailableAtSample>reference,obj.SR));
            if out.BudgetBytes==0 && ~isempty(sr)
                last=max(cellfun(@(x)x.AvailableAtSample,obj.SR(sr)));
                consumed=any(cellfun(@(x)x.StartSample>=last&&x.AvailableSample<=at,obj.Debits));
                if ~consumed, out.BudgetBytes=probeBytes; out.Source="received_SR_probe_allocation_policy"; end
            end
        end
    end
    methods (Access=private)
        function h=stateDigest(obj)
            h=sixgr.l2.mac.MACHash.of(struct('Scope',obj.Scope,'SR',{obj.SR},'BSR',{obj.BSR},'Debits',{obj.Debits}));
        end
        function checkScope(obj,s)
            assert(isequaln(obj.Scope,s),'sixgr:mac:ULBufferScope','Received demand scope/generation differs.');
        end
    end
end
