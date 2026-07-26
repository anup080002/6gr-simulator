function [ue, model] = updatePositions(ue, cfg, dt_s, model)
%SIXGR.SCENARIO.MOBILITY.UPDATEPOSITIONS Update UE positions for one time step.
%
%   [ue, model] = sixgr.scenario.mobility.updatePositions(ue, cfg, dt_s)
%   [ue, model] = ... updatePositions(ue, cfg, dt_s, model)
%
% Inputs:
%   ue    : UE struct from sixgr.scenario.dropUEs()
%   cfg   : simulator config struct
%   dt_s  : time step in seconds
%   model : optional mobility model object (handle)
%
% Outputs:
%   ue    : updated UE struct
%   model : mobility model object (cache and reuse each TTI/slot)
%
% Model selection:
%   cfg.scenario.mobility.model = "randomWaypoint" | "straightLine" | "zigzag" | "trace"
%
% Notes:
% - This wrapper exists so higher layers do not directly construct classes.
% - If model is empty, this function constructs and resets the model.
%
% See also: sixgr.scenario.mobility.MobilityRandomWaypoint

arguments
    ue struct
    cfg struct
    dt_s (1,1) double {mustBeNonnegative} = 0
    model = []
end

if dt_s == 0
    return;
end

if isempty(model)
    % Let ScenarioFactory pick the active profile (supports both profile-based
% and flat cfg.scenario.* configs).
prof = sixgr.scenario.ScenarioFactory.getProfile(cfg);
    modelName = char(string(sixgr.util.structGet(cfg, "scenario.mobility.model", "randomWaypoint")));
    mobilitySeed = double(sixgr.util.structGet(cfg, "scenario.mobility.seed", ...
        sixgr.util.structGet(cfg, "run.seed", 0)));
    wrapEn = logical(sixgr.util.structGet(cfg, "scenario.wraparoundEnabled", prof.wraparoundEnabled));
    area_m = double(prof.area_m);

    switch lower(modelName)
        case {"randomwaypoint","rwp"}
            model = sixgr.scenario.mobility.MobilityRandomWaypoint(area_m, wrapEn, ...
                "Seed", mobilitySeed);
        case {"zigzag","zig_zag","zigzagline","zig_zag_line"}
            segDur_s = double(sixgr.util.structGet(cfg, "scenario.mobility.zigzagSegmentDuration_s", ...
                sixgr.util.structGet(cfg, "scenario.mobility.segmentDuration_s", 0.75)));
            turnAngle_deg = double(sixgr.util.structGet(cfg, "scenario.mobility.zigzagTurnAngle_deg", ...
                sixgr.util.structGet(cfg, "scenario.mobility.turnAngle_deg", 35)));
            model = sixgr.scenario.mobility.MobilityZigZag(area_m, wrapEn, ...
                "SegmentDuration_s", segDur_s, "TurnAngle_deg", turnAngle_deg);
        case {"trace","trajectory_trace"}
            model = sixgr.scenario.mobility.MobilityTrace(area_m, wrapEn, ...
                sixgr.util.structGet(cfg, "scenario.mobility.userPaths", struct([])));
        case {"rmamixedspeed","rma","mixed","straightline","straight_line","straight","line"}
            model = sixgr.scenario.mobility.MobilityRMaMixedSpeed(area_m, wrapEn);
        otherwise
            error("CHANNEL:UnsupportedMobilityProfile", ...
                "Unsupported mobility profile '%s'.", modelName);
    end

    ue = model.reset(ue);
end

ue = model.step(ue, dt_s);

end
