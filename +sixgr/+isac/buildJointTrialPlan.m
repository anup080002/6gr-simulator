function plan = buildJointTrialPlan(cfg)
%BUILDJOINTTRIALPLAN Create the staged (not blind full-factorial) run matrix.

mode = lower(string(cfg.run.activeMode));
modeCfg = sixgr.util.structGet(cfg,"run.modes."+mode,[]);
profiles = localStrings(modeCfg.waveformProfiles);
seeds = double(modeCfg.trialSeeds(:));
delays = double(modeCfg.delayOverCP(:));
doppler = double(modeCfg.normalizedDoppler(:));
collisions = double(modeCfg.collisionRatiosPercent(:));
modes = localStrings(modeCfg.sensingModes);
coherentCounts=double(modeCfg.coherentSymbols(:));
defaultCoherent=double(cfg.waveform.defaultCoherentSymbols);
maskProfiles=localStrings(cfg.collisions.maskProfiles);

plan = repmat(localEmptyTrial(),0,1);
counter = 0;
% J1: separate delay and Doppler axes to avoid an unnecessary Cartesian
% product while preserving paired profile comparisons.
for seed = seeds.'
    for profile = profiles.'
        receivers=localReceiverProfiles(profile);
        for receiver=receivers.'
            for delay = delays.'
                counter = counter+1;
                plan(end+1,1) = localTrial(counter,"J1_delay",profile,seed,delay, ...
                    doppler(1),"trp_monostatic",0,"share_reuse",false,true,"single_port", ...
                    receiver,defaultCoherent,"random_isolated",localDefaultVariant(profile)); %#ok<AGROW>
            end
        end
        referenceDelay = delays(find(delays >= 1,1,"first"));
        if isempty(referenceDelay), referenceDelay = delays(1); end
        for normalizedDoppler = doppler(2:end).'
            counter = counter+1;
            plan(end+1,1) = localTrial(counter,"J1_doppler",profile,seed, ...
                referenceDelay,normalizedDoppler,"trp_monostatic",0, ...
                "share_reuse",false,true,"single_port",receivers(end), ...
                defaultCoherent,"random_isolated",localDefaultVariant(profile)); %#ok<AGROW>
        end
        if ismember(profile,["W0","W3"])
            for coherent=coherentCounts.'
                if coherent==defaultCoherent, continue; end
                counter=counter+1;
                plan(end+1,1)=localTrial(counter,"J1_coherent_length",profile,seed, ...
                    referenceDelay,doppler(1),"trp_monostatic",0,"share_reuse", ...
                    false,true,"single_port",receivers(end),coherent, ...
                    "random_isolated",localDefaultVariant(profile)); %#ok<AGROW>
            end
        end
    end
end

% J2/J3: selected W0/W3 collision and geometry interactions.
integrationProfiles = intersect(profiles,["W0";"W3"],"stable");
referenceDoppler = doppler(min(2,numel(doppler)));
for seed = seeds.'
    for profile = integrationProfiles.'
        for ratio = collisions.'
            response = "share_reuse";
            if ratio > 0, response = "sensing_puncture"; end
            selectedMasks=maskProfiles;
            if ratio==0, selectedMasks="random_isolated"; end
            for maskProfile=selectedMasks.'
                for sensingMode = modes.'
                    counter = counter+1;
                    plan(end+1,1) = localTrial(counter,"J2_collision",profile, ...
                        seed,1,referenceDoppler,sensingMode,ratio,response,false,true, ...
                        "eight_port_ula",localPrimaryReceiver(profile),defaultCoherent, ...
                        maskProfile,localDefaultVariant(profile)); %#ok<AGROW>
                end
            end
        end
        for sensingMode = modes.'
            counter = counter+1;
            plan(end+1,1) = localTrial(counter,"J4_geometry",profile,seed,1, ...
                referenceDoppler,sensingMode,0,"share_reuse",true,true,"eight_port_ula", ...
                localPrimaryReceiver(profile),defaultCoherent,"random_isolated", ...
                localDefaultVariant(profile)); %#ok<AGROW>
        end
    end
end

