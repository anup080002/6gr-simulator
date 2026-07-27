classdef ProtocolConfigurationValidator
    %PROTOCOLCONFIGURATIONVALIDATOR Fail before runtime for unsupported tuples.
    methods (Static)
        function result=validate(config)
            if ~logical(config.enabled)
                result=table();return;
            end
            profile=string(config.profile_id);
            vectorRoot=string(config.vector_root);
            if ~isfolder(vectorRoot)
                here=fileparts(mfilename("fullpath"));
                repoRoot=fileparts(fileparts(here));
                vectorRoot=fullfile(repoRoot,vectorRoot);
            end
            if ~isfolder(vectorRoot)
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Protocol vector_root does not exist: %s.",vectorRoot);
            end
            features=strings(0,1);
            rlcMode=upper(string(config.rlc.mode));
            rlcSN=double(config.rlc.sn_bits);
            features(end+1)="RLC_"+rlcMode+string(rlcSN); %#ok<AGROW>
            bearer=upper(string(config.pdcp.bearer_type));
            pdcpSN=double(config.pdcp.sn_bits);
            features(end+1)="PDCP_"+bearer+string(pdcpSN); %#ok<AGROW>
            cipher=upper(string(config.pdcp.cipher_algorithm));
            integrity=upper(string(config.pdcp.integrity_algorithm));
            if cipher=="NEA0" && integrity=="NIA0"
                features(end+1)="PDCP_NEA0_NIA0"; %#ok<AGROW>
            elseif cipher=="128-NEA2" && integrity=="128-NIA2"
                features(end+1)="PDCP_NEA2_NIA2"; %#ok<AGROW>
            else
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Mixed/unsupported PDCP security tuple %s/%s.", ...
                    cipher,integrity);
            end
            features(end+1)="SDAP_UL_DL_HEADER"; %#ok<AGROW>
            rrc=config.rrc;
            featureMap={ ...
                "setup_enabled","RRC_SETUP"; ...
                "security_mode_enabled","RRC_SECURITY_MODE"; ...
                "capability_exchange_enabled","RRC_CAPABILITY"; ...
                "reconfiguration_enabled","RRC_RECONFIG_BEARER"; ...
                "handover_enabled","INTRA_FREQ_HO"};
            for index=1:size(featureMap,1)
                if isfield(rrc,featureMap{index,1}) && ...
                        logical(rrc.(featureMap{index,1}))
                    features(end+1)=string(featureMap{index,2}); %#ok<AGROW>
                end
            end
            sessions=config.traffic.sessions;
            if iscell(sessions),sessions=[sessions{:}];end
            for index=1:numel(sessions)
                trafficProfile=upper(string(sessions(index).profile_id));
                switch trafficProfile
                    case "CBR"
                        features(end+1)="CBR_PACKET_TRAFFIC"; %#ok<AGROW>
                    case "POISSON"
                        features(end+1)="POISSON_TRAFFIC"; %#ok<AGROW>
                    case "XR_PDU_SET"
                        features(end+1)="XR_PDU_SET"; %#ok<AGROW>
                    case "TRACE_REPLAY"
                        features(end+1)="TRACE_REPLAY"; %#ok<AGROW>
                    otherwise
                        error("sixgr:traffic:InvalidTrafficProfile", ...
                            "Unsupported configured traffic profile %s.", ...
                            trafficProfile);
                end
            end
            features=unique(features,"stable");
            result=table('Size',[numel(features) 4], ...
                'VariableTypes',repmat({'string'},1,4), ...
                'VariableNames',{'ProfileID','Feature','Result','Reason'});
            for index=1:numel(features)
                plan=sixgr.protocol.ProtocolCapabilityPlanner.require( ...
                    profile,features(index),vectorRoot);
                result(index,:)={profile,features(index), ...
                    plan.PlanningResult,plan.Reason};
            end
        end
    end
end
