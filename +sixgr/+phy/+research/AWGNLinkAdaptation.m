classdef AWGNLinkAdaptation < handle
    % Measured-noise ILLA plus first-attempt CRC OLLA for identity AWGN only.
    % Calibration predicts schedulability, never replaces executed decoding.
    properties (SetAccess=private)
        Direction
        Policy
        OLLA
        ThresholdDb
        CalibrationSHA256
        FeedbackCount = 0
        MeasurementSlot = -Inf
        NoiseVariance = NaN
        Decisions = struct([])
        Updates = struct([])
        FirstAttemptTBs
        LastClock = -1
    end
    methods
        function obj=AWGNLinkAdaptation(s,direction)
            obj.Direction=upper(string(direction)); obj.Policy=s.research_adaptation;
            obj.FirstAttemptTBs=containers.Map('KeyType','char','ValueType','logical');
            p=obj.Policy; section="research_"+lower(obj.Direction);
            assert(p.enabled && s.harq.enabled && s.(section).harq_enabled && ...
                isfield(s,'research_awgn_mimo') && string(s.research_link.channel)=="identity_awgn" && ...
                string(s.research_receiver.channel_estimation)=="perfect_identity_awgn", ...
                'sixgr:research:AdaptationScope','Adaptive research reception requires fixed-port perfect identity AWGN and ideal delayed HARQ.');
            assert(p.target_bler<1 && p.calibration_confidence<1 && ...
                p.margin_min_db<=0 && p.margin_max_db>=0 && p.margin_min_db<p.margin_max_db, ...
                'sixgr:research:InvalidAdaptationPolicy','BLER/confidence must be below one and OLLA bounds must contain zero.');
            assert(isfile(p.calibration_file),'sixgr:research:MissingAdaptationCalibration', ...
                'Generate actual coded calibration first: %s.',p.calibration_file);
            provenanceFile=fullfile(fileparts(p.calibration_file),'provenance.json');
            assert(isfile(provenanceFile),'sixgr:research:MissingCalibrationProvenance','Calibration environment provenance is required.');
            provenance=jsondecode(fileread(provenanceFile));
            assert(isfield(provenance,'MATLAB') && string(provenance.MATLAB)==string(version), ...
                'sixgr:research:CalibrationEnvironmentMismatch', ...
                'Regenerate calibration on this MATLAB version; do not silently reuse another receiver implementation.');
            savedConfig=fullfile(fileparts(p.calibration_file),'resolved_config.json');
            assert(isfile(savedConfig),'sixgr:research:MissingCalibrationProvenance','The executed calibration configuration is required.');
            calibratedScenario=jsondecode(fileread(savedConfig));
            obj.CalibrationSHA256=sixgr.util.sha256File(p.calibration_file);
            T=readtable(p.calibration_file,'TextType','string');
            required=["TrialIndex","Direction","Candidate","ProfileHash","CodecSHA256","ReferenceSNRdB", ...
                "MeasuredLayerSINRdB","CRCPass","TBExact","Source"];
            assert(all(ismember(required,string(T.Properties.VariableNames))) && ...
                numel(unique(T.TrialIndex))==height(T) && all(T.Source=="actual_coded_research_calibration") && ...
                all(T.CodecSHA256==sixgr.util.sha256File(which('sixgr.phy.research.SharedChannelLink'))) && ...
                all(ismember(T.CRCPass,[0 1])) && all(ismember(T.TBExact,[0 1])) && ...
                all(T.TBExact(logical(T.CRCPass))), ...
                'sixgr:research:InvalidAdaptationCalibration','Calibration needs current-code executed CRC and exact-payload evidence.');
            obj.ThresholdDb=Inf(1,numel(p.candidate_layers));
            for k=1:numel(obj.ThresholdDb)
                sc=sixgr.phy.research.AWGNLinkAdaptation.candidate(s,obj.Direction,k);
                savedCandidate=sixgr.phy.research.AWGNLinkAdaptation.candidate(calibratedScenario,obj.Direction,k);
                hash=sixgr.phy.research.AWGNLinkAdaptation.profileHash(savedCandidate,obj.Direction);
                rows=T.Direction==obj.Direction & T.Candidate==k;
                % First bind rows to their saved executed input. Then compare
                % active PHY settings; YAML reload can add inactive aliases.
                compatible=sixgr.phy.research.AWGNLinkAdaptation.physicalProfileHash(sc,obj.Direction)== ...
                    sixgr.phy.research.AWGNLinkAdaptation.physicalProfileHash(savedCandidate,obj.Direction);
                assert(any(rows) && all(T.ProfileHash(rows)==hash) && compatible, ...
                    'sixgr:research:CalibrationProfileMismatch', ...
                    'Candidate %d/%s needs profile %s; recorded profiles: %s.', ...
                    k,obj.Direction,hash,strjoin(unique(T.ProfileHash(rows)),","));
                points=unique(T.ReferenceSNRdB(rows));
                for point=reshape(points,1,[])
                    at=rows & T.ReferenceSNRdB==point; n=sum(at); errors=sum(~logical(T.CRCPass(at)));
                    if errors==n, blerUpper=1; else, blerUpper=betaincinv(p.calibration_confidence,errors+1,n-errors); end
                    if n>=p.calibration_trials_per_point && blerUpper<=p.target_bler
                        measured=T.MeasuredLayerSINRdB(at);
                        assert(all(isfinite(measured)),'sixgr:research:InvalidCalibrationMeasurement','Finite receiver SINR is required.');
                        threshold=10*log10(mean(10.^(measured/10)));
                        obj.ThresholdDb(k)=min(obj.ThresholdDb(k),threshold);
                    end
                end
            end
            assert(any(isfinite(obj.ThresholdDb)),'sixgr:research:UnqualifiedAdaptationCandidates', ...
                'No candidate meets the configured pointwise binomial upper-bound gate.');
            assert(isfinite(obj.ThresholdDb(p.bootstrap_candidate)), ...
                'sixgr:research:UnqualifiedBootstrap','The bootstrap candidate needs coded calibration support.');
            key=struct('UEID',s.(section).rnti,'Direction',obj.Direction, ...
                'ServingCellID',s.(section).nid,'ScheduledCellID',s.(section).nid, ...
                'BWPID',0,'MCSTable',"research_explicit_candidate_menu",'ConfigurationEpoch',obj.CalibrationSHA256);
            obj.OLLA=sixgr.phy.rsla.OLLAState(key,p.target_bler,p.ack_step_db, ...
                p.margin_min_db,p.margin_max_db,"IGNORE");
        end

        function advance(obj,feedback,slot)
            assert(slot>=obj.LastClock,'sixgr:research:AdaptationClockReversed','Adaptation clock must be monotonic.');
            obj.LastClock=slot;
            assert(numel(feedback)>=obj.FeedbackCount,'sixgr:research:FeedbackHistoryTruncated','Feedback history must be append-only.');
            for k=obj.FeedbackCount+1:numel(feedback)
                e=feedback(k);
                assert(e.Direction==obj.Direction && e.DeliveredAtSlot<=slot && ...
                    e.FeedbackMode=="ideal_delayed_receiver_CRC" && ...
                    e.DeliveredAtSlot>=e.AvailableSlot && e.AvailableSlot>e.SourceSlot && ...
                    isfinite(e.MeasuredNoiseVariance) && e.MeasuredNoiseVariance>0, ...
                    'sixgr:research:NoncausalAdaptationFeedback','Use only available direction-owned receiver measurements.');
                if e.SourceSlot>obj.MeasurementSlot
                    obj.NoiseVariance=e.MeasuredNoiseVariance; obj.MeasurementSlot=e.SourceSlot;
                end
                % Combined-retransmission success is NOT first-transmission
                % success and must not bias the configured first-attempt BLER.
                if e.AttemptIndex==1
                    assert(~isKey(obj.FirstAttemptTBs,char(e.TBID)), ...
                        'sixgr:research:DuplicateOLLAFeedback','One OLLA update per initial TB is allowed.');
                    obj.FirstAttemptTBs(char(e.TBID))=true;
                    outcome="NACK"; if e.CRCPass, outcome="ACK"; end
                    before=obj.OLLA.MarginDb; obj.OLLA.update(outcome,slot);
                    row=struct('TBID',e.TBID,'SourceSlot',e.SourceSlot,'AppliedSlot',slot, ...
                        'Outcome',outcome,'MarginBeforeDb',before,'MarginAfterDb',obj.OLLA.MarginDb);
                    if isempty(obj.Updates), obj.Updates=row; else, obj.Updates(end+1)=row; end
                end
                obj.FeedbackCount=k;
            end
        end

        function [sc,allowNew,row]=select(obj,s,slot)
            assert(slot==obj.LastClock,'sixgr:research:AdaptationClockNotAdvanced','Advance feedback before selecting new data.');
            p=obj.Policy; bootstrap=~isfinite(obj.NoiseVariance);
            index=p.bootstrap_candidate; allowNew=true; predicted=NaN;
            reason="configured_bootstrap_before_first_feedback";
            if ~bootstrap
                scores=-Inf(size(obj.ThresholdDb)); predictedSINR=NaN(size(scores));
                if slot-obj.MeasurementSlot<=p.max_measurement_age_slots
                    for k=1:numel(scores)
                        trial=sixgr.phy.research.AWGNLinkAdaptation.candidate(s,obj.Direction,k);
                        a=sixgr.phy.research.SharedChannelLink.allocation(trial,slot,obj.Direction);
                        predictedSINR(k)=10*log10(1/(a.NumLayers*obj.NoiseVariance));
                        if predictedSINR(k)-obj.OLLA.MarginDb>=obj.ThresholdDb(k)
                            scores(k)=a.TransportBlockSize;
                        end
                    end
                end
                [score,index]=max(scores); allowNew=isfinite(score);
                reason="measured_noise_calibrated_ILLA_plus_CRC_OLLA";
                if ~allowNew
                    index=p.bootstrap_candidate; reason="outage_or_stale_measurement_no_new_TB";
                else
                    predicted=predictedSINR(index);
                end
            end
            sc=sixgr.phy.research.AWGNLinkAdaptation.candidate(s,obj.Direction,index);
            measurementSlot=obj.MeasurementSlot;
            if ~isfinite(measurementSlot), measurementSlot=NaN; end
            row=struct('Direction',obj.Direction,'Slot',slot,'NewDataCandidate',index, ...
                'AllowNewTB',allowNew,'BootstrapUsed',bootstrap,'Reason',reason, ...
                'MeasurementSlot',measurementSlot,'MeasuredNoiseVariance',obj.NoiseVariance, ...
                'PredictedCandidateSINRdB',predicted,'CalibratedThresholdDb',obj.ThresholdDb(index), ...
                'OLLAMarginDb',obj.OLLA.MarginDb,'Source',"scheduler_policy_prediction_not_decoded_KPI");
            if isempty(obj.Decisions), obj.Decisions=row; else, obj.Decisions(end+1)=row; end
        end
    end
    methods (Static)
        function sc=candidate(s,direction,index)
            p=s.research_adaptation; count=numel(p.candidate_layers);
            assert(numel(p.candidate_modulations)==count && numel(p.candidate_code_rates)==count && ...
                p.bootstrap_candidate<=count && index>=1 && index<=count, ...
                'sixgr:research:CandidateMenuMismatch','Candidate modulation/rank/rate lists must align.');
            sc=s; section="research_"+lower(string(direction)); rank=p.candidate_layers(index);
            ports=s.(section).dmrs_port_set;
            assert(numel(ports)>=rank && s.research_awgn_mimo.physical_ports>=rank, ...
                'sixgr:research:CandidatePortMismatch','Base config must provide DMRS and physical ports for every candidate.');
            sc.(section).num_layers=rank; sc.(section).dmrs_port_set=ports(1:rank);
            mods=string(p.candidate_modulations);
            sc.(section).modulation=char(mods(index));
            sc.(section).target_code_rate=p.candidate_code_rates(index);
        end

        function hash=profileHash(s,direction)
            ch=s.("research_"+lower(string(direction)));
            ch.harq_enabled=false; ch.rv=0;
            profile=struct('Direction',string(direction),'Allocation',ch, ...
                'Frequency',s.frequency,'Waveform',s.waveform,'Receiver',s.research_receiver, ...
                'PhysicalPorts',s.research_awgn_mimo,'Channel',s.channels, ...
                'Impairments',s.impairments);
            hash=sixgr.phy.rsla.RSLAUtil.hash(profile);
        end

        function hash=physicalProfileHash(s,direction)
            % Only executed settings, not inactive compatibility aliases.
            frame=sixgr.phy.FrameStructureEngine(s,'FrameCoreOnly',true);
            ch=s.("research_"+lower(string(direction))); ch.harq_enabled=false; ch.rv=0;
            flags=[s.impairments.cfo_enabled,s.impairments.phase_noise_enabled, ...
                s.impairments.iq_imbalance_enabled,s.impairments.pa_nonlinearity_enabled, ...
                s.impairments.timing_offset_enabled];
            channel=struct('Model',string(s.channels.model_type),'Profile',string(s.channels.profile), ...
                'Doppler',s.channels.doppler_hz,'Pathloss',logical(s.channels.pathloss_enabled), ...
                'ShadowFading',logical(s.channels.shadow_fading_enabled), ...
                'Link',string(s.research_link.channel),'RF',string(s.research_link.rf));
            profile=struct('Direction',string(direction),'Allocation',orderfields(ch), ...
                'NRB',frame.NRB,'SCSkHz',frame.SCSkHz,'FFTSize',frame.FFTSize, ...
                'SampleRateHz',frame.SampleRate_Hz,'CP',frame.CyclicPrefix, ...
                'CenterFrequencyHz',s.frequency.center_frequency_hz, ...
                'WindowingSamples',s.waveform.windowing_samples, ...
                'Receiver',orderfields(s.research_receiver), ...
                'PhysicalPorts',orderfields(s.research_awgn_mimo), ...
                'Channel',channel,'ImpairmentFlags',logical(flags));
            hash=sixgr.phy.rsla.RSLAUtil.hash(profile);
        end
    end
end
