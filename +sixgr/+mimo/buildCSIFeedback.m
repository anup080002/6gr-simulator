function csi = buildCSIFeedback(H, noiseVar, cfg, varargin)
%BUILDCSIFEEDBACK Build runtime CQI/PMI/RI feedback from measured channel H.

ip = inputParser;
ip.addParameter("Direction", "DL", @(x) ischar(x) || isstring(x));
ip.addParameter("NominalRank", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});

if nargin < 3 || ~isstruct(cfg)
    cfg = struct();
end
nominalRank = ip.Results.NominalRank;
if isempty(nominalRank)
    nominalRank = sixgr.util.structGet(cfg, "MaxRank", ...
        sixgr.util.structGet(cfg, "mimo.maxRank", ...
        sixgr.util.structGet(cfg, "phy.pdsch.numLayers", 1)));
end
decision = sixgr.mimo.resolveNominalVsEffectiveMIMO([], [], H, noiseVar, nominalRank, cfg);
widebandSINR = max([decision.SNR_layer1_dB, decision.SNR_layer2_dB], [], "omitnan");
if ~(isfinite(widebandSINR))
    widebandSINR = double(sixgr.util.structGet(cfg, "SNR_configured_dB", NaN));
end

cqi = localCQIFromSINR(widebandSINR, cfg, ip.Results.Direction);
csi = struct();
csi.Direction = upper(string(ip.Results.Direction));
csi.RI = double(decision.EffectiveRank);
csi.PMI = double(decision.PMI_i1(1));
csi.PMI_i1 = decision.PMI_i1;
csi.PMI_i2 = decision.PMI_i2;
csi.CQI = double(cqi);
csi.WidebandSINR_dB = double(widebandSINR);
csi.Precoder_W = decision.Precoder_W;
csi.RankDecisionReason = string(decision.RankDecisionReason);
csi.ConditionNumber_dB = double(decision.ConditionNumber_dB);
csi.SingularValues = decision.SingularValues;
csi.RuntimeEvidenceSource = "svd_of_measured_channel_matrix";
csi.ChannelStateInformationMode = "PMI+CQI+RI";
csi.CSIPayloadBitLength = 4 + 4 + 2;
csi.CSIPayloadHex = localPayloadHex(csi.RI, csi.PMI, csi.CQI);
end

function cqi = localCQIFromSINR(sinr_dB, cfg, direction)
cqi = NaN;
try
    feedback = sixgr.link.resolveWidebandCQI(struct( ...
        "WidebandSINR_dB", double(sinr_dB), ...
        "SINRSource", "svd_measured_mimo_channel", ...
        "SINRValueRole", "runtime_csi_feedback_input", ...
        "SINRValueStatus", "OK"), cfg, upper(string(direction)));
    cqi = double(sixgr.util.structGet(feedback, "WidebandCQI", NaN));
catch
end
if ~(isfinite(cqi))
    cqi = max(0, min(15, round((double(sinr_dB) + 6) / 2)));
end
end

function hex = localPayloadHex(ri, pmi, cqi)
ri = max(0, min(3, round(double(ri))));
pmi = max(0, min(15, round(double(pmi))));
cqi = max(0, min(15, round(double(cqi))));
val = bitor(bitshift(uint16(ri), 8), bitor(bitshift(uint16(pmi), 4), uint16(cqi)));
hex = upper(string(dec2hex(val, 3)));
end
