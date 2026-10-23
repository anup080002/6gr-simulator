function artifact=publishRFEndpointExecutionLedger(cfg,airFolder,raw)
% Publish the compact production-owner record, or verify its retained file.
% No channel-observation reconstruction and no hardware-state inference.
layout=sixgr.report.resultLayout(fileparts(char(string(airFolder))));
csvPath=string(fullfile(layout.RFCSVDir,'rf_endpoint_execution_intervals.csv'));
metaPath=string(fullfile(layout.RFCSVDir,'rf_endpoint_execution_manifest.json'));
coveragePath=string(fullfile(layout.RFCSVDir,'rf_endpoint_execution_coverage.csv'));
chainPath=string(fullfile(layout.RFCSVDir,'rf_endpoint_chain_power_intervals.csv'));
spatialPath=string(fullfile(layout.RFCSVDir,'rf_endpoint_tx_spatial_power_intervals.csv'));
radiationPath=string(fullfile(layout.RFCSVDir,'rf_endpoint_modeled_radiation_intervals.csv'));
fieldPath=string(fullfile(layout.RFDir,'mat','rf_endpoint_radiation_fields.mat'));
nativePath=string(fullfile(layout.RFDir,'mat','rf_endpoint_radiation_native_bindings.mat'));
artifact=struct('Available',false,'CSV',"",'Manifest',"",'CoverageCSV',"", ...
    'ChainPowerCSV',"",'TXSpatialPowerCSV',"",'ModeledRadiationCSV',"",'RadiationFieldMAT',"", ...
    'Evidence',[],'PhysicalReplayExecuted',false,'HardwareOperatingStateAvailable',false);
owner=sixgr.util.structGet(raw,'CoupledRuntime.SharedWaveformStream',[]);
e=sixgr.util.structGet(raw,'RFEndpointExecutionEvidence',[]);
if isa(owner,'sixgr.truth.CoupledWaveformStream')
    live=owner.Physical.readRFExecutionLedger();
    assert(isempty(e)||isequaln(e,live),'sixgr:truth:RFExecutionOwnerMismatch', ...
        'Portable RF execution evidence disagrees with its retained runtime owner.');
    e=live;
