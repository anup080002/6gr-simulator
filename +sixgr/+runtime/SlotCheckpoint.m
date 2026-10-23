classdef SlotCheckpoint
    % Exact completed-slot state plus external artifact byte watermarks.
    % Never reconstruct a receiver, HARQ buffer or channel from CSV rows.
    % A changed-source continuation is diagnostic evidence, not qualification.
    methods (Static)
        function identity = sourceIdentity()
            root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
            files=dir(fullfile(root,'+sixgr','**','*.m'));
            files=[files;dir(fullfile(root,'+sixgr','**','*.mexw64'))];
            files=[files;dir(fullfile(root,'apps','**','*.py'))];
            files=[files;dir(fullfile(root,'scripts','*.m'))];
            files=[files;dir(fullfile(root,'*.m'))];
            rows=struct('Path',{},'SHA256',{});
            for k=1:numel(files)
                path=fullfile(files(k).folder,files(k).name);
                rows(end+1)=struct('Path',string(path(numel(root)+2:end)), ...
                    'SHA256',sixgr.util.sha256File(path)); %#ok<AGROW>
            end
            [~,order]=sort(string({rows.Path})); rows=rows(order);
            identity=struct('Files',rows,'SHA256',sixgr.util.sha256Hex( ...
                uint8(unicode2native(jsonencode(rows),'UTF-8'))));
        end

        function data = scientificScenario(data)
            % Checkpoint controls change execution, not the scientific setup.
            % These two diagnostics/display policies do not change samples,
            % measurements, radio timing, RNG or terminal export populations.
            % Keep every other output/scientific setting in the comparison.
            if isfield(data,'output')
                operational={'live_csv_png_interval_slots','execution_stage_profile_enabled'};
                for k=1:numel(operational)
                    if isfield(data.output,operational{k})
                        data.output=rmfield(data.output,operational{k});
                    end
                end
            end
            fields={'runtime_checkpoint_enable','runtime_checkpoint_resume_from', ...
                'runtime_checkpoint_repair_reason','runtime_checkpoint_keep', ...
                'checkpoint_every_slots','checkpoint_first_slot'};
            for k=1:numel(fields)
                if isfield(data.run_control,fields{k})
                    data.run_control=rmfield(data.run_control,fields{k});
                end
            end
            % The loader records the restart YAML's pathname/inheritance
            % chain even when all executed settings are identical. These
            % generated locations are provenance, not scientific policy.
            % Keep all resolved values (especially seed, RF and timing)
            % exact, and retain both provenance records in the receipt.
            if isfield(data,'config_inheritance')
                if isfield(data.config_inheritance,'parents')
                    data.config_inheritance=rmfield(data.config_inheritance,'parents');
                end
                if isfield(data.config_inheritance,'provenance')
                    generated={'source_files','config_path'};
                    for k=1:numel(generated)
                        if isfield(data.config_inheritance.provenance,generated{k})
                            data.config_inheritance.provenance=rmfield( ...
                                data.config_inheritance.provenance,generated{k});
                        end
                    end
                end
            end
        end

        function settings = operationalSettings(scenario)
            % Kept separately from the original scientific/config hash.
            settings=struct('run_control',struct(),'output',struct());
            for name=["runtime_checkpoint_enable","checkpoint_every_slots","checkpoint_first_slot","runtime_checkpoint_keep"]
                if isfield(scenario.run_control,name)
                    settings.run_control.(name)=scenario.run_control.(name);
                end
            end
            for name=["live_csv_png_interval_slots","execution_stage_profile_enabled"]
                if isfield(scenario,'output') && isfield(scenario.output,name)
                    settings.output.(name)=scenario.output.(name);
                end
            end
        end

        function cfg = applyOperationalSettings(cfg,settings)
            % Only reviewed diagnostic/recovery controls may cross the
            % canonical-config restoration boundary. Never copy arbitrary
            % request output/run fields, grants, RNG or physical state.
            assert(isstruct(settings) && isscalar(settings) && ...
                all(ismember(fieldnames(settings),{'run_control','output'})), ...
                'sixgr:checkpoint:InvalidOperationalSettings','Unexpected operational settings.');
            allowed=struct('run_control',{{'runtime_checkpoint_enable','checkpoint_every_slots','checkpoint_first_slot','runtime_checkpoint_keep'}}, ...
                'output',{{'live_csv_png_interval_slots','execution_stage_profile_enabled'}});
            mapping=struct('runtime_checkpoint_enable','run.runtimeCheckpointEnabled', ...
                'checkpoint_every_slots','run.checkpointEverySlots', ...
                'checkpoint_first_slot','run.checkpointFirstSlot', ...
                'live_csv_png_interval_slots','outputs.liveCSVPNGIntervalSlots', ...
                'execution_stage_profile_enabled','outputs.executionStageProfileEnabled');
            scenario=cfg.run.runtimeCheckpointScenario;
            for group=string(fieldnames(settings)).'
                values=settings.(group);
                assert(isstruct(values) && isscalar(values) && ...
                    all(ismember(fieldnames(values),allowed.(group))), ...
                    'sixgr:checkpoint:InvalidOperationalSettings','Unreviewed operational setting.');
                for name=string(fieldnames(values)).'
                    value=values.(name);
                    if any(name==["runtime_checkpoint_enable","execution_stage_profile_enabled"])
                        validateattributes(value,{'logical'},{'scalar'});
                    elseif any(name==["checkpoint_every_slots","checkpoint_first_slot"])
                        validateattributes(value,{'numeric'},{'scalar','integer','nonnegative','finite'});
                    else
                        validateattributes(value,{'numeric'},{'scalar','integer','positive','finite'});
                    end
                    scenario.(group).(name)=value;
                    if isfield(mapping,name)
                        cfg=sixgr.util.structSet(cfg,mapping.(name),value);
                    end
                end
            end
            assert(~cfg.run.runtimeCheckpointEnabled || cfg.run.checkpointEverySlots>=1, ...
                'sixgr:checkpoint:InvalidOperationalSettings','Enabled checkpoints need a positive cadence.');
            cfg.run.runtimeCheckpointScenario=scenario;
            cfg.run.runtimeCheckpointOperationalSettings=settings;
        end

        function path = write(root,payload,scenario,source)
            checkpointScope=sixgr.runtime.ExecutionStageProfiler.scope("checkpoint","completed_slot_save"); %#ok<NASGU>
            root=localCanonical(root);
            assert(isstruct(payload) && all(isfield(payload, ...
                {'RuntimeState','CompletedSlot','RNG'})), ...
                'sixgr:checkpoint:MissingState','Checkpoint needs actual runtime state, clock and RNG.');
            slot=double(payload.CompletedSlot);
            validateattributes(slot,{'double'},{'scalar','integer','positive','finite'});
            assert(payload.RuntimeState.CurrentSlot==slot, ...
                'sixgr:checkpoint:ClockMismatch','Only a fully completed slot can be saved.');
            if isfield(payload.RuntimeState,'SharedWaveformStream')
                stream=payload.RuntimeState.SharedWaveformStream;
                assert(~stream.Events.Faulted && ~stream.Physical.Faulted && ...
                    stream.Events.NextSampleIndex==stream.Physical.NextSampleIndex, ...
                    'sixgr:checkpoint:FaultedState','Do not save a faulted or split-clock physical owner.');
            end
            ledgerRequired=sixgr.runtime.RuntimeCallLedger.isConfigured();
            if ledgerRequired
                ledger=sixgr.runtime.RuntimeCallLedger.checkpoint(root);
                assert(~isempty(ledger),'sixgr:checkpoint:RuntimeCallLedgerEmpty', ...
                    'A configured production checkpoint requires its actual runtime-call prefix.');
            end
            base=sixgr.runtime.SlotCheckpoint.storageRoot(root);
            if ~isfolder(base), mkdir(base); end
            generation=1;
            if isfile(fullfile(base,'latest.json'))
                previous=jsondecode(fileread(fullfile(base,'latest.json')));
                generation=double(previous.Generation)+1;
            end
            % UUID permits a repaired continuation to checkpoint the same slot
            % without overwriting any prior checkpoint or failed-run evidence.
            folder=fullfile(base,sprintf('after_slot_%06d_%s',slot,char(java.util.UUID.randomUUID)));
            mkdir(folder); mkdir(fullfile(folder,'small_files'));
            records=struct('Path',{},'Bytes',{},'SHA256',{},'Snapshot',{});
            files=dir(fullfile(root,'**','*')); files=files(~[files.isdir]);
            for k=1:numel(files)
                file=fullfile(files(k).folder,files(k).name);
                rel=string(file(numel(root)+2:end));
                if startsWith(replace(rel,'\','/'),'checkpoints/'), continue; end
                localWithinRun(file,root);
                snapshot="";
                % Mutable outputs require versioned recoverable bytes, not
                % a new copy of unchanged bytes for every generation.
                [~,~,extension]=fileparts(file);
                immutableChannel=~isempty(regexp(char(replace(rel,'\','/')), ...
                    '^channel/mat/(channel_observation_|effch_)[a-f0-9]{64}\.mat$','once'));
                immutablePlot=~isempty(regexp(char(replace(rel,'\','/')), ...
                    '^reports/live_measurements/[a-f0-9]{64}/','once'));
                immutableReceiveOnly=~isempty(regexp(char(replace(rel,'\','/')), ...
                    '^air_interface/mat/receive_only_observation_[a-f0-9]{64}\.mat$','once'));
                if files(k).bytes<=1024*1024 || ...
                        (~strcmpi(extension,'.bin') && ~immutableChannel && ~immutablePlot && ~immutableReceiveOnly)
                    [snapshot,hash]=sixgr.runtime.CheckpointFileStore.capture(base,file);
                else
                    % Large IQ/channel files are append-only or immutable.
                    % Keep a verified prefix watermark; never copy gigabytes
                    % at every slot or silently trust a modified dependency.
                    hash=localPrefix(file,files(k).bytes,"");
                end
                records(end+1)=struct('Path',rel,'Bytes',files(k).bytes, ...
                    'SHA256',hash,'Snapshot',snapshot); %#ok<AGROW>
            end
            payload.Scenario=sixgr.runtime.SlotCheckpoint.scientificScenario(scenario);
            payload.FullScenario=scenario;
            % A small exact-type mirror permits a scientific-config reject
            % before deserializing large channel/RF/HARQ handle graphs.
            % It never replaces the comparison against the native payload.
            scenarioPath=fullfile(folder,'scientific_scenario.mat');
            sixgr.util.matSave(scenarioPath,struct('ScientificScenario',payload.Scenario), ...
                'UseArtifactStore',false);
            scenarioHash=sixgr.util.sha256File(scenarioPath);
            path=fullfile(folder,'state.mat');
            % HDF5 cannot reliably serialize directly into a long Windows
            % or synchronised result path. Use the existing byte-validated
            % local serializer; checkpoint state stays filesystem-owned.
            sixgr.util.matSave(path,struct('payload',payload), ...
                'UseArtifactStore',false,'ForceV73',true);
            stateHash=sixgr.util.sha256File(path);
            receipt=struct('SchemaVersion',2,'Status','complete','Generation',generation, ...
                'RunFolder',root,'CompletedSlotOneBased',slot,'NextSlotOneBased',slot+1, ...
                'MATLABVersion',version,'StateSHA256',stateHash,'Source',source, ...
                'ScientificScenarioFile','scientific_scenario.mat', ...
                'ScientificScenarioSHA256',scenarioHash, ...
                'Files',records,'RuntimeCallLedgerRequired',ledgerRequired, ...
                'PrimaryStudyEligible',false, ...
                'EvidenceScope','exact_state_checkpoint_not_performance_qualification');
            sixgr.util.jsonWrite(fullfile(folder,'checkpoint.json'),receipt);
            sixgr.util.jsonWrite(fullfile(base,'latest.json'), ...
                struct('Checkpoint',path,'Generation',generation, ...
                'CompletedSlotOneBased',slot,'NextSlotOneBased',slot+1));
            sixgr.util.jsonWrite(fullfile(root,'meta','latest_slot_checkpoint.json'), ...
                struct('Checkpoint',path,'CompletedSlotOneBased',slot,'NextSlotOneBased',slot+1));
            keep=double(scenario.run_control.runtime_checkpoint_keep);
            sixgr.runtime.SlotCheckpoint.retireOld(base,keep);
        end

        function base=storageRoot(root)
            % Private execution state is outside the published run tree.
            % CSV annotators/materializers must never rewrite a saved prefix
            % or ingest a preserved failed attempt as current measurements.
            root=localCanonical(root);
            [parent,leaf]=fileparts(root);
            base=fullfile(parent,'.checkpoints',leaf);
        end

        function retireOld(base,keep)
            validateattributes(keep,{'double'},{'scalar','integer','>=',2});
            entries=dir(fullfile(base,'after_slot_*')); entries=entries([entries.isdir]);
            entries=entries(arrayfun(@(e)isfile(fullfile(base,e.name,'checkpoint.json')),entries));
            generations=zeros(1,numel(entries));
            for k=1:numel(entries)
                record=jsondecode(fileread(fullfile(base,entries(k).name,'checkpoint.json')));
                generations(k)=double(record.Generation);
            end
            assert(numel(unique(generations))==numel(generations), ...
                'sixgr:checkpoint:DuplicateGeneration','Only one writer may checkpoint a run.');
            [~,order]=sort(generations,'descend'); entries=entries(order);
            for k=keep+1:numel(entries)
                folder=fullfile(base,entries(k).name); localWithin(folder,base);
                assert(~isempty(regexp(entries(k).name, ...
                    '^after_slot_[0-9]{6}_[a-f0-9-]{36}$','once')), ...
                    'sixgr:checkpoint:RetirementPath','Refuse unexpected checkpoint directory.');
                record=jsondecode(fileread(fullfile(folder,'checkpoint.json')));
                record.Status='retired_by_configured_rolling_retention';
                sixgr.util.jsonWrite(fullfile(base,[entries(k).name '_retired.json']),record);
                % Only this writer's generated checkpoint payload is retired.
                % Never remove root-run IQ, logs, or preserved failed attempts.
                rmdir(folder,'s');
            end
        end

        function [payload,receipt] = read(path,scenario,repairReason)
            preflight=sixgr.runtime.SlotCheckpoint.preflightScenario(path,scenario);
            receipt=sixgr.runtime.SlotCheckpoint.verify(path,repairReason);
            % Neither metadata nor the mirror may change between preflight
            % and the full verified state read. Legacy checkpoints continue
            % to use the original exact native-state comparison below.
            if preflight.Available
                assert(isfield(receipt,'ScientificScenarioFile') && ...
                    string(receipt.ScientificScenarioFile)=="scientific_scenario.mat" && ...
                    isfield(receipt,'ScientificScenarioSHA256') && ...
                    string(receipt.ScientificScenarioSHA256)==preflight.SHA256, ...
                    'sixgr:checkpoint:ScenarioPreflightChanged', ...
                    'Checkpoint configuration preflight changed during restore.');
            end
            nativeLoadScope=sixgr.runtime.ExecutionStageProfiler.scope("checkpoint","deserialize_native_state"); %#ok<NASGU>
            saved=sixgr.util.loadVerifiedMAT(string(path), ...
                string(receipt.StateSHA256),"payload");
            payload=saved.payload;
            stream=sixgr.util.structGet(payload,'RuntimeState.SharedWaveformStream',[]);
            if isa(stream,'sixgr.truth.CoupledWaveformStream')
                stream.compactBroadcastContexts();
            end
            assert(isequaln(sixgr.runtime.SlotCheckpoint.scientificScenario(payload.Scenario), ...
                sixgr.runtime.SlotCheckpoint.scientificScenario(scenario)), ...
                'sixgr:checkpoint:ScenarioChanged', ...
                'Scientific configuration changed: restart from slot zero.');
            receipt.RequestedConfigInheritance=sixgr.util.structGet( ...
                scenario,'config_inheritance',struct());
            receipt.ScenarioPreflight=preflight;
            receipt.RequestedOperationalSettings= ...
                sixgr.runtime.SlotCheckpoint.operationalSettings(scenario);
        end

        function evidence = preflightScenario(path,scenario)
            % No state deserialization, runtime mutation, artifact recovery
            % or scientific-config migration. Old receipts remain supported.
            path=localCanonical(path);
            receiptPath=fullfile(fileparts(path),'checkpoint.json');
            assert(isfile(path) && isfile(receiptPath), ...
                'sixgr:checkpoint:Incomplete','No committed state/receipt pair exists at %s.',path);
            receipt=jsondecode(fileread(receiptPath));
            evidence=struct('Available',false,'SHA256',"", ...
                'NativeStateLoaded',false,'Scope',"legacy_native_scenario_check_required");
            fields=isfield(receipt,{'ScientificScenarioFile','ScientificScenarioSHA256'});
            if ~any(fields), return; end
            assert(all(fields) && isscalar(receipt) && ...
                any(receipt.SchemaVersion==[1 2]) && string(receipt.Status)=="complete" && ...
                isscalar(string(receipt.ScientificScenarioFile)) && ...
                string(receipt.ScientificScenarioFile)=="scientific_scenario.mat" && ...
                isscalar(string(receipt.ScientificScenarioSHA256)) && ...
                ~isempty(regexp(char(string(receipt.ScientificScenarioSHA256)), ...
                    '^[a-f0-9]{64}$','once')), ...
                'sixgr:checkpoint:ScenarioPreflightIntegrity', ...
                'The exact scientific configuration mirror needs a valid file and checksum.');
            mirror=fullfile(fileparts(path),'scientific_scenario.mat');
            assert(isfile(mirror) && ...
                string(sixgr.util.sha256File(mirror))==string(receipt.ScientificScenarioSHA256), ...
                'sixgr:checkpoint:ScenarioPreflightIntegrity', ...
                'The scientific configuration mirror is missing or changed.');
            saved=sixgr.util.loadVerifiedMAT(string(mirror), ...
                string(receipt.ScientificScenarioSHA256),"ScientificScenario");
            assert(isequaln(saved.ScientificScenario, ...
                sixgr.runtime.SlotCheckpoint.scientificScenario(scenario)), ...
                'sixgr:checkpoint:ScenarioChanged', ...
                'Scientific configuration changed: restart from slot zero. Native runtime state was not loaded.');
            evidence.Available=true;
            evidence.SHA256=string(receipt.ScientificScenarioSHA256);
            evidence.Scope="verified_exact_config_mirror_not_a_replacement_for_native_state_validation";
        end

        function receipt = verify(path,repairReason)
            % Byte/source checks without native MATLAB object reconstruction.
            verifyScope=sixgr.runtime.ExecutionStageProfiler.scope("checkpoint","verify_state_bytes_and_source"); %#ok<NASGU>
            path=localCanonical(path);
            receiptPath=fullfile(fileparts(path),'checkpoint.json');
            assert(isfile(path) && isfile(receiptPath), ...
                'sixgr:checkpoint:Incomplete','No committed state/receipt pair exists at %s.',path);
            receipt=jsondecode(fileread(receiptPath));
            assert(any(receipt.SchemaVersion==[1 2]) && string(receipt.Status)=="complete" && ...
                string(receipt.StateSHA256)==sixgr.util.sha256File(path), ...
                'sixgr:checkpoint:StateIntegrity','Checkpoint schema/status/hash mismatch.');
            assert(string(receipt.MATLABVersion)==string(version), ...
                'sixgr:checkpoint:MATLABVersion','Restore requires the same MATLAB version.');
            current=sixgr.runtime.SlotCheckpoint.sourceIdentity();
            changed=string(current.SHA256)~=string(receipt.Source.SHA256);
            assert(~changed || strlength(strtrim(string(repairReason)))>0, ...
                'sixgr:checkpoint:SourceChanged', ...
                ['Source changed. Review whether the repair affects prefix state; ' ...
                 'declare runtime_checkpoint_repair_reason for diagnostic replay only.']);
            receipt.RestoredSource=current;
            receipt.SourceChanged=changed;
            receipt.RepairReason=string(repairReason);
            receipt.PrimaryStudyEligible=false;
            receipt.EvidenceScope='checkpoint_continuation_requires_full_source_qualification';
        end

        function [data,metadata] = savedScenarioMetadata(path,expectedState,expectedConfig)
            % Small, immutable checkpoint dependencies only. This does NOT
            % authorize a resume or replace native-state/source validation.
            path=localCanonical(path);
            receiptPath=fullfile(fileparts(path),'checkpoint.json');
            assert(isfile(path)&&isfile(receiptPath), ...
                'sixgr:checkpoint:Incomplete','No completed state/receipt pair exists.');
            receiptHash=string(sixgr.util.sha256File(receiptPath));
            receipt=jsondecode(fileread(receiptPath));
            assert(any(receipt.SchemaVersion==[1 2])&&string(receipt.Status)=="complete"&& ...
                string(receipt.StateSHA256)==string(expectedState), ...
                'sixgr:checkpoint:SavedIdentityMismatch','The selected checkpoint state identity differs from the request.');
            paths=replace(string({receipt.Files.Path}),'\','/');
            names=["meta/scenario_config_resolved.json","meta/scenario_config_identity.json"];
            values=cell(2,1); sources=strings(2,1); hashes=strings(2,1);
            for k=1:2
                idx=find(paths==names(k));
                assert(isscalar(idx),'sixgr:checkpoint:SavedMetadataMissing', ...
                    'Checkpoint must retain exactly one %s.',names(k));
                record=receipt.Files(idx);
                assert(strlength(string(record.Snapshot))>0, ...
                    'sixgr:checkpoint:SavedMetadataMissing','Saved configuration must be an immutable checkpoint version.');
                sources(k)=string(localSource(record,path,receipt.RunFolder));
                info=dir(sources(k));
                assert(isscalar(info)&&info.bytes==record.Bytes&& ...
                    string(sixgr.util.sha256File(sources(k)))==string(record.SHA256), ...
                    'sixgr:checkpoint:SavedMetadataIntegrity','Saved configuration dependency changed: %s.',names(k));
                values{k}=jsondecode(fileread(sources(k))); hashes(k)=string(record.SHA256);
                assert(string(sixgr.util.sha256File(sources(k)))==hashes(k), ...
                    'sixgr:checkpoint:SavedMetadataIntegrity','Saved configuration changed during read.');
            end
            data=values{1}; identity=values{2};
            assert(isstruct(data)&&isscalar(data)&&isstruct(identity)&&isscalar(identity)&& ...
                all(isfield(identity,{'SchemaVersion','ScenarioID','ConfigHash','ResolvedJSONSHA256'}))&& ...
                string(identity.SchemaVersion)=="sixgr_resolved_config_identity/v1"&& ...
                string(identity.ConfigHash)==string(expectedConfig)&& ...
                string(identity.ResolvedJSONSHA256)==hashes(1)&& ...
                string(identity.ScenarioID)==string(sixgr.util.structGet(data,'meta.scenario_id',"")), ...
                'sixgr:checkpoint:SavedIdentityMismatch','Saved scenario identity and immutable configuration disagree.');
            assert(string(sixgr.util.sha256File(receiptPath))==receiptHash, ...
                'sixgr:checkpoint:SavedMetadataChanged','Checkpoint receipt changed during metadata read.');
            metadata=struct('ReceiptSHA256',receiptHash,'ResolvedSource',sources(1), ...
                'ResolvedSHA256',hashes(1),'IdentitySHA256',hashes(2), ...
                'ConfigHash',string(identity.ConfigHash),'StateSHA256',string(receipt.StateSHA256), ...
                'CompletedSlot',double(receipt.CompletedSlotOneBased));
        end

        function [payload,lineage,scenario] = readSavedContinuation(request)
            assert(isa(request,'sixgr.runtime.CheckpointContinuationRequest'), ...
                'sixgr:checkpoint:InvalidContinuationRequest','An explicit saved-configuration request is required.');
            [archived,metadata]=request.verifiedMetadata();
            lineage=sixgr.runtime.SlotCheckpoint.verify(request.Path,request.RepairReason);
            saved=sixgr.util.loadVerifiedMAT(request.Path,string(lineage.StateSHA256),"payload");
            payload=saved.payload;
            assert(all(isfield(payload,{'FullScenario','Scenario','ConfigHash'}))&& ...
                string(payload.ConfigHash)==request.ExpectedConfigHash&& ...
                isequaln(sixgr.runtime.SlotCheckpoint.scientificScenario(payload.FullScenario), ...
                    sixgr.runtime.SlotCheckpoint.scientificScenario(payload.Scenario)), ...
                'sixgr:checkpoint:SavedIdentityMismatch','Native scientific state/configuration identity is inconsistent.');
            % JSON is only the portable comparison plane, never the source
            % of a reconstructed native runtime/config. Its exact bytes were
            % checked above; native FullScenario retains original MATLAB types.
            nativePortable=jsondecode(jsonencode(payload.FullScenario));
            assert(isequaln(sixgr.runtime.SlotCheckpoint.scientificScenario(nativePortable), ...
                sixgr.runtime.SlotCheckpoint.scientificScenario(archived)), ...
                'sixgr:checkpoint:SavedScenarioMismatch', ...
                'Native saved scenario differs from its immutable published configuration.');
            % A mirror, when present, remains an integrity dependency even
            % though this mode takes the scientific values from native state.
            lineage.ScenarioPreflight=sixgr.runtime.SlotCheckpoint.preflightScenario( ...
                request.Path,payload.FullScenario);
            request.verifiedMetadata();
            stream=sixgr.util.structGet(payload,'RuntimeState.SharedWaveformStream',[]);
            if isa(stream,'sixgr.truth.CoupledWaveformStream'), stream.compactBroadcastContexts(); end
            scenario=request.applyOperational(payload.FullScenario);
            % The same exact native scientific comparison used by ordinary
            % YAML resumes still applies. No ignored new scientific fields.
            assert(isequaln(sixgr.runtime.SlotCheckpoint.scientificScenario(payload.Scenario), ...
                sixgr.runtime.SlotCheckpoint.scientificScenario(scenario)), ...
                'sixgr:checkpoint:ScenarioChanged','A continuation cannot change saved science.');
            lineage.RequestedOperationalSettings=sixgr.runtime.SlotCheckpoint.operationalSettings(scenario);
            lineage.RequestedConfigInheritance=sixgr.util.structGet(scenario,'config_inheritance',struct());
            lineage.ConfigurationSource="immutable_checkpoint_native_scenario_no_current_defaults_or_inheritance";
            lineage.SavedConfigurationMetadata=metadata;
            lineage.ContinuationRequestPath=request.RequestPath;
            lineage.ContinuationRequestSHA256=request.RequestSHA256;
            lineage.ExecutionHorizon=request.ExecutionHorizon;
            if ~isempty(fieldnames(request.ExecutionHorizon))
                probe.run.executionHorizon=request.ExecutionHorizon;
                sixgr.runtime.CheckpointExecutionHorizon.assertResume(payload,probe, ...
                    request.ExecutionHorizon.FinishAfterSlot,payload.SNRGrid);
            end
        end

        function [root,lineage,lease] = prepareResume(path,scenario,repairReason,requireRuntimeLedger)
            % Preflight ALL dependencies before moving anything. The old run
            % is retained under checkpoints/recovery_*, never deleted.
            if nargin<4, requireRuntimeLedger=false; end
            validateattributes(requireRuntimeLedger,{'logical'},{'scalar'});
            if requireRuntimeLedger
                recordPath=fullfile(fileparts(localCanonical(path)),'checkpoint.json');
                assert(isfile(recordPath),'sixgr:checkpoint:Incomplete','No checkpoint receipt exists.');
                record=jsondecode(fileread(recordPath));
                paths=replace(string({record.Files.Path}),'\','/');
                assert(any(paths=="reports/csv/runtime_call_ledger.csv"), ...
                    'sixgr:checkpoint:RuntimeCallLedgerNotCheckpointed', ...
                    ['This checkpoint omitted the in-memory runtime-call prefix. ' ...
                     'Restart from a checkpoint containing it or begin a new execution; ' ...
                     'do not reconstruct historical calls or replace the existing run.']);
            end
            stateReadTimer=tic;
            if isa(scenario,'sixgr.runtime.CheckpointContinuationRequest')
                assert(string(localCanonical(path))==scenario.Path&&string(repairReason)==scenario.RepairReason, ...
                    'sixgr:checkpoint:SavedIdentityMismatch','Continuation path and repair declaration must match the request.');
                [saved,lineage,scenario]=sixgr.runtime.SlotCheckpoint.readSavedContinuation(scenario);
            else
                [saved,lineage]=sixgr.runtime.SlotCheckpoint.read(path,scenario,repairReason);
            end
            lineage.ResumePreparationTiming=struct('StateReadAndValidationSeconds',toc(stateReadTimer), ...
                'NativeDeserializations',1,'ExternalDependencyValidationSeconds',NaN, ...
                'ArtifactRestorationSeconds',NaN);
            lineage.CanonicalScenario=saved.FullScenario;
            lineage.CanonicalConfigHash=saved.ConfigHash;
            lease=[];
            % Only the production single-owner handoff retains native state.
            % Two-output legacy/report callers keep their prior memory scope.
            if nargout<3, clear saved; end
            root=localCanonical(lineage.RunFolder);
            archiveStorage=localArchiveStorage(root);
            base=sixgr.runtime.SlotCheckpoint.storageRoot(root);
            localWithin(path,base);
            records=lineage.Files;
            dependencyTimer=tic;
            dependencyScope=sixgr.runtime.ExecutionStageProfiler.scope("checkpoint","verify_external_dependencies");
            for k=1:numel(records)
                source=localSource(records(k),path,root);
                assert(localPrefix(source,records(k).Bytes,"")==string(records(k).SHA256), ...
                    'sixgr:checkpoint:ArtifactIntegrity', ...
                    'Checkpoint dependency was removed or changed: %s.',records(k).Path);
            end
            clear dependencyScope
            lineage.ResumePreparationTiming.ExternalDependencyValidationSeconds=toc(dependencyTimer);
            restorationTimer=tic;
            restorationScope=sixgr.runtime.ExecutionStageProfiler.scope("checkpoint","restore_artifact_prefix"); %#ok<NASGU>
            history=fullfile(base, ...
                ['recovery_' char(java.util.UUID.randomUUID)]);
            staging=fullfile(base,['restore_' char(java.util.UUID.randomUUID)]);
            localWithin(history,base); localWithin(staging,base); mkdir(staging);
            externalRestore="";
            if ~isempty(archiveStorage)
                % Each restored view has its own directory inventory, while
                % unchanged immutable MAT bytes can share same-volume links.
                % The preserved attempt never acquires later run files.
                [archiveParent,archiveLeaf]=fileparts(archiveStorage.ExternalFolder);
                externalRestore=fullfile(archiveParent, ...
                    archiveLeaf+"_restore_"+string(java.util.UUID.randomUUID));
                localWithin(externalRestore,archiveParent);
                assert(~isfolder(externalRestore),'sixgr:checkpoint:ExternalArchiveExists');
                mkdir(externalRestore);
            end
            for k=1:numel(records)
                target=fullfile(staging,records(k).Path); localWithin(target,staging);
                source=localSource(records(k),path,root);
                relative=replace(string(records(k).Path),'\','/');
                if strlength(externalRestore)>0 && startsWith(relative,"channel/mat/")
                    name=extractAfter(relative,"channel/mat/");
                    assert(~contains(name,["/","\"]) && endsWith(name,".mat"), ...
                        'sixgr:checkpoint:ExternalArchivePath','Only flat MAT archives may use this route.');
                    target=fullfile(externalRestore,name); localWithin(target,externalRestore);
                end
                parent=fileparts(target); if ~isfolder(parent), mkdir(parent); end
                hash=localRestoreFile(source,records(k),target);
                assert(hash==string(records(k).SHA256), ...
                    'sixgr:checkpoint:RestoreIntegrity','Restored prefix hash mismatch.');
            end
            if strlength(externalRestore)>0
                localBindRestoredArchives(staging,root,externalRestore,records,archiveStorage);
            end
            % The complete replacement exists and is verified before the
            % original directory is moved. Both names are on the same volume.
            % On a failed second rename, put the untouched original back.
            localWithin(root,fileparts(root));
            movefile(root,history);
            try
                movefile(staging,root);
            catch cause
                if ~isfolder(root), movefile(history,root); end
                rethrow(cause);
            end
            lineage.PreservedFailedAttempt=history;
            lineage.Checkpoint=localCanonical(path);
            lineage.ResumePreparationTiming.ArtifactRestorationSeconds=toc(restorationTimer);
            sixgr.util.jsonWrite(fullfile(root,'meta','checkpoint_resume.json'),lineage);
            sixgr.util.jsonWrite(fullfile(root,'meta','latest_slot_checkpoint.json'), ...
                struct('Checkpoint',lineage.Checkpoint, ...
                'CompletedSlotOneBased',lineage.CompletedSlotOneBased, ...
                'NextSlotOneBased',lineage.NextSlotOneBased));
            if nargout>=3
                lease=sixgr.runtime.CheckpointResumeLease(path,saved,lineage);
            end
        end
    end
end

function path=localCanonical(path)
path=char(java.io.File(char(path)).getCanonicalPath());
end

function localWithin(path,root)
path=string(localCanonical(path)); root=string(localCanonical(root));
assert(startsWith(lower(path),lower(root+filesep)), ...
    'sixgr:checkpoint:PathEscape','Checkpoint path escapes its exact run root: %s.',path);
end

function path=localSource(record,checkpoint,root)
if startsWith(string(record.Snapshot),"@objects/")
    path=sixgr.runtime.CheckpointFileStore.resolve(fileparts(fileparts(checkpoint)),record.Snapshot);
elseif strlength(string(record.Snapshot))>0
    root=fileparts(checkpoint); path=fullfile(root,record.Snapshot);
    localWithin(path,root);
else
    path=fullfile(root,record.Path);
    localWithinRun(path,root);
end
end

function hash=localRestoreFile(source,record,target)
relative=replace(string(record.Path),'\','/');
immutable=~isempty(regexp(char(relative), ...
    '^channel/mat/(channel_observation_|effch_)[a-f0-9]{64}\.mat$','once')) || ...
    ~isempty(regexp(char(relative),'^reports/live_measurements/[a-f0-9]{64}/','once')) || ...
    ~isempty(regexp(char(relative), ...
    '^air_interface/mat/receive_only_observation_[a-f0-9]{64}\.mat$','once'));
info=dir(source);
if immutable && info.bytes==record.Bytes
    % No mutable primary CSV, append-only IQ stream or state file is linked.
    try
        java.nio.file.Files.createLink(java.io.File(char(target)).toPath(), ...
            java.io.File(char(source)).toPath());
        linked=true;
    catch cause
        if isfile(target), rethrow(cause); end
        linked=false; % unsupported/cross-volume filesystems get exact copies
    end
    if linked
        hash=localPrefix(target,record.Bytes,"");
        return;
    end
end
hash=localPrefix(source,record.Bytes,target);
end

function record=localArchiveStorage(root)
record=[];
receiptPath=fullfile(root,'meta','channel_archive_storage.json');
if ~isfile(receiptPath), return; end
record=jsondecode(fileread(receiptPath));
required={'Contract','Status','RunFolder','LogicalRelativeFolder','ExternalFolder', ...
    'ScientificDataChanged','SourceCodeMoved'};
assert(all(isfield(record,required)) && ...
    string(record.Contract)=="LLSExternalChannelArchive/v1" && ...
    string(record.Status)=="verified" && ...
    strcmpi(localCanonical(record.RunFolder),localCanonical(root)) && ...
    string(record.LogicalRelativeFolder)=="channel/mat" && ...
    ~record.ScientificDataChanged && ~record.SourceCodeMoved, ...
    'sixgr:checkpoint:ExternalArchiveIdentity','Invalid declared external archive ownership.');
external=string(localCanonical(record.ExternalFolder));
assert(ispc && isfolder(external) && ~isempty(fileparts(external)) && ...
    strlength(external)>3 && ~startsWith(lower(external),lower(string(root)+filesep)) && ...
    ~startsWith(lower(string(root)),lower(external+filesep)) && ...
    lower(external)~=lower(string(root)), ...
    'sixgr:checkpoint:ExternalArchiveIdentity','External storage must be a disjoint existing directory.');
logical=fullfile(root,'channel','mat');
assert(isfolder(logical) && java.nio.file.Files.isSameFile( ...
    java.io.File(char(logical)).toPath(),java.io.File(char(external)).toPath()), ...
    'sixgr:checkpoint:ExternalArchiveIdentity','The visible archive route does not match its receipt.');
record.ExternalFolder=external;
end

function localWithinRun(path,root)
% Only the explicitly installed, verified archive route may leave run storage.
relative=string(path);
logicalRoot=string(root)+filesep;
if startsWith(lower(relative),lower(logicalRoot))
    relative=extractAfter(relative,strlength(logicalRoot));
else
    localWithin(path,root);
    return;
end
relative=replace(relative,'\','/');
if startsWith(relative,"channel/mat/")
    storage=localArchiveStorage(root);
    if ~isempty(storage)
        name=extractAfter(relative,"channel/mat/");
        assert(~contains(name,["/","\"]) && endsWith(name,".mat"), ...
            'sixgr:checkpoint:ExternalArchivePath','Only flat MAT dependencies may leave the run root.');
        expected=fullfile(storage.ExternalFolder,name);
        localWithin(expected,storage.ExternalFolder);
        assert(~java.nio.file.Files.isSymbolicLink(java.io.File(char(expected)).toPath()) && ...
            java.nio.file.Files.isSameFile(java.io.File(char(path)).toPath(), ...
                java.io.File(char(expected)).toPath()), ...
            'sixgr:checkpoint:ExternalArchiveIdentity','Archive target differs from the explicit storage owner.');
        return;
    end
end
localWithin(path,root);
end

function localBindRestoredArchives(staging,root,external,records,previous)
logical=fullfile(staging,'channel','mat');
assert(~isfolder(logical),'sixgr:checkpoint:ExternalArchiveExists');
parent=fileparts(logical); if ~isfolder(parent), mkdir(parent); end
% Use the same PowerShell 7 host as archive relocation. Windows PowerShell
% 5.1 New-Item rejects valid checkpoint staging paths beyond MAX_PATH.
% One native operation; no shell-built delete/move or shortened owner path.
quotedPath=replace(string(logical),"'","''");
quotedTarget=replace(string(external),"'","''");
command="pwsh.exe -NoProfile -NonInteractive -Command "+char(34)+ ...
    "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path '"+ ...
    quotedPath+"' -Target '"+quotedTarget+"' | Out-Null"+char(34);
[status,message]=system(command);
assert(status==0 && java.nio.file.Files.isSameFile( ...
    java.io.File(char(logical)).toPath(),java.io.File(char(external)).toPath()), ...
    'sixgr:checkpoint:ExternalArchiveJunction','Archive route creation failed: %s',message);
files=struct('Name',{},'Bytes',{},'SHA256',{});
for k=1:numel(records)
    relative=replace(string(records(k).Path),'\','/');
    if ~startsWith(relative,"channel/mat/"), continue; end
    name=extractAfter(relative,"channel/mat/");
    assert(localPrefix(fullfile(logical,name),records(k).Bytes,"")==string(records(k).SHA256), ...
        'sixgr:checkpoint:RestoreIntegrity','Visible external archive hash mismatch.');
    files(end+1)=struct('Name',name,'Bytes',records(k).Bytes, ... %#ok<AGROW>
        'SHA256',records(k).SHA256);
end
receipt=struct('Contract','LLSExternalChannelArchive/v1','Status','verified', ...
    'RunFolder',root,'LogicalRelativeFolder','channel/mat','ExternalFolder',external, ...
    'FileCount',numel(files),'Bytes',sum([files.Bytes]),'Files',files, ...
    'ScientificDataChanged',false,'SourceCodeMoved',false, ...
    'PreviousExternalFolder',previous.ExternalFolder, ...
    'RestoreMethod','verified_immutable_links_or_exact_byte_copy');
sixgr.util.jsonWrite(fullfile(staging,'meta','channel_archive_storage.json'),receipt);
end

function hash=localPrefix(path,count,destination)
hashScope=sixgr.runtime.ExecutionStageProfiler.scope("hashing","checkpoint_prefix_readback"); %#ok<NASGU>
assert(isfile(path),'sixgr:checkpoint:MissingArtifact','Missing checkpoint dependency: %s.',path);
info=dir(path);
assert(info.bytes>=count,'sixgr:checkpoint:ShortArtifact','Truncated checkpoint dependency: %s.',path);
input=java.io.FileInputStream(java.io.File(char(path)));
inputGuard=onCleanup(@()input.close()); %#ok<NASGU>
in=input.getChannel(); digest=java.security.MessageDigest.getInstance('SHA-256');
buffer=java.nio.ByteBuffer.allocate(1024*1024);
if strlength(string(destination))>0
    output=java.io.FileOutputStream(java.io.File(char(destination)));
    outputGuard=onCleanup(@()output.close()); %#ok<NASGU>
    out=output.getChannel();
end
left=double(count);
while left>0
    buffer.clear(); buffer.limit(int32(min(left,buffer.capacity())));
    n=in.read(buffer); assert(n>0,'sixgr:checkpoint:ReadFailed','Short prefix read.');
    buffer.flip(); digest.update(buffer.asReadOnlyBuffer());
    if strlength(string(destination))>0
        while buffer.hasRemaining(), out.write(buffer); end
    end
    left=left-double(n);
end
hash=lower(string(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[])));
end
