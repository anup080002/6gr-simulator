classdef PHRStateMachine < handle
    % Pure preview; committed new-data MAC CE transaction consumes triggers.
    properties (SetAccess=private)
        UEID (1,1) double
        PendingTrigger (1,1) string = "none"
        ProhibitUntilSlot (1,1) double = -Inf
        PeriodicDueSlot (1,1) double = Inf
        PeriodicSlots (1,1) double = Inf
        PeriodicStarted (1,1) logical = false
        CurrentSlot (1,1) double = 0
        TriggerGeneration (1,1) double = 0
        LastCommittedGeneration (1,1) double = -1
        CommittedTransmissionIDs string = strings(0,1)
        CommittedReportHashes string = strings(0,1)
    end
    methods
        function obj=PHRStateMachine(ueID,periodicSlots)
            validateattributes(ueID,{'numeric'},{'scalar','integer','positive','finite'});
            obj.UEID=double(ueID);
            if nargin<2, periodicSlots=Inf; end
            assert(isscalar(periodicSlots)&&isreal(periodicSlots)&& ...
                ((isfinite(periodicSlots)&&periodicSlots>=1&&periodicSlots==fix(periodicSlots))||periodicSlots==Inf), ...
                'sixgr:mac:PHRPeriodicTimer','Explicit positive periodic slots or infinity required.');
            obj.PeriodicSlots=periodicSlots;
        end
        function trigger(obj,kind,currentSlot)
            kind=lower(string(kind));
            validateattributes(currentSlot,{'numeric'},{'scalar','integer','nonnegative','finite'});
            assert(isscalar(kind) && ismember(kind,["periodic","pathlosschange", ...
                "powerbackoffchange","activation","configuration"]), ...
                'sixgr:mac:InvalidPHRTrigger','Unknown PHR trigger.');
            if ~ismember(kind,["pathlosschange","powerbackoffchange"]) || currentSlot>=obj.ProhibitUntilSlot
                obj.PendingTrigger=kind;
                obj.TriggerGeneration=obj.TriggerGeneration+1;
            end
        end
        function advanceTo(obj,slot)
            validateattributes(slot,{'numeric'},{'scalar','finite','integer','>=',obj.CurrentSlot});
            obj.CurrentSlot=slot;
            if slot>=obj.PeriodicDueSlot
                obj.PeriodicDueSlot=Inf;
                obj.trigger("periodic",slot);
            end
        end
        function receivedNewDataGrant(obj,slot)
            obj.advanceTo(slot);
            if ~obj.PeriodicStarted
                obj.PeriodicStarted=true; obj.PeriodicDueSlot=slot+obj.PeriodicSlots;
            end
        end
        function report=buildReport(obj,entries,currentSlot,prohibitSlots)
            % Compatibility entry point now previews; callers MUST commit TX.
            validateattributes(currentSlot,{'numeric'},{'scalar','integer','nonnegative','finite'});
            validateattributes(prohibitSlots,{'numeric'},{'scalar','integer','nonnegative','finite'});
            if obj.PendingTrigger=="none"
                report=struct('Transmit',false); return;
            end
            assert(isstruct(entries) && ~isempty(entries),'sixgr:mac:MissingPHREntry','Original PH entries required.');
            n=numel(entries); ph=zeros(n,1); pcmax=zeros(n,1);
            for ii=1:n
                ph(ii)=sixgr.l2.mac.PHRMappingR18.phIndex(entries(ii).PH_dB);
                pcmax(ii)=sixgr.l2.mac.PHRMappingR18.pcmaxIndex(entries(ii).PCMAX_dBm);
            end
            report=struct('Transmit',true,'PHIndex',ph,'PCMAXIndex',pcmax, ...
                'MultipleEntry',n>1,'Trigger',obj.PendingTrigger,'UEID',obj.UEID, ...
                'TriggerGeneration',obj.TriggerGeneration,'PreparedSlot',currentSlot, ...
                'ProhibitSlots',prohibitSlots,'PeriodicSlots',obj.PeriodicSlots);
            report.ReportSHA256=sixgr.l2.mac.MACHash.of(report);
        end
        function duplicate=validateTransmission(obj,report,tx)
            duplicate=false;
            % tx must be projected by actual TX commit, not by planning code.
            % Retry uses original TB bytes and MUST NOT call this method.
            assert(isstruct(tx)&&isscalar(tx)&&isequal(tx.Executed,true)&& ...
                isequal(tx.IsNewData,true)&&tx.UEID==obj.UEID, ...
                'sixgr:mac:PHRTXAuthority','Actual original new-data TX required.');
            validateattributes(tx.Slot,{'numeric'},{'scalar','integer','nonnegative','finite'});
            id=string(tx.TransmissionID);
            assert(isscalar(id)&&~ismissing(id)&&strlength(id)>0, ...
                'sixgr:mac:PHRTXAuthority','Original transmission identity required.');
            h=string(report.ReportSHA256); unsigned=rmfield(report,'ReportSHA256');
            assert(report.Transmit && report.UEID==obj.UEID && ...
                h==sixgr.l2.mac.MACHash.of(unsigned) && string(tx.PHRReportSHA256)==h && ...
                tx.Slot>=report.PreparedSlot && report.TriggerGeneration<=obj.TriggerGeneration, ...
                'sixgr:mac:PHRPreparedBinding','Committed TX must bind its original prepared report.');
            prior=find(obj.CommittedTransmissionIDs==id);
            if ~isempty(prior)
                assert(isscalar(prior)&&obj.CommittedReportHashes(prior)==h, ...
                    'sixgr:mac:PHRCommitConflict','A TX identity cannot change report.');
                duplicate=true; return;
            end
            assert(report.TriggerGeneration>obj.LastCommittedGeneration, ...
                'sixgr:mac:PHRAlreadyCommitted','One trigger cannot create two new-data reports.');
        end
        function recordTransmission(obj,report,tx)
            if obj.validateTransmission(report,tx), return; end
            id=string(tx.TransmissionID); h=string(report.ReportSHA256);
            obj.CommittedTransmissionIDs(end+1,1)=id;
            obj.CommittedReportHashes(end+1,1)=h;
            obj.LastCommittedGeneration=report.TriggerGeneration;
            obj.ProhibitUntilSlot=tx.Slot+report.ProhibitSlots;
            obj.PeriodicDueSlot=tx.Slot+obj.PeriodicSlots; obj.PeriodicStarted=true;
            % A newer trigger created after preparation remains pending.
            if report.TriggerGeneration==obj.TriggerGeneration, obj.PendingTrigger="none"; end
        end
    end
end
