classdef CheckpointContinuationRequest
    % Explicit restoration of SAVED science; not a scenario-validation bypass.
    % No scientific overrides or inheritance are accepted. Metadata selects
    % the routing configuration only; native state must still agree with it
    % before any run-folder mutation. Current YAML defaults are never merged.
    properties (SetAccess=private)
        Path
        ExpectedStateSHA256
        ExpectedConfigHash
        RepairReason
        OperationalSettings
        RequestPath
        RequestSHA256
        Metadata
        ExecutionHorizon = struct()
    end
    methods (Static)
        function obj=fromFile(path)
            raw=sixgr.lls6g.config.readConfigFile(path);
            obj=[];
            if isfield(raw,'checkpoint_continuation')
                obj=sixgr.runtime.CheckpointContinuationRequest(raw,path);
            end
        end
    end
    methods
        function obj=CheckpointContinuationRequest(raw,path)
            assert(isequal(fieldnames(raw),{'checkpoint_continuation'}), ...
                'sixgr:checkpoint:RequestScienceOverride', ...
                'A saved-configuration continuation cannot also declare scenario fields or inheritance.');
            r=raw.checkpoint_continuation;
            required={'contract','checkpoint','state_sha256','config_hash','repair_reason'};
            assert(isstruct(r)&&isscalar(r)&&all(isfield(r,required))&& ...
                all(ismember(fieldnames(r),[required {'operational_settings','finish_after_slot'}].')), ...
                'sixgr:checkpoint:InvalidContinuationRequest', ...
                'Use only the versioned checkpoint identity, repair reason and operational settings.');
            for name=string(required)
                assert((ischar(r.(name))||isstring(r.(name)))&&isscalar(string(r.(name)))&& ...
                    ~ismissing(string(r.(name)))&&strlength(strtrim(string(r.(name))))>0, ...
                    'sixgr:checkpoint:InvalidContinuationRequest','Missing scalar request field %s.',name);
            end
            assert(string(r.contract)=="sixgr_checkpoint_continuation/v1", ...
                'sixgr:checkpoint:InvalidContinuationRequest','Unsupported continuation request contract.');
            for name=["state_sha256","config_hash"]
                assert(~isempty(regexp(char(string(r.(name))),'^[a-f0-9]{64}$','once')), ...
                    'sixgr:checkpoint:InvalidContinuationRequest','%s must be the explicit original SHA-256 identity.',name);
            end
            obj.RequestPath=string(sixgr.util.canonicalPath(path));
            obj.RequestSHA256=string(sixgr.util.sha256File(path));
            requested=java.io.File(char(string(r.checkpoint)));
            assert(requested.isAbsolute(),'sixgr:checkpoint:InvalidContinuationRequest', ...
                'Use an absolute checkpoint path; never resolve it against a changed working directory.');
            obj.Path=string(requested.getCanonicalPath());
            obj.ExpectedStateSHA256=string(r.state_sha256);
            obj.ExpectedConfigHash=string(r.config_hash);
            obj.RepairReason=string(r.repair_reason);
            obj.OperationalSettings=sixgr.util.structGet(r,'operational_settings',struct());
            % Reuse the production allow-list and type/range checks. This
            % validates execution controls, not a new waveform configuration.
            probe.run=struct('runtimeCheckpointScenario',struct('run_control',struct()), ...
                'runtimeCheckpointEnabled',false,'checkpointEverySlots',1);
            sixgr.runtime.SlotCheckpoint.applyOperationalSettings(probe,obj.OperationalSettings);
            [savedScenario,obj.Metadata]=sixgr.runtime.SlotCheckpoint.savedScenarioMetadata( ...
                obj.Path,obj.ExpectedStateSHA256,obj.ExpectedConfigHash);
            if isfield(r,'finish_after_slot')
                obj.ExecutionHorizon=sixgr.runtime.CheckpointExecutionHorizon.fromRequest( ...
                    savedScenario,obj.Metadata,r.finish_after_slot,obj.RequestPath,obj.RequestSHA256);
            end
        end

        function [data,metadata]=verifiedMetadata(obj)
            assert(isfile(obj.RequestPath)&& ...
                string(sixgr.util.sha256File(obj.RequestPath))==obj.RequestSHA256, ...
                'sixgr:checkpoint:ContinuationRequestChanged','Continuation request changed after preparation.');
            [data,metadata]=sixgr.runtime.SlotCheckpoint.savedScenarioMetadata( ...
                obj.Path,obj.ExpectedStateSHA256,obj.ExpectedConfigHash);
            assert(isequaln(metadata,obj.Metadata), ...
                'sixgr:checkpoint:SavedMetadataChanged','Checkpoint metadata changed after request validation.');
        end

        function scenario=applyOperational(obj,scenario)
            cfg.run.runtimeCheckpointScenario=scenario;
            cfg.run.runtimeCheckpointEnabled=logical(sixgr.util.structGet(scenario, ...
                'run_control.runtime_checkpoint_enable',false));
            cfg.run.checkpointEverySlots=double(sixgr.util.structGet(scenario, ...
                'run_control.checkpoint_every_slots',1));
            cfg=sixgr.runtime.SlotCheckpoint.applyOperationalSettings(cfg,obj.OperationalSettings);
            scenario=cfg.run.runtimeCheckpointScenario;
            scenario.run_control.runtime_checkpoint_resume_from=char(obj.Path);
            scenario.run_control.runtime_checkpoint_repair_reason=char(obj.RepairReason);
        end

        function scfg=preview(obj)
            [data,metadata]=obj.verifiedMetadata();
            assert(string(sixgr.util.structGet(data,'scenario.runner_profile',""))=="waveform_bundle" && ...
                string(sixgr.util.structGet(data,'output.backend',""))=="filesystem", ...
                'sixgr:checkpoint:UnsupportedResumeBackend', ...
                'Saved-configuration restoration requires a filesystem waveform-bundle checkpoint.');
            % Only for routing until prepareResume verifies native state.
            scfg=sixgr.lls6g.config.ScenarioConfig(obj.applyOperational(data), ...
                'ConfigHash',obj.ExpectedConfigHash,'ConfigPath',obj.RequestPath, ...
                'SourceFiles',[obj.RequestPath;string(metadata.ResolvedSource)],'Kind','checkpoint_continuation');
        end
    end
end