end
if ~isempty(e)
    T=sixgr.truth.bindCoupledExecutionIdentity(e.Intervals,cfg,"RF_ENDPOINT_EXECUTION");
    coverage=sixgr.truth.RFEndpointExecutionLedger.validate(e);
    chain=sixgr.util.structGet(e,'ChainPowerIntervals',sixgr.truth.rfChainPowerInterval());
    chainComplete=sixgr.truth.validateRFChainPowerIntervals(chain,e.Intervals);
    spatial=sixgr.util.structGet(e,'TXSpatialPowerIntervals',sixgr.truth.rfTXSpatialPowerInterval());
    spatialComplete=sixgr.truth.validateTXSpatialPowerIntervals(spatial,e.Intervals,chain);
    localCheckSpatialCompleteness(e,cfg,spatialComplete);
    [radiation,library,native,radiationComplete]=localRadiationEvidence(e,cfg,spatial);
    % Configuration/lifecycle identity accompanies producer clock identity.
    meta=rmfield(e,intersect(fieldnames(e),{'Intervals','Coverage','ChainPowerIntervals','TXSpatialPowerIntervals', ...
        'TXRadiationIntervals','TXRadiationLibrary','TXRadiationNativeBindings'}));
    meta.Inventory=table2struct(e.Inventory);
    meta.ConfigHash=string(sixgr.util.structGet(cfg,'meta.configHash',""));
    meta.ExecutionID=string(sixgr.util.structGet(cfg,'run.executionID', ...
        sixgr.util.structGet(cfg,'meta.executionID',"")));
    meta.Scope="all_committed_RF_operator_intervals_since_recording_origin_not_hardware_power_states";
    meta.HardwareOperatingStateAvailable=false;
    meta.BSPowerReference=sixgr.util.structGet(cfg,'rf.bsPowerReference',struct());
    e.Intervals=T;
    sixgr.util.csvWriteTable(csvPath,T,'PreserveSchema',true,'RoundTripNumericText',true);
    meta.IntervalFileSHA256=string(sixgr.util.sha256File(csvPath));
    sixgr.util.csvWriteTable(coveragePath,coverage,'PreserveSchema',true,'RoundTripNumericText',true);
    meta.ChainPowerCompleteFromOrigin=chainComplete;
    if ~isempty(chain)
        chain=sixgr.truth.bindCoupledExecutionIdentity(chain,cfg,"RF_CHAIN_POWER");
        sixgr.util.csvWriteTable(chainPath,chain,'PreserveSchema',true,'RoundTripNumericText',true);
        meta.ChainPowerFileSHA256=string(sixgr.util.sha256File(chainPath));
    end
    e.ChainPowerIntervals=chain;
    e.ChainPowerCompleteFromOrigin=meta.ChainPowerCompleteFromOrigin;
    meta.TXSpatialPowerCompleteFromOrigin=spatialComplete;
    if ~isempty(spatial)
        spatial=sixgr.truth.bindCoupledExecutionIdentity(spatial,cfg,"RF_TX_SPATIAL_POWER");
        sixgr.util.csvWriteTable(spatialPath,spatial,'PreserveSchema',true,'RoundTripNumericText',true);
        meta.TXSpatialPowerFileSHA256=string(sixgr.util.sha256File(spatialPath));
    end
    e.TXSpatialPowerIntervals=spatial;
    e.TXSpatialPowerCompleteFromOrigin=spatialComplete;
    meta.ModeledRadiationCompleteFromOrigin=radiationComplete;
    if ~isempty(library)
        % Immutable large arrays are written only once, not repeated in each
        % interval, report refresh, JSON manifest or receiver observation.
        if isfile(fieldPath)
            stored=load(fieldPath,'Library');
            assert(isfield(stored,'Library')&&isequaln(stored.Library,library), ...
                'sixgr:truth:RadiationFieldArchiveChanged','Never overwrite a different installed field.');
        else
            sixgr.util.matSave(fieldPath,struct('Library',library),'UseArtifactStore',false);
        end
        sixgr.util.matSave(nativePath,struct('NativeBindings',native),'UseArtifactStore',false);
        radiation=sixgr.truth.bindCoupledExecutionIdentity(radiation,cfg,"MODELED_TX_RADIATION");
        sixgr.util.csvWriteTable(radiationPath,radiation,'PreserveSchema',true,'RoundTripNumericText',true);
        meta.RadiationFieldFileSHA256=string(sixgr.util.sha256File(fieldPath));
        meta.RadiationNativeBindingsFileSHA256=string(sixgr.util.sha256File(nativePath));
        meta.ModeledRadiationFileSHA256=string(sixgr.util.sha256File(radiationPath));
        meta.RadiationScope="executed_post_TX_RF_covariance_local_frequency_flat_native_field_model_not_accepted_feed_or_hardware";
    end
    e.TXRadiationIntervals=radiation; e.TXRadiationLibrary=library; e.TXRadiationNativeBindings=native;
    e.ModeledRadiationCompleteFromOrigin=radiationComplete;
    sixgr.util.jsonWrite(metaPath,meta);
