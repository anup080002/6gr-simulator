classdef ExecutionStageProfiler < handle
    % Wall-clock diagnostics only; no samples, RNG or receiver decisions.
    % Synchronous nested spans: exclusive time subtracts child spans.
    % ScopeExitCount is NOT successful decode/qualification evidence.
    properties (Access=private)
        Path
        Session
        Slot = 0
        Sweep = 0
        Serial = 0
        Stack = struct('ID',{},'Stage',{},'Operation',{},'Slot',{},'Sweep',{},'Timer',{},'Children',{})
        Rows = struct('Slot',{},'Sweep',{},'Stage',{},'Operation',{},'ScopeExitCount',{},'InclusiveSeconds',{},'ExclusiveSeconds',{})
    end
    methods (Static)
        function cleanup=start(root,enabled)
            validateattributes(enabled,{'logical'},{'scalar'});
            assert(isempty(sixgr.runtime.ExecutionStageProfiler.active()), ...
                'sixgr:profile:SessionActive','Close the prior diagnostic session first.');
            cleanup=[];
            if ~enabled || ~sixgr.util.persistenceEnabled(), return; end
            obj=sixgr.runtime.ExecutionStageProfiler();
            obj.Path=fullfile(root,'reports','csv','execution_stage_profile.csv');
            folder=fileparts(obj.Path);
            if ~isfolder(folder), mkdir(folder); end
            % UUID is independent of MATLAB's scientific RNG stream.
            obj.Session=string(char(java.util.UUID.randomUUID()));
            sixgr.runtime.ExecutionStageProfiler.active(obj);
            cleanup=onCleanup(@()sixgr.runtime.ExecutionStageProfiler.stop(obj));
        end

        function cleanup=scope(stage,operation)
            obj=sixgr.runtime.ExecutionStageProfiler.active();
            cleanup=[];
            if isempty(obj), return; end
            obj.Serial=obj.Serial+1; id=obj.Serial;
            obj.Stack(end+1)=struct('ID',id,'Stage',string(stage), ...
                'Operation',string(operation),'Slot',obj.Slot,'Sweep',obj.Sweep, ...
                'Timer',tic,'Children',0);
            cleanup=onCleanup(@()obj.closeSpan(id));
        end

        function setSlot(slot,sweep)
            obj=sixgr.runtime.ExecutionStageProfiler.active();
            if isempty(obj), return; end
            validateattributes(slot,{'numeric'},{'scalar','integer','nonnegative','finite'});
            validateattributes(sweep,{'numeric'},{'scalar','integer','nonnegative','finite'});
            assert(isempty(obj.Stack),'sixgr:profile:ActiveSpanAtSlotBoundary', ...
                'Close measured scopes before changing their slot identity.');
            obj.flushRows();
            obj.Slot=double(slot); obj.Sweep=double(sweep);
        end

        function flush()
            obj=sixgr.runtime.ExecutionStageProfiler.active();
            if ~isempty(obj), obj.flushRows(); end
        end
    end
    methods (Access=private)
        function closeSpan(obj,id)
            assert(~isempty(obj.Stack) && obj.Stack(end).ID==id, ...
                'sixgr:profile:NonNestedScope','Profile spans must close in execution order.');
            span=obj.Stack(end);
            elapsed=toc(span.Timer);
            obj.Stack(end)=[];
            if ~isempty(obj.Stack)
                obj.Stack(end).Children=obj.Stack(end).Children+elapsed;
            end
            exclusive=max(0,elapsed-span.Children);
            k=find([obj.Rows.Slot]==span.Slot & [obj.Rows.Sweep]==span.Sweep & ...
                string({obj.Rows.Stage})==span.Stage & string({obj.Rows.Operation})==span.Operation,1);
            if isempty(k)
                obj.Rows(end+1)=struct('Slot',span.Slot,'Sweep',span.Sweep, ...
                    'Stage',span.Stage,'Operation',span.Operation,'ScopeExitCount',1, ...
                    'InclusiveSeconds',elapsed,'ExclusiveSeconds',exclusive);
            else
                obj.Rows(k).ScopeExitCount=obj.Rows(k).ScopeExitCount+1;
                obj.Rows(k).InclusiveSeconds=obj.Rows(k).InclusiveSeconds+elapsed;
                obj.Rows(k).ExclusiveSeconds=obj.Rows(k).ExclusiveSeconds+exclusive;
            end
        end

        function flushRows(obj)
            if isempty(obj.Rows), return; end
            fresh=~isfile(obj.Path) || dir(obj.Path).bytes==0;
            fid=fopen(obj.Path,'a','n','UTF-8');
            assert(fid>=0,'sixgr:profile:WriteFailed','Cannot append stage profile: %s',obj.Path);
            closeFile=onCleanup(@()fclose(fid)); %#ok<NASGU>
            if fresh
                fprintf(fid,'SessionID,SlotOneBased,SweepPointIndex,Stage,Operation,ScopeExitCount,InclusiveSeconds,ExclusiveSeconds,EvidenceScope\n');
            end
            for r=obj.Rows
                fprintf(fid,'"%s",%d,%d,"%s","%s",%d,%.17g,%.17g,"wall_clock_scope_exit_not_PHY_acceptance"\n', ...
                    obj.Session,r.Slot,r.Sweep,replace(r.Stage,'"','""'), ...
                    replace(r.Operation,'"','""'),r.ScopeExitCount,r.InclusiveSeconds,r.ExclusiveSeconds);
            end
            [message,code]=ferror(fid);
            assert(code==0,'sixgr:profile:WriteFailed','Stage profile write failed: %s',message);
            obj.Rows=obj.Rows([]);
        end
    end
    methods (Static,Access=private)
        function obj=active(varargin)
            persistent current
            if nargin>0, current=varargin{1}; end
            obj=current;
        end
        function stop(obj)
            obj.flushRows();
            sixgr.runtime.ExecutionStageProfiler.active([]);
        end
    end
end
