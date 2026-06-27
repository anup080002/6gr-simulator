function verdict = validateChannelRFConfigStrict(cfg)
%VALIDATECHANNELRFCONFIGSTRICT Fail-closed validation for strict Channel/RF runs.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end

verdict = struct();
verdict.Ok = true;
verdict.Failures = strings(0, 1);
verdict.StrictUnsupportedReason = "";

channelModel = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", ""))));
if strlength(channelModel) == 0
    channelModel = upper(strtrim(string(sixgr.util.structGet(cfg, "lls6g.resolvedConfig.channels.model_type", ""))));
end
delayProfile = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.delayProfile", ...
    sixgr.util.structGet(cfg, "lls6g.resolvedConfig.channels.profile", "")))));
if strlength(channelModel) == 0
    verdict = localFail(verdict, "channel_model_missing");
elseif ~any(channelModel == ["AWGN", "TDL", "CDL"])
    verdict = localFail(verdict, "unsupported_channel_model:" + channelModel);
end

if channelModel == "TDL"
    if ~(startsWith(delayProfile, "TDL-") && strlength(delayProfile) > 4)
        verdict = localFail(verdict, "tdl_requires_concrete_profile");
    end
    if exist("nrTDLChannel", "class") ~= 8 && exist("nrTDLChannel", "file") ~= 2
        verdict = localFail(verdict, "nrtdlchannel_unavailable");
    end
elseif channelModel == "CDL"
    if ~(startsWith(delayProfile, "CDL-") && strlength(delayProfile) > 4)
        verdict = localFail(verdict, "cdl_requires_concrete_profile");
    end
    if exist("nrCDLChannel", "class") ~= 8 && exist("nrCDLChannel", "file") ~= 2
        verdict = localFail(verdict, "nrcdlchannel_unavailable");
    end
elseif channelModel == "AWGN"
    if strlength(delayProfile) > 0 && delayProfile ~= "AWGN"
        verdict = localFail(verdict, "awgn_cannot_claim_fading_profile");
    end
end

fcHz = double(sixgr.util.structGet(cfg, "channel.fc_Hz", sixgr.util.structGet(cfg, "phy.fc_Hz", NaN)));
bwHz = double(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", NaN));
sampleRateHz = double(sixgr.util.structGet(cfg, "channel_rf.sampleRateHz", ...
    sixgr.util.structGet(cfg, "phy.sampleRate_Hz", NaN)));
if ~(isfinite(fcHz) && fcHz > 0)
    verdict = localFail(verdict, "carrier_frequency_missing");
end
if ~(isfinite(bwHz) && bwHz > 0)
    verdict = localFail(verdict, "bandwidth_missing");
end
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    nrb = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 24));
    scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", 30));
    sampleRateHz = max(1, nrb * 12 * scs * 1e3);
end
verdict.SampleRateHz = double(sampleRateHz);

pathlossEnabled = logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", false));
pathlossModel = lower(strtrim(string(sixgr.util.structGet(cfg, "channel.pathlossModel", ...
    sixgr.util.structGet(cfg, "channel.pathloss.model", "none")))));
if pathlossEnabled && ~any(pathlossModel == ["nrpathloss", "nr", "none"])
    verdict = localFail(verdict, "unsupported_pathloss_model:" + pathlossModel);
end

o2iConfigured = logical(sixgr.util.structGet(cfg, "channel.o2i.enabled", false)) || ...
    any(lower(strtrim(string(sixgr.util.structGet(cfg, "channel.o2i.model", "none")))) == ["low", "high"]);
if o2iConfigured && ~pathlossEnabled
    verdict = localFail(verdict, "o2i_requires_pathloss_application");
end

rfEnabled = logical(sixgr.util.structGet(cfg, "rf.enable", false)) || ...
    abs(double(sixgr.util.structGet(cfg, "phy.impairments.cfoHz", 0))) > 0 || ...
    logical(sixgr.util.structGet(cfg, "rf.phaseNoise.enable", ...
    sixgr.util.structGet(cfg, "phy.impairments.phaseNoiseEnabled", false))) || ...
    logical(sixgr.util.structGet(cfg, "phy.impairments.iqImbalanceEnabled", false)) || ...
    logical(sixgr.util.structGet(cfg, "phy.impairments.paNonlinearityEnabled", false)) || ...
    abs(double(sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", 0))) > 0 || ...
    abs(double(sixgr.util.structGet(cfg, "rf.sampleClockOffset.ppm", ...
    sixgr.util.structGet(cfg, "phy.impairments.sampleClockOffsetPpm", ...
    sixgr.util.structGet(cfg, "impairments.sample_clock_offset_ppm", 0))))) > 0;
verdict.RFConfigured = logical(rfEnabled);

sampleClockOffsetPpm = double(sixgr.util.structGet(cfg, "rf.sampleClockOffset.ppm", ...
    sixgr.util.structGet(cfg, "phy.impairments.sampleClockOffsetPpm", ...
    sixgr.util.structGet(cfg, "impairments.sample_clock_offset_ppm", 0))));
sampleClockOffsetEnabled = logical(sixgr.util.structGet(cfg, "rf.sampleClockOffset.enable", ...
    sixgr.util.structGet(cfg, "phy.impairments.sampleClockOffsetEnabled", abs(sampleClockOffsetPpm) > 0)));
verdict.SampleClockOffsetConfigured = logical(sampleClockOffsetEnabled && abs(sampleClockOffsetPpm) > 0);
verdict.SampleClockOffsetSupported = true;
verdict.SampleClockOffsetExecutionBackend = "sixgr.rf.applyRFImpairmentChain.localApplySampleClockOffset";

if ~verdict.Ok
    verdict.StrictUnsupportedReason = strjoin(verdict.Failures, ";");
end
end

function verdict = localFail(verdict, reason)
verdict.Ok = false;
verdict.Failures(end+1, 1) = string(reason);
end
