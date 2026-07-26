function [beamIdx, beamGain_dB, evidence] = selectBestBeamPerLink(uePos, bsPos, bsAzim_deg, nBeams, spanDeg, maxGain_dB, varargin)
% sixgr.system.selectBestBeamPerLink
% Select a beam from receiver measurements in strict mode.
%
% Geometry is retained as a compatibility channel/pattern helper for legacy
% system studies. It is not an admissible decision oracle for a strict
% waveform profile. Strict callers must provide a K-by-B-by-Nbeam measured
% RSRP/SINR tensor through the Measurements option.

ip = inputParser;
ip.addParameter("Measurements", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("MeasurementResourceIDs", [], @(x) isempty(x) || isnumeric(x) || isstring(x) || iscellstr(x));
ip.addParameter("Strict", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("Metric", "RSRP_dBm", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
opt = ip.Results;

K = size(uePos, 1);
B = size(bsPos, 1);
beamIdx = ones(K, B);
beamGain_dB = zeros(K, B);

nBeams = max(1, round(double(nBeams)));
spanDeg = max(30, min(240, double(spanDeg)));
maxGain_dB = double(maxGain_dB);

if ~isempty(opt.Measurements)
    measured = double(opt.Measurements);
    if ismatrix(measured) && B == 1 && isequal(size(measured),[K nBeams])
        measured = reshape(measured,[K 1 nBeams]);
    end
    if ~isequal(size(measured),[K B nBeams])
        error("sixgr:mimo:BeamReportMismatch", ...
            "Measured beam tensor must be K-by-B-by-Nbeam (%d-by-%d-by-%d).", ...
            K,B,nBeams);
    end
    if any(~isfinite(measured(:)))
        error("sixgr:mimo:MissingMeasurementState", ...
            "Strict beam decisions require finite receiver measurements.");
    end
    [beamGain_dB,beamIdx] = max(measured,[],3);
    resourceIDs = opt.MeasurementResourceIDs;
    if isempty(resourceIDs)
        resourceIDs = string(0:nBeams-1);
    end
    if numel(resourceIDs) ~= nBeams
        error("sixgr:mimo:BeamReportMismatch", ...
            "MeasurementResourceIDs must identify every measured beam.");
    end
    evidence = struct( ...
        "SelectionSource","measured_reference_signal", ...
        "MeasurementMetric",string(opt.Metric), ...
        "MeasurementResourceIDs",string(resourceIDs(:)), ...
        "GeometryOracleUsed",false, ...
        "Strict",logical(opt.Strict));
    return;
end

if logical(opt.Strict)
    error("sixgr:mimo:BeamMeasurementOracleForbidden", ...
        "Strict beam selection requires measured SSB/CSI-RS/SRS results; geometry cannot select the winner.");
end

if nBeams == 1
    beamOffsets = 0;
else
    beamOffsets = linspace(-0.5 * spanDeg, 0.5 * spanDeg, nBeams);
end
beamBW = max(spanDeg / max(nBeams, 1), 5);
for b = 1:B
    dx = uePos(:,1) - bsPos(b,1);
    dy = uePos(:,2) - bsPos(b,2);
    linkAz = atan2d(dy, dx);
    beamCenters = double(bsAzim_deg(b)) + beamOffsets;
    delta = abs(localWrapTo180(linkAz - reshape(beamCenters, 1, [])));
    atten_dB = min(30, 12 .* (delta ./ beamBW).^2);
    [bestAtten, idx] = min(atten_dB, [], 2);
    beamIdx(:, b) = idx;
    beamGain_dB(:, b) = maxGain_dB - bestAtten;
end
evidence = struct( ...
    "SelectionSource","legacy_geometry_pattern_study", ...
    "MeasurementMetric","configured_pattern_gain_dB", ...
    "MeasurementResourceIDs",string(0:nBeams-1).', ...
    "GeometryOracleUsed",true, ...
    "Strict",false);
end

function y = localWrapTo180(x)
y = mod(double(x) + 180, 360) - 180;
end
