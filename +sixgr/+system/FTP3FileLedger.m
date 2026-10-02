classdef FTP3FileLedger < handle
%FTP3FILELEDGER FIFO application-file ownership over actual HARQ TBs.
% Reserve at first transmission using the real grant TBS, retain that file
% binding for retransmissions, and commit it only on first CRC success.
% Arrival timestamps retain continuous-time generator evidence. Receiver
% completion is resolved to the end of the executed TTI, not sub-slot time.
    properties (SetAccess=private)
        Files table
        Events table
        TTIDuration_s double
        NumUE double
        CurrentTTI double = 0
    end
    properties (Access=private)
        TBs
    end
    methods
        function obj=FTP3FileLedger(arrivals,tti_s,nUE)
            arguments
                arrivals table
                tti_s (1,1) double {mustBePositive,mustBeFinite}
                nUE (1,1) double {mustBeInteger,mustBePositive}
            end
            names=["ArrivalID","ArrivalTTI","ArrivalTime_s","UEID","Direction","OfferedBits"];
            if ~all(ismember(names,string(arrivals.Properties.VariableNames)))
                error("sixgr:traffic:FTP3FileSchema","Arrival ledger lacks file identity/time/size.");
            end
            if numel(unique(string(arrivals.ArrivalID)))~=height(arrivals) || ...
                    any(strlength(string(arrivals.ArrivalID))==0) || ...
                    any(~ismember(string(arrivals.Direction),["DL","UL"])) || ...
                    any(~isfinite(arrivals.ArrivalTime_s) | arrivals.ArrivalTime_s<0) || ...
                    any(arrivals.ArrivalTTI~=floor(arrivals.ArrivalTime_s/tti_s)+1) || ...
                    any(~isfinite(arrivals.UEID) | arrivals.UEID<1 | arrivals.UEID>nUE | arrivals.UEID~=fix(arrivals.UEID)) || ...
                    any(~isfinite(arrivals.OfferedBits) | arrivals.OfferedBits<1 | arrivals.OfferedBits~=fix(arrivals.OfferedBits))
                error("sixgr:traffic:FTP3FileIdentity","Invalid/duplicate arrival identity, time, UE or file bits.");
            end
            obj.TTIDuration_s=tti_s; obj.NumUE=nUE;
            obj.Files=sortrows(arrivals,["ArrivalTime_s","ArrivalID"]);
            n=height(arrivals);
            obj.Files.Admitted=false(n,1);
            obj.Files.AllocatedBits=zeros(n,1);
            obj.Files.ReservedBits=zeros(n,1);
            obj.Files.DeliveredBits=zeros(n,1);
            obj.Files.DroppedBits=zeros(n,1);
            obj.Files.TailDroppedBits=zeros(n,1);
            obj.Files.FirstTransmissionTTI=NaN(n,1);
            obj.Files.CompletionTTI=NaN(n,1);
            obj.Files.CompletionTime_s=NaN(n,1);
            obj.TBs=containers.Map('KeyType','char','ValueType','any');
            obj.Events=table(strings(0,1),zeros(0,1),strings(0,1),zeros(0,1), ...
                zeros(0,1),strings(0,1),zeros(0,1),zeros(0,1),strings(0,1),strings(0,1), ...
                'VariableNames',{'TBIdentity','UEID','Direction','TTI','Time_s', ...
                'Event','PayloadBits','TBSBits','FileBindingJSON','EventTimeResolution'});
        end

        function advance(obj,tti)
            obj.validateTTI(tti);
            if tti<obj.CurrentTTI
                error("sixgr:traffic:FTP3ClockBackwards","FTP3 ledger clock cannot move backwards.");
            end
            obj.CurrentTTI=tti;
            obj.Files.Admitted=obj.Files.ArrivalTTI<=tti;
        end

        function b=bind(obj,tbIdentity,ue,direction,tbsBits,tti,isRetransmission)
            obj.advance(tti); obj.validateUE(ue,direction);
            key=char(string(tbIdentity));
            if isempty(key) || ~(isscalar(tbsBits) && isfinite(tbsBits) && tbsBits>=1 && tbsBits==fix(tbsBits))
                error("sixgr:traffic:FTP3TBIdentity","Binding requires immutable TB identity and actual positive integer TBS.");
            end
            if isKey(obj.TBs,key)
                b=obj.TBs(key);
                if ~isRetransmission || b.UEID~=ue || b.Direction~=direction || b.TBSBits~=tbsBits
                    error("sixgr:traffic:FTP3TBMutation","TB identity was reused with changed ownership/size or as new data.");
                end
                obj.record(b,tti,"retransmission_existing_binding",0);
                return
            elseif isRetransmission
                error("sixgr:traffic:FTP3UnknownRetransmission","Retransmission has no first-TX file binding.");
            end
            rows=find(obj.Files.Admitted & obj.Files.UEID==ue & string(obj.Files.Direction)==direction);
            left=tbsBits; mapping=zeros(0,3);
            for k=rows.'
                available=obj.Files.OfferedBits(k)-obj.Files.AllocatedBits(k)-obj.Files.TailDroppedBits(k);
                take=min(available,left);
                if take<=0, continue; end
                mapping(end+1,:)=[k,obj.Files.AllocatedBits(k),take]; %#ok<AGROW>
                obj.Files.AllocatedBits(k)=obj.Files.AllocatedBits(k)+take;
                obj.Files.ReservedBits(k)=obj.Files.ReservedBits(k)+take;
                if isnan(obj.Files.FirstTransmissionTTI(k)), obj.Files.FirstTransmissionTTI(k)=tti; end
                left=left-take;
                if left==0, break; end
            end
            b=struct("TBIdentity",string(key),"UEID",ue,"Direction",string(direction), ...
                "TBSBits",tbsBits,"PayloadBits",tbsBits-left,"PaddingBits",left, ...
                "FirstTransmissionTTI",tti,"Mapping",mapping,"Status","in_flight");
            obj.TBs(key)=b; obj.record(b,tti,"first_transmission_bound",b.PayloadBits);
        end

        function bits=complete(obj,tbIdentity,tti)
            obj.advance(tti); b=obj.requireTB(tbIdentity); bits=0;
            if b.Status~="in_flight"
                obj.record(b,tti,"duplicate_or_late_completion_ignored",0);
                return
            end
            for j=1:size(b.Mapping,1)
                k=b.Mapping(j,1); n=b.Mapping(j,3);
                obj.Files.ReservedBits(k)=obj.Files.ReservedBits(k)-n;
                obj.Files.DeliveredBits(k)=obj.Files.DeliveredBits(k)+n;
                if obj.Files.DeliveredBits(k)==obj.Files.OfferedBits(k) && obj.Files.DroppedBits(k)==0
                    obj.Files.CompletionTTI(k)=tti;
                    obj.Files.CompletionTime_s(k)=tti*obj.TTIDuration_s;
                end
            end
            bits=b.PayloadBits; b.Status="delivered";
            obj.TBs(char(b.TBIdentity))=b; obj.record(b,tti,"first_success_delivered",bits);
        end

        function bits=abandon(obj,tbIdentity,tti)
            % Invoke only when the real HARQ/runtime drops the immutable TB.
            obj.advance(tti); b=obj.requireTB(tbIdentity); bits=0;
            if b.Status~="in_flight", return; end
            for j=1:size(b.Mapping,1)
                k=b.Mapping(j,1); n=b.Mapping(j,3);
                obj.Files.ReservedBits(k)=obj.Files.ReservedBits(k)-n;
                obj.Files.DroppedBits(k)=obj.Files.DroppedBits(k)+n;
            end
            bits=b.PayloadBits; b.Status="dropped";
            obj.TBs(char(b.TBIdentity))=b; obj.record(b,tti,"harq_payload_dropped",bits);
        end

        function dropTail(obj,ue,direction,bits,tti)
            obj.advance(tti); obj.validateUE(ue,direction);
            if ~(isscalar(bits) && isfinite(bits) && bits>=0 && bits==fix(bits))
                error("sixgr:traffic:FTP3DropBits","Drop amount must be a nonnegative integer.");
            end
            rows=find(obj.Files.Admitted & obj.Files.UEID==ue & string(obj.Files.Direction)==direction);
            unbound=obj.Files.OfferedBits(rows)-obj.Files.AllocatedBits(rows)-obj.Files.TailDroppedBits(rows);
            if bits>sum(unbound)
                error("sixgr:traffic:FTP3DropInflight","Tail drop cannot silently remove payload already bound to an in-flight TB.");
            end
            left=bits; mapping=zeros(0,3);
            for k=flip(rows).'
                available=obj.Files.OfferedBits(k)-obj.Files.AllocatedBits(k)-obj.Files.TailDroppedBits(k);
                take=min(left,available);
                if take<=0, continue; end
                start=obj.Files.OfferedBits(k)-obj.Files.TailDroppedBits(k)-take;
                mapping(end+1,:)=[k,start,take]; %#ok<AGROW>
                obj.Files.TailDroppedBits(k)=obj.Files.TailDroppedBits(k)+take;
                obj.Files.DroppedBits(k)=obj.Files.DroppedBits(k)+take;
                left=left-take;
                if left==0, break; end
            end
            b=struct("TBIdentity","","UEID",ue,"Direction",string(direction), ...
                "TBSBits",NaN,"Mapping",mapping);
            obj.record(b,tti,"queue_tail_drop",bits);
        end

        function bits=queuedBits(obj,ue,direction)
            obj.validateUE(ue,direction);
            r=obj.Files.Admitted & obj.Files.UEID==ue & string(obj.Files.Direction)==direction;
            bits=sum(obj.Files.OfferedBits(r)-obj.Files.DeliveredBits(r)-obj.Files.DroppedBits(r));
        end

        function bits=unallocatedBits(obj,ue,direction)
            % New-data scheduling excludes ranges owned by in-flight TBs.
            % Retransmissions remain schedulable from their immutable binding.
            obj.validateUE(ue,direction);
            r=obj.Files.Admitted & obj.Files.UEID==ue & string(obj.Files.Direction)==direction;
            bits=sum(obj.Files.OfferedBits(r)-obj.Files.AllocatedBits(r)-obj.Files.TailDroppedBits(r));
        end

        function out=snapshot(obj,endTTI)
            obj.advance(endTTI);
            F=obj.Files(obj.Files.Admitted,:);
            F.RemainingBits=F.OfferedBits-F.DeliveredBits-F.DroppedBits;
            F.Completed=isfinite(F.CompletionTTI);
            F.HasDroppedPayload=F.DroppedBits>0;
            F.RightCensored=F.RemainingBits>0;
            F.Status=repmat("right_censored",height(F),1);
            F.Status(F.HasDroppedPayload)="dropped_payload_incomplete_file";
            F.Status(F.Completed)="completed";
            F.FileTransferDelay_s=F.CompletionTime_s-F.ArrivalTime_s;
            F.FileUPT_bps=F.OfferedBits./F.FileTransferDelay_s;
            F.CensorTime_s=repmat(endTTI*obj.TTIDuration_s,height(F),1);
            F.CompletionTimeResolution=repmat("executed_TTI_end_boundary",height(F),1);
            F.ArrivalAdmissionResolution=repmat("continuous_arrival_binned_to_containing_TTI",height(F),1);
            F.FileUPTDefinition=repmat("completed_file_bits_over_arrival_to_completion_seconds",height(F),1);
            F.Source=repmat("immutable_actual_TB_binding_first_success_application_FIFO",height(F),1);
            summary=table('Size',[0,13], ...
                'VariableTypes',["double","string",repmat("double",1,11)], ...
                'VariableNames',{'UEID','Direction','ArrivedFileCount','CompletedFileCount', ...
                'CensoredFileCount','DroppedFileCount','OfferedBits','UniqueDeliveredBits', ...
                'DroppedBits','RemainingBits','MeanCompletedFileUPT_bps', ...
                'PooledCompletedFileUPT_bps','WallClockGoodput_bps'});
            for direction=["DL","UL"]
                for ue=1:obj.NumUE
                    r=F.UEID==ue & string(F.Direction)==direction; completed=r & F.Completed;
                    if ~any(r), continue; end
                    meanUPT=NaN; pooledUPT=NaN;
                    if any(completed)
                        meanUPT=mean(F.FileUPT_bps(completed));
                        pooledUPT=sum(F.OfferedBits(completed))/sum(F.FileTransferDelay_s(completed));
                    end
                    row=table(ue,direction,nnz(r),nnz(completed),nnz(r & F.RightCensored), ...
                        nnz(r & F.HasDroppedPayload),sum(F.OfferedBits(r)),sum(F.DeliveredBits(r)), ...
                        sum(F.DroppedBits(r)),sum(F.RemainingBits(r)),meanUPT,pooledUPT, ...
                        sum(F.DeliveredBits(r))/(endTTI*obj.TTIDuration_s), ...
                        'VariableNames',{'UEID','Direction','ArrivedFileCount','CompletedFileCount', ...
                        'CensoredFileCount','DroppedFileCount','OfferedBits','UniqueDeliveredBits', ...
                        'DroppedBits','RemainingBits','MeanCompletedFileUPT_bps', ...
                        'PooledCompletedFileUPT_bps','WallClockGoodput_bps'});
                    summary=[summary;row]; %#ok<AGROW>
                end
            end
            if any(F.RemainingBits<0) || any(F.ReservedBits<0) || any(F.ReservedBits>F.RemainingBits)
                error("sixgr:traffic:FTP3LedgerConservation","Application file bit conservation failed.");
            end
            summary.UPTDefinition=repmat("completed_files_only_arrival_to_completion_includes_queue_delay",height(summary),1);
            summary.Source=repmat("immutable_actual_TB_binding_first_success_application_FIFO",height(summary),1);
            out=struct("Files",F,"DeliveryEvents",obj.Events,"UserSummary",summary, ...
                "Source","immutable_actual_TB_binding_first_success_application_FIFO", ...
                "TransportSemantics","fixed_file_application_workload_no_TCP_or_packet_byte_integrity_claim");
        end
    end
    methods (Access=private)
        function b=requireTB(obj,key)
            key=char(string(key));
            if ~isKey(obj.TBs,key)
                error("sixgr:traffic:FTP3UnknownTB","No first-transmission binding exists for this TB.");
            end
            b=obj.TBs(key);
        end
        function validateUE(obj,ue,direction)
            if ~(isscalar(ue) && isfinite(ue) && ue>=1 && ue<=obj.NumUE && ue==fix(ue)) || ...
                    ~isscalar(string(direction)) || ~ismember(string(direction),["DL","UL"])
                error("sixgr:traffic:FTP3UEIdentity","Invalid UE or direction.");
            end
        end
        function validateTTI(~,tti)
            if ~(isscalar(tti) && isfinite(tti) && tti>=1 && tti==fix(tti))
                error("sixgr:traffic:FTP3TTI","An executed positive integer TTI is required.");
            end
        end
        function record(obj,b,tti,event,bits)
            map=b.Mapping;
            fileIDs=string(obj.Files.ArrivalID(map(:,1)));
            bindings=table(fileIDs,map(:,2),map(:,3), ...
                'VariableNames',{'ArrivalID','OffsetStart_bit','PayloadBits'});
            eventTime=tti*obj.TTIDuration_s; timeResolution="executed_TTI_end_boundary";
            if ismember(string(event),["first_transmission_bound","retransmission_existing_binding"])
                eventTime=NaN; timeResolution="transmission_TTI_only_no_subslot_timestamp";
            end
            row=table(string(b.TBIdentity),b.UEID,string(b.Direction),tti,eventTime, ...
                string(event),bits,b.TBSBits,string(jsonencode(table2struct(bindings))), ...
                timeResolution, ...
                'VariableNames',obj.Events.Properties.VariableNames);
            obj.Events=[obj.Events;row];
        end
    end
end
