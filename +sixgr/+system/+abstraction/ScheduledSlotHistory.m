classdef ScheduledSlotHistory < handle
    % Bounded immutable scheduled population, including explicitly idle slots.
    % Stores modeled execution inputs, never fabricated waveform outcomes.
    properties (SetAccess=private)
        LookbackSlots (1,1) double
        LookaheadSlots (1,1) double
        CommittedSlotCount (1,1) double = 0
        ExplicitIdleSlotCount (1,1) double = 0
        CommittedThroughTTI (1,1) double = 0
    end
    properties (Access=private)
        Records cell = {}
    end
    methods
        function obj=ScheduledSlotHistory(lookback,lookahead)
            if nargin<2, lookahead=0; end
            validateattributes(lookback,{'double'},{'scalar','integer','nonnegative','finite'});
            validateattributes(lookahead,{'double'},{'scalar','integer','nonnegative','finite'});
            obj.LookbackSlots=lookback;
            obj.LookaheadSlots=lookahead;
        end
        function append(obj,state)
            assert(isstruct(state) && isscalar(state) && ...
                all(isfield(state,{'TTI','GrantsDL','GrantsUL','GrantCellsDL','GrantCellsUL','LargeScaleState'})), ...
                'sixgr:abstraction:SlotHistoryPopulation','Retain a complete scheduled population and its propagation state.');
            validateattributes(state.TTI,{'numeric'},{'scalar','integer','positive','finite'});
            % Validate the second clock before retaining any population.
            % Reference producers consume AbsoluteSlot0 while finite receive
            % windows use TTI-1. A disagreement must not poison history and
            % then fail only when feedback happens to be enabled.
            if isfield(state,'AbsoluteSlot0')
                slot=state.AbsoluteSlot0;
                assert(isnumeric(slot) && isreal(slot) && isscalar(slot) && ...
                    isfinite(slot) && slot==state.TTI-1, ...
                    'sixgr:abstraction:SlotHistoryClock', ...
                    'AbsoluteSlot0 must equal TTI-1 for the committed physical slot.');
            end
            assert(isstruct(state.GrantsDL) && isstruct(state.GrantsUL) && ...
                numel(state.GrantsDL)==numel(state.GrantCellsDL) && ...
                numel(state.GrantsUL)==numel(state.GrantCellsUL), ...
                'sixgr:abstraction:SlotHistoryPopulation','Every scheduled grant requires its actual serving-cell identity.');
            for direction=["DL","UL"]
                cells=state.("GrantCells"+direction);
                assert(isnumeric(cells) && all(isfinite(cells(:))) && ...
                    all(cells(:)>0 & cells(:)==fix(cells(:))), ...
                    'sixgr:abstraction:SlotHistoryPopulation','Cell identities must be explicit positive integers.');
                grants=state.("Grants"+direction);
                for k=1:numel(grants)
                    g=grants(k);
                    % Legacy rectangular numerical fixtures have no grant
                    % clock. When the issued identity is supplied, however,
                    % never silently execute it in a different slot/direction.
                    if isfield(g,'ScheduledAbsoluteSlot')
                        slot=g.ScheduledAbsoluteSlot;
                        assert(isnumeric(slot) && isreal(slot) && isscalar(slot) && ...
                            isfinite(slot) && slot==state.TTI-1, ...
                            'sixgr:abstraction:SlotHistoryGrantClock', ...
                            'Every committed grant must belong to this transmission slot, not its earlier control slot.');
                    end
                    if isfield(g,'Direction')
                        label=string(g.Direction);
                        assert(isscalar(label) && label==direction, ...
                            'sixgr:abstraction:SlotHistoryGrantDirection', ...
                            'A committed grant direction must agree with its DL/UL population.');
                    end
                end
            end
            if ~isempty(obj.Records)
                previous=obj.Records{end};
                if state.TTI==previous.TTI
                    assert(isequaln(state,previous),'sixgr:abstraction:SlotHistoryMutation', ...
                        'A committed slot population cannot change between grant decodes.');
                    return;
                end
                assert(state.TTI==previous.TTI+1,'sixgr:abstraction:SlotHistoryClock', ...
                    'Publish every slot in order, including idle slots; missing history is not silence.');
            end
            obj.Records{end+1}=state;
            obj.CommittedThroughTTI=double(state.TTI);
            obj.CommittedSlotCount=obj.CommittedSlotCount+1;
            obj.ExplicitIdleSlotCount=obj.ExplicitIdleSlotCount+ ...
                double(isempty(state.GrantsDL) && isempty(state.GrantsUL));
            if numel(obj.Records)>obj.LookbackSlots+obj.LookaheadSlots+1, obj.Records(1)=[]; end
        end
        function [states,evidence]=window(obj,tti)
            validateattributes(tti,{'numeric'},{'scalar','integer','positive','finite'});
            assert(~isempty(obj.Records) && obj.Records{end}.TTI==tti, ...
                'sixgr:abstraction:SlotHistoryClock','The requested current slot must already be committed.');
            [states,evidence]=obj.receiveWindow(tti,0);
        end
        function state=scheduledState(obj,tti)
            validateattributes(tti,{'numeric'},{'scalar','integer','positive','finite'});
            match=find(cellfun(@(s)s.TTI==tti,obj.Records));
            assert(isscalar(match),'sixgr:abstraction:IncompleteSlotHistory', ...
                'The actual scheduled slot is missing or expired; current state cannot replace it.');
            state=obj.Records{match};
        end
        function [states,evidence]=receiveWindow(obj,tti,lookahead)
            % A receive window may finish AFTER its target transmission.
            % Future schedules/zero padding are not committed observations.
            validateattributes(tti,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(lookahead,{'numeric'},{'scalar','integer','nonnegative','finite'});
            assert(lookahead<=obj.LookaheadSlots, ...
                'sixgr:abstraction:ReceiveWindowRetention','The requested receive-window support exceeds retained lookahead capacity.');
            assert(~isempty(obj.Records) && obj.Records{end}.TTI>=tti+lookahead, ...
                'sixgr:abstraction:ReceiveWindowNotAvailable', ...
                'The receive window is unavailable until every required following slot has been committed.');
            expected=max(1,tti-obj.LookbackSlots):tti+lookahead;
            retained=cellfun(@(s)double(s.TTI),obj.Records);
            selected=retained>=expected(1) & retained<=expected(end);
            actual=retained(selected);
            assert(isequal(actual,expected),'sixgr:abstraction:IncompleteSlotHistory', ...
                'A missing or expired slot cannot be replaced by zero interference.');
            states=obj.Records(selected);
            idle=cellfun(@(s)isempty(s.GrantsDL) && isempty(s.GrantsUL),states);
            evidence=struct('Source',"committed_scheduled_shared_data_populations", ...
                'TTIs',actual,'AbsoluteSlots0',actual-1,'ExplicitIdleTTIs',actual(idle), ...
                'InitialSimulationBoundaryIncluded',expected(1)==1, ...
                'ObservationTTI',double(tti),'RequiredCommittedThroughTTI',double(tti+lookahead), ...
                'ReadAtCommittedTTI',double(obj.Records{end}.TTI), ...
                'RequiredFollowingSlots',double(lookahead), ...
                'CommittedSlotCount',obj.CommittedSlotCount, ...
                'ExplicitIdleSlotCount',obj.ExplicitIdleSlotCount, ...
                'HistoryComplete',true,'WaveformMeasured',false, ...
                'ControlRSInterferenceIncluded',false);
        end
    end
end
