classdef PDSCHHARQManager < handle
    %PDSCHHARQManager Own codeword-specific, position-aware HARQ buffers.

    properties (SetAccess = immutable)
        Capability (1,1) struct
    end

    properties (Access = private)
        Contexts
    end

    methods
        function obj = PDSCHHARQManager(capability)
            arguments
                capability (1,1) struct
            end
            if ~isfield(capability, "MaxProcesses") || ...
                    ~isscalar(capability.MaxProcesses) || ...
                    ~isfinite(capability.MaxProcesses) || ...
                    capability.MaxProcesses ~= fix(capability.MaxProcesses) || ...
                    capability.MaxProcesses < 1
                error("sixgr:pdsch:MissingHARQCapability", ...
                    "HARQ MaxProcesses must come from UE/serving-cell capability.");
            end
            obj.Capability = orderfields(capability);
            obj.Contexts = containers.Map("KeyType", "char", "ValueType", "any");
        end

        function [context, result] = process(obj, observation)
            arguments
                obj
                observation (1,1) struct
            end
            obs = obj.validateObservation(observation);
            key = char(sixgr.pdsch.PDSCHHARQContext.digestKey(obs));
            familyKey = obj.familyDigest(obs);
            prior = struct();
            if isKey(obj.Contexts, key)
                priorObj = obj.Contexts(key);
                prior = priorObj.toStruct();
            else
                stale = obj.findFamilyContext(familyKey);
                if ~isempty(stale) && ~logical(obs.NewData)
                    error("sixgr:pdsch:HARQConfigurationEpochMismatch", ...
                        "HARQ retransmission configuration epoch does not match stored state.");
                end
            end

            isNew = isempty(fieldnames(prior)) || logical(obs.NewData) || ...
                logical(obs.NDI) ~= logical(prior.NDI);
            inputDigest = obj.digestSoft(obs.RateRecoveredLLR, obs.ValidPositionMask);
            if isNew
                data = obj.newContext(obs);
                combined = false;
                action = "reset_and_load_new_tb";
            else
                obj.assertCompatible(prior, obs);
                data = obj.combineContext(prior, obs);
                combined = true;
                action = "position_aware_soft_combine";
            end
            context = sixgr.pdsch.PDSCHHARQContext(data);
            obj.Contexts(key) = context;
            outputDigest = obj.digestSoft(data.CircularBufferLLR, data.ValidPositionMask);
            result = struct( ...
                "Action", action, ...
                "Combined", logical(combined), ...
                "SoftBufferInputDigest", char(inputDigest), ...
                "SoftBufferOutputDigest", char(outputDigest), ...
                "TransmissionCount", double(data.TransmissionCount), ...
                "RV", double(obs.RV), ...
                "TBCRCOK", logical(obs.DecodeOK), ...
                "ContextKeyDigest", char(context.KeyDigest));
        end

        function context = get(obj, key)
            arguments
                obj
                key (1,1) struct
            end
            digest = char(sixgr.pdsch.PDSCHHARQContext.digestKey(key));
            if isKey(obj.Contexts, digest)
                context = obj.Contexts(digest);
            else
                context = [];
            end
        end

        function clear(obj)
            obj.Contexts = containers.Map("KeyType", "char", "ValueType", "any");
        end
    end

    methods (Access = private)
        function obs = validateObservation(obj, obs)
            required = [ ...
                "UEId","ServingCellId","SchedulingCellId","CCId","BWPId", ...
                "HARQProcessId","CodewordIndex","ConfigurationEpoch", ...
                "NDI","NewData","RV","TBIdentityDigest","TBS", ...
                "CodingPlanDigest","BaseGraph","LiftingSize", ...
                "CodeBlockLayout","FillerPositions","Ncb","Nref", ...
                "RateRecoveredLLR","ValidPositionMask","DecodeOK"];
            missing = required(~isfield(obs, required));
            if ~isempty(missing)
                error("sixgr:pdsch:IncompleteHARQObservation", ...
                    "PDSCH HARQ observation is missing: %s.", ...
                    strjoin(cellstr(missing), ", "));
            end
            maxProcesses = double(obj.Capability.MaxProcesses);
            if ~isscalar(obs.HARQProcessId) || ...
                    obs.HARQProcessId ~= fix(obs.HARQProcessId) || ...
                    obs.HARQProcessId < 0 || obs.HARQProcessId >= maxProcesses
                error("sixgr:pdsch:HARQProcessIDOutOfRange", ...
                    "HARQ process ID must be in [0,%d] for this UE/cell.", ...
                    maxProcesses - 1);
            end
            if ~isscalar(obs.CodewordIndex) || ...
                    obs.CodewordIndex ~= fix(obs.CodewordIndex) || ...
                    ~any(obs.CodewordIndex == [0 1])
                error("sixgr:pdsch:HARQCodewordIndexOutOfRange", ...
                    "PDSCH HARQ codeword index must be zero or one.");
            end
            if ~isscalar(obs.RV) || obs.RV ~= fix(obs.RV) || ...
                    ~any(obs.RV == [0 1 2 3])
                error("sixgr:pdsch:RVOutOfRange", ...
                    "PDSCH HARQ RV must be one of 0, 1, 2, or 3.");
            end
            if ~(isscalar(obs.TBS) && isfinite(obs.TBS) && ...
                    obs.TBS == fix(obs.TBS) && obs.TBS > 0)
                error("sixgr:pdsch:HARQTBSMismatch", ...
                    "PDSCH HARQ TBS must be a positive integer.");
            end
            llr = double(obs.RateRecoveredLLR);
            mask = logical(obs.ValidPositionMask);
            if ~isequal(size(llr), size(mask))
                error("sixgr:pdsch:HARQPositionMapMismatch", ...
                    "Rate-recovered LLR and valid-position mask shapes differ.");
            end
            if isempty(llr)
                error("sixgr:pdsch:HARQPositionMapMismatch", ...
                    "PDSCH HARQ circular-buffer observation is empty.");
            end
            if any(~isfinite(llr(mask)))
                error("sixgr:pdsch:HARQInvalidLLR", ...
                    "Observed circular-buffer LLR positions must be finite.");
            end
            obs.RateRecoveredLLR = llr;
            obs.ValidPositionMask = mask;
        end

        function data = newContext(~, obs)
            llr = zeros(size(obs.RateRecoveredLLR));
            llr(obs.ValidPositionMask) = obs.RateRecoveredLLR(obs.ValidPositionMask);
            data = sixgr.pdsch.PDSCHHARQManager.baseContext(obs);
            data.RVHistory = double(obs.RV);
            data.CircularBufferLLR = llr;
            data.ValidPositionMask = logical(obs.ValidPositionMask);
            data.TransmissionCount = 1;
            data.LastDecodeOutcome = logical(obs.DecodeOK);
        end

        function data = combineContext(~, prior, obs)
            data = prior;
            data.RVHistory = [double(prior.RVHistory(:).'), double(obs.RV)];
            current = double(obs.RateRecoveredLLR);
            mask = logical(obs.ValidPositionMask);
            combined = double(prior.CircularBufferLLR);
            combined(mask) = combined(mask) + current(mask);
            data.CircularBufferLLR = combined;
            data.ValidPositionMask = logical(prior.ValidPositionMask) | mask;
            data.TransmissionCount = double(prior.TransmissionCount) + 1;
            data.LastDecodeOutcome = logical(obs.DecodeOK);
        end

        function assertCompatible(~, prior, obs)
            if string(prior.TBIdentityDigest) ~= string(obs.TBIdentityDigest)
                error("sixgr:pdsch:HARQTBIdentityMismatch", ...
                    "HARQ retransmission TB identity differs from stored state.");
            end
            if double(prior.TBS) ~= double(obs.TBS)
                error("sixgr:pdsch:HARQTBSMismatch", ...
                    "HARQ retransmission TBS differs from stored state.");
            end
            if string(prior.CodingPlanDigest) ~= string(obs.CodingPlanDigest)
                error("sixgr:pdsch:HARQCodingLayoutMismatch", ...
                    "HARQ retransmission coding layout differs from stored state.");
            end
            if double(prior.ConfigurationEpoch) ~= double(obs.ConfigurationEpoch)
                error("sixgr:pdsch:HARQConfigurationEpochMismatch", ...
                    "HARQ retransmission configuration epoch differs from stored state.");
            end
            if ~isequal(size(prior.CircularBufferLLR), size(obs.RateRecoveredLLR))
                error("sixgr:pdsch:HARQCodingLayoutMismatch", ...
                    "HARQ retransmission circular-buffer shape differs from stored state.");
            end
        end

        function stale = findFamilyContext(obj, familyDigest)
            stale = [];
            values = obj.Contexts.values();
            for idx = 1:numel(values)
                candidate = values{idx}.toStruct();
                if obj.familyDigest(candidate) == familyDigest
                    stale = values{idx};
                    return;
                end
            end
        end

        function digest = familyDigest(~, value)
            key = struct( ...
                "UEId", double(value.UEId), ...
                "ServingCellId", double(value.ServingCellId), ...
                "SchedulingCellId", double(value.SchedulingCellId), ...
                "CCId", double(value.CCId), ...
                "BWPId", double(value.BWPId), ...
                "HARQProcessId", double(value.HARQProcessId), ...
                "CodewordIndex", double(value.CodewordIndex));
            digest = string(sixgr.util.sha256Hex(uint8(unicode2native( ...
                jsonencode(orderfields(key)), "UTF-8"))));
        end

        function digest = digestSoft(~, llr, mask)
            payload = struct( ...
                "Size", double(size(llr)), ...
                "ValidIndex", double(find(mask(:))).', ...
                "ObservedLLR", double(llr(mask)).');
            digest = string(sixgr.util.sha256Hex(uint8(unicode2native( ...
                jsonencode(orderfields(payload)), "UTF-8"))));
        end
    end

    methods (Static, Access = private)
        function data = baseContext(obs)
            data = struct( ...
                "UEId", double(obs.UEId), ...
                "ServingCellId", double(obs.ServingCellId), ...
                "SchedulingCellId", double(obs.SchedulingCellId), ...
                "CCId", double(obs.CCId), ...
                "BWPId", double(obs.BWPId), ...
                "HARQProcessId", double(obs.HARQProcessId), ...
                "CodewordIndex", double(obs.CodewordIndex), ...
                "ConfigurationEpoch", double(obs.ConfigurationEpoch), ...
                "NDI", logical(obs.NDI), ...
                "TBIdentityDigest", string(obs.TBIdentityDigest), ...
                "TBS", double(obs.TBS), ...
                "CodingPlanDigest", string(obs.CodingPlanDigest), ...
                "BaseGraph", double(obs.BaseGraph), ...
                "LiftingSize", double(obs.LiftingSize), ...
                "CodeBlockLayout", obs.CodeBlockLayout, ...
                "FillerPositions", {obs.FillerPositions}, ...
                "Ncb", double(obs.Ncb), ...
                "Nref", double(obs.Nref), ...
                "RVHistory", zeros(1,0), ...
                "CircularBufferLLR", zeros(size(obs.RateRecoveredLLR)), ...
                "ValidPositionMask", false(size(obs.ValidPositionMask)), ...
                "TransmissionCount", 0, ...
                "LastDecodeOutcome", false);
        end
    end
end
