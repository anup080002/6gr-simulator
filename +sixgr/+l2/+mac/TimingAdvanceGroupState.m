classdef TimingAdvanceGroupState < handle
    %TIMINGADVANCEGROUPSTATE TA command and timeAlignmentTimer authority.
    properties (SetAccess=private)
        TAGID (1,1) double
        NTA (1,1) double = 0
        TimerExpirySlot (1,1) double = -Inf
        ULAllowed (1,1) logical = false
    end
    methods
        function obj=TimingAdvanceGroupState(tagID)
            obj.TAGID=double(tagID);
        end
        function delta=applyCommand(obj,mu,command,currentSlot,timerSlots)
            validateattributes(command,{'numeric'},{'scalar','integer','>=',0,'<=',63});
            delta=(double(command)-31)*1024/(2^double(mu));
            obj.NTA=max(0,obj.NTA+delta);
            obj.TimerExpirySlot=currentSlot+timerSlots; obj.ULAllowed=true;
        end
        function tick(obj,currentSlot)
            if currentSlot>=obj.TimerExpirySlot
                obj.NTA=0; obj.ULAllowed=false;
            end
        end
        function applyAbsolute(obj,nta,currentSlot,timerSlots)
            validateattributes(nta,{'numeric'},{'scalar','nonnegative'});
            obj.NTA=nta; obj.TimerExpirySlot=currentSlot+timerSlots;
            obj.ULAllowed=true;
        end
    end
    methods (Static)
        function [delta,nta]=resolveCommand(mu,currentNTA,command)
            validateattributes(mu,{'numeric'},{'scalar','integer','nonnegative'});
            validateattributes(currentNTA,{'numeric'},{'scalar','nonnegative'});
            validateattributes(command,{'numeric'},{'scalar','integer','>=',0,'<=',63});
            delta=(double(command)-31)*1024/(2^double(mu));
            nta=max(0,double(currentNTA)+delta);
        end
    end
end
