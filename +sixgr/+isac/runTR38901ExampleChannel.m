function [received,metadata] = runTR38901ExampleChannel(cfg,waveform,context)
%RUNTR38901EXAMPLECHANNEL Adapter for the R2026a example-local ISAC channel.
%
% The helper class is supplied by the MathWorks example rather than the 5G
% Toolbox public path. A selected unavailable helper fails closed and is never
% replaced by the deterministic campaign channel.

arguments
    cfg (1,1) struct
    waveform double
    context (1,1) struct
end
helper=sixgr.isac.resolveTR38901ExampleHelper(cfg);
className=helper.ClassName;
channel=feval(className);
cleanup=onCleanup(@() release(channel)); %#ok<NASGU>
channel.SensingMode=localSensingMode(string(context.SensingMode));
channel.SensingScenario=char(string(cfg.channel.tr38901Backend.sensingScenario));
channel.CommunicationScenario=char(string(cfg.channel.tr38901Backend.communicationScenario));
channel.CenterFrequency=double(context.CarrierFrequencyHz);
channel.SampleRate=double(context.SampleRateHz);
channel.Seed=double(context.Seed);
channel.LOSProbability=double(cfg.channel.tr38901Backend.losProbability);
channel.BackgroundChannel=logical(cfg.channel.tr38901Backend.backgroundChannel);
channel.TargetChannel=logical(cfg.channel.tr38901Backend.targetChannel);
channel.ChannelFiltering=true;
channel.STX.Position=double(context.TxPositionM(:));
channel.STX.NumTransmitAntennas=size(waveform,2);
channel.STX.TransmitArrayOrientation=double(context.TxOrientationDeg(:));
channel.SRX.Position=double(context.RxPositionM(:));
channel.SRX.NumReceiveAntennas=double(context.NumReceiveAntennas);
channel.SRX.ReceiveArrayOrientation=double(context.RxOrientationDeg(:));
targets=context.Targets;
channel.STs=repmat(channel.STs,1,numel(targets));
for i=1:numel(targets)
    channel.STs(i).Position=double(targets(i).PositionM(:));
    channel.STs(i).Velocity=double(targets(i).VelocityMps(:));
    channel.STs(i).Orientation=double(targets(i).OrientationDeg(:));
end
[received,pathGains,sampleTimes]=channel(waveform);
channelInfo=info(channel);
metadata=struct("Backend","h38901ISACChannel", ...
    "SensingMode",string(context.SensingMode),"ChannelInfo",channelInfo, ...
    "PathGains",pathGains,"SampleTimes",sampleTimes, ...
    "ReceivedSHA256",string(localHash(received)), ...
    "HelperPath",helper.HelperPath,"HelperSHA256",helper.HelperSHA256, ...
    "ExampleId",helper.ExampleId,"EvidenceClass",helper.EvidenceClass);
end

function value=localSensingMode(value)
switch lower(strtrim(value))
    case {"trp_monostatic","trp monostatic"}
        value="TRP Monostatic";
    case {"ue_monostatic","ue monostatic"}
        value="UE Monostatic";
    case {"trp_ue_bistatic","trp-ue bistatic"}
        value="TRP-UE Bistatic";
    case {"ue_trp_bistatic","ue-trp bistatic"}
        value="UE-TRP Bistatic";
    case {"trp_trp_bistatic","trp-trp bistatic"}
        value="TRP-TRP Bistatic";
    case {"ue_ue_bistatic","ue-ue bistatic"}
        value="UE-UE Bistatic";
    otherwise
        error("sixgr:isac:UnsupportedTR38901SensingMode", ...
            "Unsupported TR 38.901 sensing mode %s.",value);
end
end

function digest=localHash(value)
digest=sixgr.util.sha256Hex(typecast([real(value(:));imag(value(:))],"uint8"));
end