% J3: each configured collision response is executed through the shared
% waveform chain for W0 and W3.  Relocation responses therefore exercise
% explicit sequence reconstruction rather than only mask arithmetic.
j3Responses=localStrings(cfg.collisions.responses);
for profile=integrationProfiles.'
    for response=j3Responses.'
        counter=counter+1;
        portProfile="single_port";
        if response=="beam_precoder_change", portProfile="eight_port_ula"; end
        plan(end+1,1)=localTrial(counter,"J3_response",profile,seeds(1),1, ...
            referenceDoppler,"trp_monostatic",10,response,false,true,portProfile, ...
            localPrimaryReceiver(profile),defaultCoherent,"random_isolated", ...
            localDefaultVariant(profile)); %#ok<AGROW>
    end
end
% Shared-resource receiver-knowledge contrast on the identical W0 waveform.
for knowledge=["known_cancelled","decoded_reconstructed","residual_data_interference"]
    counter=counter+1;
    trial=localTrial(counter,"J3_receiver_knowledge","W0",seeds(1),1, ...
        referenceDoppler,"trp_monostatic",0,"share_reuse",false,true,"single_port", ...
        "B1",defaultCoherent,"random_isolated","default");
    trial.SharedResourceKnowledge=char(knowledge);
    plan(end+1,1)=trial; %#ok<AGROW>
end

% W1 randomization subcases execute with equal resources and the same seed.
for variant=localStrings(cfg.waveform.w1RandomizationSubcases).'
    counter=counter+1;
    plan(end+1,1)=localTrial(counter,"J3_w1_randomization","W1",seeds(1),1, ...
        referenceDoppler,"trp_monostatic",0,"share_reuse",false,true,"single_port", ...
        "B0",defaultCoherent,"random_isolated",variant); %#ok<AGROW>
end

% Empirical no-target decisions use the same W0 waveform and receiver.
noTargetTrials = double(modeCfg.noTargetTrials);
baseSeed = seeds(1);
for index = 1:noTargetTrials
    counter = counter+1;
    pfaTrial = localTrial(counter,"PFA_no_target","W0", ...
        baseSeed+100000+index,1,referenceDoppler,"trp_monostatic",0, ...
        "share_reuse",false,false,"single_port","B1",defaultCoherent, ...
        "random_isolated","default");
    pfaTrial.WaveformSeed=baseSeed;
    plan(end+1,1)=pfaTrial; %#ok<AGROW>
end
end

function trial = localTrial(index,stage,profile,seed,delay,doppler,mode,ratio,response,useGeometry,targetPresent,portProfile,receiverProfile,coherentSymbols,collisionMaskProfile,sequenceVariant)
trial = localEmptyTrial();
trial.TrialId = sprintf("%s_%05d",stage,index);
trial.Stage = char(stage);
trial.WaveformProfile = char(profile);
trial.Seed = double(seed);
trial.WaveformSeed=double(seed);
trial.DelayOverCP = double(delay);
trial.NormalizedDoppler = double(doppler);
trial.SensingMode = char(mode);
trial.CollisionRatioPercent = double(ratio);
trial.CollisionResponse = char(response);
trial.TDDPattern = "all_dl";
trial.TargetPresent = logical(targetPresent);
trial.UseGeometryDelay = logical(useGeometry);
trial.PortProfile = char(portProfile);
trial.ReceiverProfile=char(string(receiverProfile(1)));
trial.CoherentSymbols=double(coherentSymbols);
trial.CollisionMaskProfile=char(collisionMaskProfile);
trial.SequenceVariant=char(sequenceVariant);
end

function trial = localEmptyTrial()
trial = struct("TrialId","","Stage","","WaveformProfile","", ...
    "Seed",0,"WaveformSeed",0,"DelayOverCP",0,"NormalizedDoppler",0, ...
    "SensingMode","","CollisionRatioPercent",0, ...
    "CollisionResponse","","TDDPattern","all_dl", ...
    "TargetPresent",true,"UseGeometryDelay",false,"PortProfile","single_port", ...
    "ReceiverProfile","","CoherentSymbols",0,"CollisionMaskProfile","random_isolated", ...
    "SequenceVariant","default","RelationClass","","SharedResourceKnowledge","");
end

function out=localReceiverProfiles(profile)
switch upper(string(profile))
    case "W0", out=["B0";"B1"];
    case "W1", out="B0";
    case "W2", out="B2";
    case "W3", out="C0";
    otherwise, error("sixgr:isac:UnknownWaveformProfile","Unknown waveform %s.",profile);
end
end

function out=localPrimaryReceiver(profile)
values=localReceiverProfiles(profile); out=values(end);
end

function out=localDefaultVariant(profile)
if upper(string(profile))=="W1", out="per_occasion"; else, out="default"; end
end

function out = localStrings(value)
out = string(value(:));
end
