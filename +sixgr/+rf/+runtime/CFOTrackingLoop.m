classdef CFOTrackingLoop < handle
%CFOTRACKINGLOOP Stateful first-order residual-CFO tracking loop.

    properties(SetAccess=private)
        LoopGain (1,1) double
        Estimate_Hz (1,1) double = 0
        PhaseError_rad (1,1) double = 0
        Step (1,1) double = 0
        StateEpoch (1,1) double
    end

    methods
        function obj=CFOTrackingLoop(loopGain,initialEstimateHz,stateEpoch)
            arguments
                loopGain (1,1) double {mustBeFinite,mustBePositive}
                initialEstimateHz (1,1) double {mustBeFinite}=0
                stateEpoch (1,1) double {mustBeFinite}=1
            end
            if loopGain>1
                error("RF:UnsupportedCombination", ...
                    "CFO tracking-loop gain must be in (0,1].");
            end
            obj.LoopGain=loopGain;
            obj.Estimate_Hz=initialEstimateHz;
            obj.StateEpoch=stateEpoch;
        end

        function trace=update(obj,measurementHz,timeStep_s,expectedEpoch)
            if nargin>=4 && expectedEpoch~=obj.StateEpoch
                error("RF:StateEpochMismatch", ...
                    "CFO tracking state epoch mismatch.");
            end
            if ~(isscalar(measurementHz)&&isfinite(measurementHz)&& ...
                    isscalar(timeStep_s)&&isfinite(timeStep_s)&&timeStep_s>0)
                error("RF:CFOAcquisitionFailed", ...
                    "CFO tracking requires a finite measurement and time step.");
            end
            residual=measurementHz-obj.Estimate_Hz;
            obj.Estimate_Hz=obj.Estimate_Hz+obj.LoopGain*residual;
            obj.PhaseError_rad=2*pi*(measurementHz-obj.Estimate_Hz)*timeStep_s;
            obj.Step=obj.Step+1;
            trace=struct("Step",obj.Step,"EstimatedCFO_Hz",obj.Estimate_Hz, ...
                "ResidualCFO_Hz",measurementHz-obj.Estimate_Hz, ...
                "PhaseError_rad",obj.PhaseError_rad, ...
                "CorrectionApplied",true,"StateEpoch",obj.StateEpoch);
        end
    end
end