elseif isfile(metaPath)
    % Terminal/report-only execution must read the exact committed record,
    % never silently substitute the smaller receiver observation union.
    meta=sixgr.util.jsonRead(metaPath);
    assert(isfile(csvPath)&&string(sixgr.util.sha256File(csvPath))==string(meta.IntervalFileSHA256), ...
        'sixgr:truth:RFExecutionFileHash','Retained RF execution CSV is missing or changed.');
    assert(string(meta.ConfigHash)==string(sixgr.util.structGet(cfg,'meta.configHash',"")) && ...
        string(meta.ExecutionID)==string(sixgr.util.structGet(cfg,'run.executionID', ...
        sixgr.util.structGet(cfg,'meta.executionID',""))), ...
        'sixgr:truth:RFExecutionFileScope','Retained RF execution belongs to a different configuration or execution.');
    e=meta; e.Inventory=struct2table(meta.Inventory);
    for field=["EndpointID","Role","Direction"], e.Inventory.(field)=string(e.Inventory.(field)); end
    prototype=sixgr.truth.RFEndpointExecutionLedger.emptyTable(); types=struct();
    for field=string(prototype.Properties.VariableNames)
        types.(field)=class(prototype.(field));
    end
    e.Intervals=sixgr.util.csvReadTable(csvPath,'TextType','string','ColumnTypes',types);
    assert(string(sixgr.util.sha256File(csvPath))==string(meta.IntervalFileSHA256), ...
        'sixgr:truth:RFExecutionFileHash','Retained RF execution changed during read.');
    e.Coverage=sixgr.truth.RFEndpointExecutionLedger.validate(e);
    e.CompleteFromOrigin=~isempty(e.Coverage)&&all(e.Coverage.CompleteFromOrigin);
    e.CompleteFromSampleZero=e.CompleteFromOrigin&&e.OriginSample==0;
    e.HardwareOperatingStateAvailable=false;
    e.ChainPowerIntervals=sixgr.truth.rfChainPowerInterval();
    if isfield(meta,'ChainPowerFileSHA256')
        assert(isfile(chainPath)&&string(sixgr.util.sha256File(chainPath))==string(meta.ChainPowerFileSHA256), ...
            'sixgr:truth:RFChainPowerFileHash','Retained chain-power CSV is missing or changed.');
        prototype=sixgr.truth.rfChainPowerInterval(); types=struct();
        for field=string(prototype.Properties.VariableNames), types.(field)=class(prototype.(field)); end
        e.ChainPowerIntervals=sixgr.util.csvReadTable(chainPath,'TextType','string','ColumnTypes',types);
        % CSV empty text is imported as missing string; the producer's
        % schema uses empty string for inapplicable text, never a number.
        for field=string(prototype.Properties.VariableNames)
            if isstring(prototype.(field))
                values=e.ChainPowerIntervals.(field); values(ismissing(values))="";
                e.ChainPowerIntervals.(field)=values;
            end
        end
        assert(string(sixgr.util.sha256File(chainPath))==string(meta.ChainPowerFileSHA256), ...
            'sixgr:truth:RFChainPowerFileHash','Chain-power CSV changed during read.');
    end
    e.ChainPowerCompleteFromOrigin=sixgr.truth.validateRFChainPowerIntervals(e.ChainPowerIntervals,e.Intervals);
    e.TXSpatialPowerIntervals=sixgr.truth.rfTXSpatialPowerInterval();
    if isfield(meta,'TXSpatialPowerFileSHA256')
        assert(isfile(spatialPath) && ...
            string(sixgr.util.sha256File(spatialPath))==string(meta.TXSpatialPowerFileSHA256), ...
            'sixgr:truth:TXSpatialPowerFileHash','Retained TX spatial-power CSV is missing or changed.');
        prototype=sixgr.truth.rfTXSpatialPowerInterval(); types=struct();
        for field=string(prototype.Properties.VariableNames), types.(field)=class(prototype.(field)); end
        e.TXSpatialPowerIntervals=sixgr.util.csvReadTable(spatialPath,'TextType','string','ColumnTypes',types);
        assert(string(sixgr.util.sha256File(spatialPath))==string(meta.TXSpatialPowerFileSHA256), ...
            'sixgr:truth:TXSpatialPowerFileHash','TX spatial power changed during read.');
    end
    spatialComplete=sixgr.truth.validateTXSpatialPowerIntervals( ...
        e.TXSpatialPowerIntervals,e.Intervals,e.ChainPowerIntervals);
    localCheckSpatialCompleteness(meta,cfg,spatialComplete);
    e.TXSpatialPowerCompleteFromOrigin=spatialComplete;
    e.TXRadiationIntervals=sixgr.truth.modeledRadiationInterval();
    e.TXRadiationLibrary=struct('Installation',{},'Field',{});
    e.TXRadiationNativeBindings=struct('LinkID',{},'Receipt',{});
    if isfield(meta,'RadiationFieldFileSHA256')
        paths=[fieldPath,nativePath,radiationPath];
        names=["RadiationFieldFileSHA256","RadiationNativeBindingsFileSHA256","ModeledRadiationFileSHA256"];
        for k=1:numel(paths)
            assert(isfile(paths(k))&&isfield(meta,names(k))&& ...
                string(sixgr.util.sha256File(paths(k)))==string(meta.(names(k))), ...
                'sixgr:truth:ModeledRadiationFileHash','Original field/native/interval artifact is missing or changed.');
        end
        stored=load(fieldPath,'Library'); original=load(nativePath,'NativeBindings');
        e.TXRadiationLibrary=stored.Library; e.TXRadiationNativeBindings=original.NativeBindings;
        prototype=sixgr.truth.modeledRadiationInterval(); types=struct();
        for name=string(prototype.Properties.VariableNames), types.(name)=class(prototype.(name)); end
        e.TXRadiationIntervals=sixgr.util.csvReadTable(radiationPath,'TextType','string','ColumnTypes',types);
        for k=1:numel(paths)
            assert(string(sixgr.util.sha256File(paths(k)))==string(meta.(names(k))), ...
                'sixgr:truth:ModeledRadiationFileHash','Radiation artifacts changed during read.');
        end
    end
    [~,~,~,e.ModeledRadiationCompleteFromOrigin]=localRadiationEvidence(e,cfg,e.TXSpatialPowerIntervals);
