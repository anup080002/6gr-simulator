function S = summarizeHARQResidualBLER(T)
% Terminal receiver delivery outcomes, scoped by physical experiment point.
% An incomplete cohort exposes counts, never an uncensored residual BLER.
prototype=struct('Direction',"",'ProbeMode',"",'SweepPointIndex',NaN, ...
    'ConfiguredSNR_dB',NaN,'ObservedPackets',0,'TerminalPackets',0, ...
    'QualifiedPackets',0,'ResidualErrors',0,'UnresolvedPackets',0, ...
    'LeftCensoredPackets',0,'InitialTrials',0,'InitialErrors',0, ...
    'InitialBLER',NaN,'ResidualBLER',NaN,'PopulationStatus',"");
S=struct2table(repmat(prototype,0,1));
required=["Direction","ProbeMode","PacketID","Attempt","CombinedDecodeOK","StopCondition"];
if isempty(T) || ~all(ismember(required,string(T.Properties.VariableNames))), return; end
direction=string(T.Direction); mode=string(T.ProbeMode);
assert(~any(ismissing(direction) | ismissing(mode)), ...
    'sixgr:truth:MissingResidualHARQScope','Direction and execution mode must be explicit.');
point=localNumeric(T,'SweepPointIndex'); snr=localNumeric(T,'ConfiguredSNR_dB');
probe=ismember(mode,["observation","exercise","closed_loop"]);
if ismember('SNR_dB',T.Properties.VariableNames)
    snr(probe)=double(T.SNR_dB(probe)); % Probe axis, not runtime measured SINR.
end
keys=direction+"|"+mode+"|point="+compose('%.17g',point)+"|snr="+compose('%.17g',snr);
for key=unique(keys,'stable').'
    idx=find(keys==key); Q=T(idx,:);
    r=prototype; r.Direction=direction(idx(1)); r.ProbeMode=mode(idx(1));
    r.SweepPointIndex=point(idx(1)); r.ConfiguredSNR_dB=snr(idx(1));
    id=string(Q.PacketID);
    if any(ismissing(id) | strlength(strtrim(id))==0 | lower(id)=="nan")
        error('sixgr:truth:MissingResidualHARQPacketIdentity','Packet identity is required.');
    end
    for packet=unique(id,'stable').'
        P=Q(id==packet,:); [~,order]=sort(double(P.Attempt)); P=P(order,:);
        r.ObservedPackets=r.ObservedPackets+1;
        attempts=double(P.Attempt); crc=double(P.CombinedDecodeOK);
        assert(all(~isfinite(crc) | crc==0 | crc==1), ...
            'sixgr:truth:InvalidResidualHARQReceiverDecision','CRC decisions must be zero, one, or unavailable.');
        original=attempts(1)==1;
        if ismember('IsRetransmission',P.Properties.VariableNames)
            original=original && double(P.IsRetransmission(1))==0;
        end
        if ~original, r.LeftCensoredPackets=r.LeftCensoredPackets+1; end
        if original && ismember('CurrentDecodeOK',P.Properties.VariableNames)
            current=double(P.CurrentDecodeOK(1));
            standalone=true;
            if ismember('CurrentAttemptStandaloneCRCMeasured',P.Properties.VariableNames)
                standalone=double(P.CurrentAttemptStandaloneCRCMeasured(1))==1;
            end
            if standalone && isfinite(current) && any(current==[0 1])
                r.InitialTrials=r.InitialTrials+1;
                r.InitialErrors=r.InitialErrors+double(current==0);
            end
        end
        complete=original && isequal(attempts,(1:height(P)).') && ...
            all(isfinite(crc) & (crc==0 | crc==1));
        terminal=false;
        if r.ProbeMode=="canonical_slot_runtime_truth"
            needed=["TransmitterTerminal","TransmitterLifecycleBound", ...
                "HARQPacketReceiverPopulationComplete"];
            if all(ismember(needed,string(P.Properties.VariableNames)))
                terminal=nnz(double(P.TransmitterTerminal)==1)==1 && ...
                    double(P.TransmitterTerminal(end))==1;
                complete=complete && all(double(P.TransmitterLifecycleBound)==1) && ...
                    all(double(P.HARQPacketReceiverPopulationComplete)==1);
            else
                complete=false;
            end
        elseif ismember(r.ProbeMode,["observation","exercise","closed_loop"])
            stop=string(P.StopCondition);
            terminal=any(stop(end)==["ack","crc_pass","max_retx_drop"]) && ...
                all(stop(1:end-1)=="pending");
            if terminal && complete
                if any(stop(end)==["ack","crc_pass"])
                    assert(crc(end)==1,'sixgr:truth:HARQProbeStopCRCConflict','Successful ideal-feedback probe stop requires receiver CRC success.');
                else
                    assert(all(crc==0),'sixgr:truth:HARQProbeStopCRCConflict','A dropped ideal-feedback probe cannot contain an earlier successful decode.');
                end
            end
        end
        r.TerminalPackets=r.TerminalPackets+double(terminal);
        if terminal && complete
            r.QualifiedPackets=r.QualifiedPackets+1;
            % False NACKs may cause further TX after the TB was delivered;
            % false ACKs may stop TX despite every receiver decode failing.
            r.ResidualErrors=r.ResidualErrors+double(~any(crc==1));
        end
    end
    r.UnresolvedPackets=r.ObservedPackets-r.QualifiedPackets;
    if r.InitialTrials>0
        r.InitialBLER=r.InitialErrors/r.InitialTrials;
    end
    r.PopulationStatus="incomplete_or_censored_no_residual_bler";
    if r.ObservedPackets>0 && r.UnresolvedPackets==0
        r.ResidualBLER=r.ResidualErrors/r.ObservedPackets;
        r.PopulationStatus="complete_observed_terminal_population_not_statistical_qualification";
    end
    S=[S;struct2table(r)]; %#ok<AGROW>
end
end

function v=localNumeric(T,name)
v=nan(height(T),1);
if ismember(name,string(T.Properties.VariableNames)), v=double(T.(name)); end
end