end
if isempty(e), return; end
artifact.Available=~isempty(e.Intervals); artifact.CSV=csvPath;
artifact.Manifest=metaPath; artifact.CoverageCSV=coveragePath; artifact.Evidence=e;
if isfield(e,'ChainPowerIntervals') && ~isempty(e.ChainPowerIntervals), artifact.ChainPowerCSV=chainPath; end
if isfield(e,'TXSpatialPowerIntervals') && ~isempty(e.TXSpatialPowerIntervals)
    artifact.TXSpatialPowerCSV=spatialPath;
end
if isfield(e,'TXRadiationLibrary')&&~isempty(e.TXRadiationLibrary)
    artifact.ModeledRadiationCSV=radiationPath; artifact.RadiationFieldMAT=fieldPath;
end
end

function [T,library,native,complete]=localRadiationEvidence(e,cfg,spatial)
T=sixgr.util.structGet(e,'TXRadiationIntervals',sixgr.truth.modeledRadiationInterval());
library=sixgr.util.structGet(e,'TXRadiationLibrary',struct('Installation',{},'Field',{}));
native=sixgr.util.structGet(e,'TXRadiationNativeBindings',struct('LinkID',{},'Receipt',{}));
complete=sixgr.truth.validateModeledRadiationIntervals(T,library,e.Intervals,spatial,native);
if isfield(e,'ModeledRadiationCompleteFromOrigin')
    assert(isequal(logical(e.ModeledRadiationCompleteFromOrigin),complete), ...
        'sixgr:truth:ModeledRadiationCompleteness','Declared coverage disagrees with actual original intervals.');
end
if logical(sixgr.util.structGet(cfg,'rf.modeledRadiatedPower.Enabled',false))&&e.EndSampleExclusive>e.OriginSample
    if istable(e.Inventory), inventory=e.Inventory; else, inventory=struct2table(e.Inventory); end
    assert(complete&&numel(library)==nnz(string(inventory.Role)=="TX"), ...
        'sixgr:truth:ModeledRadiationCompleteness','Every enabled TX must retain field and full actual interval evidence.');
end
end

function localCheckSpatialCompleteness(e,cfg,measuredComplete)
if isfield(e,'TXSpatialPowerCompleteFromOrigin')
    declared=e.TXSpatialPowerCompleteFromOrigin;
    assert(isscalar(declared) && any(declared==[0 1]) && logical(declared)==measuredComplete, ...
        'sixgr:truth:TXSpatialPowerCompleteness','Declared spatial-power coverage disagrees with actual TX intervals.');
end
if istable(e.Inventory), roles=string(e.Inventory.Role);
else, roles=string({e.Inventory.Role}); end
if logical(sixgr.util.structGet(cfg,'rf.txSpatialPowerEnabled',false)) && ...
        e.EndSampleExclusive>e.OriginSample && any(roles=="TX")
    assert(measuredComplete,'sixgr:truth:TXSpatialPowerCompleteness', ...
        'Enabled spatial-power measurement must retain every committed TX interval; no diagonal-power fallback.');
end
end
