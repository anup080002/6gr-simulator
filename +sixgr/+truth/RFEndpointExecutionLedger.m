classdef RFEndpointExecutionLedger < handle
    % Compact record of committed RF execution, independent of RX observers.
    % RF operator execution is NOT a hardware TX/RX/idle/sleep decision.
    % No IQ, per-sample converter arrays, RNG draws or repeated hashes here.
    properties (SetAccess=private)
        SampleRateHz
        OriginSample
        NextSampleIndex
        ConfigurationEpoch
        Inventory
        Rows
        ProducerSHA256
        ChainPowerRows table = table()
        TXSpatialPowerRows table = table()
        TXRadiationLibrary = struct('Installation',{},'Field',{})
        TXRadiationNativeBindings = struct('LinkID',{},'Receipt',{})
        TXRadiationRows table = table()
        TXLinearReferenceLibrary = struct([])
        TXLinearReferenceIntervals table = table()
        TXLinearReferenceLibraryInstalled (1,1) logical = false
    end
    methods
        function installTXLinearReferenceLibrary(obj,library)
            assert(isempty(obj.Rows)&&obj.NextSampleIndex==obj.OriginSample&& ...
                ~obj.TXLinearReferenceLibraryInstalled,'sixgr:truth:TXLinearReferenceInstallation', ...
                'Freeze the model owner library once, before any committed interval.');
            empty=sixgr.truth.txLinearReferenceInterval();
            sixgr.truth.validateTXLinearReferenceIntervals(empty,library,obj.Rows);
            for k=1:numel(library)
                a=library(k); at=obj.Inventory.Role=="TX"&obj.Inventory.EndpointID==string(a.EndpointID);
                assert(nnz(at)==1&&obj.Inventory.PhysicalPortCount(at)==a.NumAntennas&& ...
                    obj.Inventory.Direction(at)==string(a.Direction)&&a.SampleRateHz==obj.SampleRateHz&& ...
                    a.ConfigurationEpoch==obj.ConfigurationEpoch&&a.OriginSample==obj.OriginSample, ...
                    'sixgr:truth:TXLinearReferenceInstallation','Bind the original registered TX endpoint and model-history origin.');
            end
            obj.TXLinearReferenceLibrary=library; obj.TXLinearReferenceIntervals=empty;
            obj.TXLinearReferenceLibraryInstalled=true;
        end
        function installRadiationLibrary(obj,library)
            assert(isempty(obj.Rows)&&obj.NextSampleIndex==obj.OriginSample&&isempty(obj.TXRadiationLibrary), ...
                'sixgr:truth:ModeledRadiationInstallation','Freeze the field library before the first committed interval.');
            empty=sixgr.truth.modeledRadiationInterval();
            sixgr.truth.validateModeledRadiationIntervals(empty,library,obj.Rows, ...
                sixgr.truth.rfTXSpatialPowerInterval(),obj.TXRadiationNativeBindings);
            for k=1:numel(library)
                a=library(k).Installation;
                at=obj.Inventory.Role=="TX"&obj.Inventory.EndpointID==string(a.TransmitterID);
                assert(nnz(at)==1&&obj.Inventory.PhysicalPortCount(at)==a.PhysicalChainCount&& ...
                    obj.Inventory.Direction(at)==string(a.Direction)&&a.SampleRateHz==obj.SampleRateHz&& ...
                    a.PhysicalConfigurationEpoch==obj.ConfigurationEpoch&&a.RFStreamOriginSample<=obj.OriginSample, ...
                    'sixgr:truth:ModeledRadiationInstallation','Field library must belong to original registered TX owners.');
            end
            obj.TXRadiationLibrary=library; obj.TXRadiationRows=empty;
        end
        function obj=RFEndpointExecutionLedger(fs,first,epoch,inventory)
            validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
            validateattributes(first,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            validateattributes(epoch,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            assert(istable(inventory) && ~isempty(inventory) && ...
                all(ismember({'EndpointID','Role','Direction','PhysicalPortCount'},inventory.Properties.VariableNames)), ...
                'sixgr:truth:RFExecutionInventory','Declare the actual registered RF endpoints.');
            ids=string(inventory.EndpointID); roles=string(inventory.Role);
            assert(all(~ismissing(ids)&strlength(ids)>0) && ...
                all(ismember(roles,["TX","RX"])) && ...
                all(ismember(string(inventory.Direction),["DL","UL"])) && ...
                numel(unique(roles+"|"+ids))==height(inventory), ...
                'sixgr:truth:RFExecutionInventory','RF endpoint identities and roles must be unique and explicit.');
            validateattributes(inventory.PhysicalPortCount,{'numeric'}, ...
                {'real','finite','integer','positive'});
            inventory.EndpointID=ids; inventory.Role=roles;
            inventory.Direction=string(inventory.Direction);
            obj.SampleRateHz=double(fs); obj.OriginSample=double(first);
            obj.NextSampleIndex=double(first); obj.ConfigurationEpoch=double(epoch);
            obj.Inventory=inventory; obj.Rows=sixgr.truth.RFEndpointExecutionLedger.emptyTable();
            obj.ProducerSHA256=string(sixgr.util.sha256File(mfilename('fullpath')+".m"));
        end

        function append(obj,execution)
            assert(isstruct(execution) && isscalar(execution) && ...
                all(isfield(execution,{'StartSample','EndSampleExclusive','TX','RX'})), ...
                'sixgr:truth:RFExecutionClock','A completed physical execution interval is required.');
            first=double(execution.StartSample); stop=double(execution.EndSampleExclusive);
            assert(isscalar(first)&&first==obj.NextSampleIndex && isscalar(stop) && ...
                isfinite(stop)&&stop==fix(stop)&&stop>first, ...
                'sixgr:truth:RFExecutionClock','RF execution intervals must be contiguous and committed exactly once.');
            next=sixgr.truth.RFEndpointExecutionLedger.emptyTable();
            nextPower=sixgr.truth.rfChainPowerInterval();
            nextSpatial=sixgr.truth.rfTXSpatialPowerInterval();
            nextRadiation=sixgr.truth.modeledRadiationInterval();
            nextLinear=sixgr.truth.txLinearReferenceInterval();
            native=obj.TXRadiationNativeBindings;
            links=sixgr.util.structGet(execution,'Links',struct('ID',{},'TX',{},'Replay',{}));
            for link=links
                if ~isfield(link.Replay,'TXRadiationInstallation'), continue; end
                receipt=link.Replay.TXRadiationInstallation;
                assert(string(receipt.TransmitterID)==string(link.TX)&& ...
                    string(receipt.StateKey)==string(link.Replay.RuntimeChannelStateKey)&& ...
                    link.Replay.RuntimeChannelStartSample==first&& ...
                    link.Replay.RuntimeChannelEndSample==stop, ...
                    'sixgr:truth:ModeledRadiationClosure','Native binding belongs to the executed link transmitter.');
                found=find(arrayfun(@(x)string(x.Receipt.ReceiptSHA256)==string(receipt.ReceiptSHA256),native));
                if isempty(found)
                    native(end+1)=struct('LinkID',string(link.ID),'Receipt',receipt); %#ok<AGROW>
                else
                    assert(isscalar(found)&&string(native(found).LinkID)==string(link.ID)&& ...
                        isequaln(native(found).Receipt,receipt),'sixgr:truth:ModeledRadiationClosure', ...
                        'A native installation receipt cannot be reused for another link.');
                end
            end
            for role=["TX","RX"]
                entries=execution.(role); actual=string({entries.ID});
                expected=string(obj.Inventory.EndpointID(obj.Inventory.Role==role));
                assert(numel(actual)==numel(expected) && numel(unique(actual))==numel(actual) && ...
                    all(ismember(expected,actual)),'sixgr:truth:RFExecutionEndpointCoverage', ...
                    'Every registered endpoint must execute once, including zero-input intervals.');
                for k=1:numel(entries)
                    inv=obj.Inventory(obj.Inventory.Role==role & obj.Inventory.EndpointID==actual(k),:);
                    r=entries(k).Replay;
                    required={'RFEndpoint','RFProcessingMode','RFStreamStartSample', ...
                        'RFStreamEndSampleExclusive','RFConfigurationEpoch','RFStrictOk', ...
                        'RFInputPower','RFOutputPower','RFInputAllZero','RFInputWaveformSHA256','RFOutputWaveformSHA256', ...
                        'RFConfiguredStageCount','RFExecutedStageCount','RFAppliedStageCount'};
                    assert(isstruct(r)&&isscalar(r)&&all(isfield(r,required)), ...
                        'sixgr:truth:RFExecutionReplay','Retain actual RF replay metadata, not inferred activity.');
                    assert(string(r.RFProcessingMode)=="retained_sample_stream" && ...
                        upper(string(r.RFEndpoint))==role && r.RFStreamStartSample==first && ...
                        r.RFStreamEndSampleExclusive==stop && r.RFConfigurationEpoch==obj.ConfigurationEpoch, ...
                        'sixgr:truth:RFExecutionReplay','RF replay must match its endpoint, epoch and consumed clock.');
                    values=double([r.RFInputPower r.RFOutputPower]);
                    assert(numel(values)==2 && all(isfinite(values)&values>=0), ...
                        'sixgr:truth:RFExecutionPower','RF mean-square measurements must be finite and nonnegative.');
                    assert(islogical(r.RFInputAllZero)&&isscalar(r.RFInputAllZero) && ...
                        (~r.RFInputAllZero||values(1)==0), ...
                        'sixgr:truth:RFExecutionPower','Zero-input evidence must come from actual RF samples, not a power threshold.');
                    hashes=string({r.RFInputWaveformSHA256,r.RFOutputWaveformSHA256});
                    assert(all(arrayfun(@(h)~isempty(regexp(char(h),'^[0-9a-f]{64}$','once')),hashes)), ...
                        'sixgr:truth:RFExecutionHash','Use the actual RF operator input/output hashes.');
                    counts=double([r.RFConfiguredStageCount r.RFExecutedStageCount r.RFAppliedStageCount]);
                    assert(numel(counts)==3 && all(isfinite(counts)&counts>=0&counts==fix(counts)) && ...
                        counts(3)<=counts(2) && isscalar(r.RFStrictOk) && any(r.RFStrictOk==[0 1]), ...
                        'sixgr:truth:RFExecutionStages','Retain finite executed stage counts and the actual strict outcome.');
                    row=sixgr.truth.RFEndpointExecutionLedger.emptyTable(1);
                    row.EndpointID=actual(k); row.Role=role; row.Direction=string(inv.Direction);
                    row.StartSample=first; row.EndSampleExclusive=stop;
                    row.SampleRateHz=obj.SampleRateHz; row.SampleCount=stop-first;
                    row.PhysicalPortCount=double(inv.PhysicalPortCount);
                    row.ConfigurationEpoch=obj.ConfigurationEpoch;
                    row.InputMeanSquare=values(1); row.OutputMeanSquare=values(2);
                    row.InputSquaredMagnitudeSum=values(1)*row.SampleCount*row.PhysicalPortCount;
                    row.OutputSquaredMagnitudeSum=values(2)*row.SampleCount*row.PhysicalPortCount;
                    row.InputIsAllZero=r.RFInputAllZero; row.RFStrictOk=logical(r.RFStrictOk);
                    row.ConfiguredStageCount=counts(1); row.ExecutedStageCount=counts(2); row.AppliedStageCount=counts(3);
                    row.InputWaveformSHA256=hashes(1); row.OutputWaveformSHA256=hashes(2);
                    next=[next;row]; %#ok<AGROW>
                    measured=sixgr.truth.rfChainPowerInterval(r,actual(k),role,inv.Direction, ...
                        first,stop,obj.SampleRateHz,double(inv.PhysicalPortCount));
                    nextPower=[nextPower;measured]; %#ok<AGROW>
                    if role=="TX"
                        nextSpatial=[nextSpatial;sixgr.truth.rfTXSpatialPowerInterval(r,row)]; %#ok<AGROW>
                        enabled=any(arrayfun(@(x)string(x.Installation.TransmitterID)==actual(k),obj.TXRadiationLibrary));
                        assert(enabled==isfield(r,'ModeledRadiation'),'sixgr:truth:ModeledRadiationMissing', ...
                            'Enabled TX radiation must retain each original interval; disabled radios cannot inject receipts.');
                        if enabled
                            nativeHashes=strings(0,1);
                            for link=links
                                if string(link.TX)~=actual(k), continue; end
                                assert(isfield(link.Replay,'TXRadiationInstallation'), ...
                                    'sixgr:truth:ModeledRadiationMissing','Active native link lacks its installation binding.');
                                nativeHashes(end+1,1)=string(link.Replay.TXRadiationInstallation.ReceiptSHA256); %#ok<AGROW>
                            end
                            nextRadiation=[nextRadiation;sixgr.truth.modeledRadiationInterval(r,row,nativeHashes)]; %#ok<AGROW>
                        end
                    end
                end
            end
            references=sixgr.util.structGet(execution,'TXLinearReferences',struct('ID',{},'Receipt',{}));
            assert(isstruct(references)&&all(isfield(references,{'ID','Receipt'})), ...
                'sixgr:truth:TXLinearReferenceMissing','Separate original-owner model receipts are required.');
            actual=string({references.ID});
            expected=strings(numel(obj.TXLinearReferenceLibrary),1);
            for k=1:numel(expected), expected(k)=string(obj.TXLinearReferenceLibrary(k).EndpointID); end
            assert(numel(actual)==numel(expected)&&numel(unique(actual))==numel(actual)&&all(ismember(expected,actual)), ...
                'sixgr:truth:TXLinearReferenceMissing','Every enabled original TX requires one separate model receipt; disabled TX cannot inject one.');
            for k=1:numel(references)
                base=next(next.Role=="TX"&next.EndpointID==actual(k),:);
                nextLinear=[nextLinear;sixgr.truth.txLinearReferenceInterval(references(k).Receipt,base)]; %#ok<AGROW>
            end
            % Commit only after every endpoint passed its metadata checks.
            combined=[obj.Rows;next];
            if isempty(obj.ChainPowerRows), combinedPower=nextPower;
            else, combinedPower=[obj.ChainPowerRows;nextPower]; end
            sixgr.truth.validateRFChainPowerIntervals(nextPower,next);
            sixgr.truth.validateTXSpatialPowerIntervals(nextSpatial,next,nextPower);
            sixgr.truth.validateModeledRadiationIntervals(nextRadiation,obj.TXRadiationLibrary,next,nextSpatial,native);
            sixgr.truth.validateTXLinearReferenceIntervals(nextLinear,obj.TXLinearReferenceLibrary,next,nextPower);
            if isempty(obj.TXLinearReferenceIntervals), combinedLinear=nextLinear;
            else, combinedLinear=[obj.TXLinearReferenceIntervals;nextLinear]; end
            % Check only the prior compact tuple, not every historic JSON
            % receipt on every append. Full validation occurs on read/export.
            if ~isempty(obj.TXLinearReferenceIntervals)
                for k=1:height(nextLinear)
                    prior=find(obj.TXLinearReferenceIntervals.EndpointID==nextLinear.EndpointID(k),1,'last');
                    assert(~isempty(prior)&& ...
                        obj.TXLinearReferenceIntervals.StaticOperatorSHA256(prior)==nextLinear.StaticOperatorSHA256(k), ...
                        'sixgr:truth:TXLinearReferenceClosure','Installed static RF operators changed between intervals.');
                end
            end
            if isempty(obj.TXSpatialPowerRows), combinedSpatial=nextSpatial;
            else, combinedSpatial=[obj.TXSpatialPowerRows;nextSpatial]; end
            obj.Rows=combined; obj.ChainPowerRows=combinedPower;
            obj.TXSpatialPowerRows=combinedSpatial;
            if isempty(obj.TXRadiationRows), obj.TXRadiationRows=nextRadiation;
            else, obj.TXRadiationRows=[obj.TXRadiationRows;nextRadiation]; end
            obj.TXRadiationNativeBindings=native;
            obj.TXLinearReferenceIntervals=combinedLinear;
            obj.NextSampleIndex=stop;
        end

        function evidence=read(obj)
            evidence=struct('Contract',"committed_rf_endpoint_execution/v1", ...
                'SampleRateHz',obj.SampleRateHz,'OriginSample',obj.OriginSample, ...
                'EndSampleExclusive',obj.NextSampleIndex,'ConfigurationEpoch',obj.ConfigurationEpoch, ...
                'Inventory',obj.Inventory,'Intervals',obj.Rows,'ProducerSHA256',obj.ProducerSHA256);
            evidence.Coverage=sixgr.truth.RFEndpointExecutionLedger.validate(evidence);
            evidence.CompleteFromOrigin=~isempty(evidence.Coverage) && all(evidence.Coverage.CompleteFromOrigin);
            evidence.CompleteFromSampleZero=evidence.CompleteFromOrigin && obj.OriginSample==0;
            evidence.HardwareOperatingStateAvailable=false;
            evidence.ChainPowerIntervals=obj.ChainPowerRows;
            evidence.ChainPowerCompleteFromOrigin= ...
                sixgr.truth.validateRFChainPowerIntervals(obj.ChainPowerRows,obj.Rows);
            evidence.TXSpatialPowerIntervals=obj.TXSpatialPowerRows;
            evidence.TXSpatialPowerCompleteFromOrigin= ...
                sixgr.truth.validateTXSpatialPowerIntervals(obj.TXSpatialPowerRows,obj.Rows,obj.ChainPowerRows);
            evidence.TXRadiationLibrary=obj.TXRadiationLibrary;
            evidence.TXRadiationNativeBindings=obj.TXRadiationNativeBindings;
            radiation=obj.TXRadiationRows;
            if isempty(radiation), radiation=sixgr.truth.modeledRadiationInterval(); end
            evidence.TXRadiationIntervals=radiation;
            evidence.ModeledRadiationCompleteFromOrigin=sixgr.truth.validateModeledRadiationIntervals( ...
                radiation,obj.TXRadiationLibrary,obj.Rows,obj.TXSpatialPowerRows,obj.TXRadiationNativeBindings);
            linear=obj.TXLinearReferenceIntervals;
            if isempty(linear), linear=sixgr.truth.txLinearReferenceInterval(); end
            evidence.TXLinearReferenceLibrary=obj.TXLinearReferenceLibrary;
            evidence.TXLinearReferenceIntervals=linear;
            evidence.TXLinearReferenceCompleteFromOrigin=sixgr.truth.validateTXLinearReferenceIntervals( ...
                linear,obj.TXLinearReferenceLibrary,obj.Rows,obj.ChainPowerRows);
        end
    end
    methods (Static)
        function T=emptyTable(count)
            if nargin<1, count=0; end
            row=struct('EndpointID',"",'Role',"",'Direction',"", ...
                'StartSample',NaN,'EndSampleExclusive',NaN,'SampleRateHz',NaN,'SampleCount',NaN, ...
                'PhysicalPortCount',NaN,'ConfigurationEpoch',NaN, ...
                'InputMeanSquare',NaN,'OutputMeanSquare',NaN, ...
                'InputSquaredMagnitudeSum',NaN,'OutputSquaredMagnitudeSum',NaN, ...
                'InputIsAllZero',false,'RFStrictOk',false, ...
                'ConfiguredStageCount',NaN,'ExecutedStageCount',NaN,'AppliedStageCount',NaN, ...
                'InputWaveformSHA256',"",'OutputWaveformSHA256',"", ...
                'ClockDomain',"shared_physical_absolute_sample_clock_zero_based", ...
                'PowerPlane',"mean_squared_complex_RF_operator_samples_not_calibrated_hardware_watts", ...
                'OperatingState',"RF_operator_executed_hardware_state_not_inferred", ...
                'Source',"completed_shared_physical_RF_execution");
            T=struct2table(row); T=T(ones(count,1),:);
        end

        function coverage=validate(evidence)
            assert(isstruct(evidence)&&isscalar(evidence)&& ...
                all(isfield(evidence,{'Contract','SampleRateHz','OriginSample','EndSampleExclusive', ...
                'ConfigurationEpoch','Inventory','Intervals'})) && ...
                string(evidence.Contract)=="committed_rf_endpoint_execution/v1", ...
                'sixgr:truth:RFExecutionEvidence','An explicit RF execution contract is required.');
            % Reuse the producer's strict checks for recovered file evidence.
            check=sixgr.truth.RFEndpointExecutionLedger(evidence.SampleRateHz,evidence.OriginSample, ...
                evidence.ConfigurationEpoch,evidence.Inventory);
            T=evidence.Intervals; template=sixgr.truth.RFEndpointExecutionLedger.emptyTable();
            assert(istable(T)&&all(ismember(template.Properties.VariableNames,T.Properties.VariableNames)), ...
                'sixgr:truth:RFExecutionEvidence','The complete compact execution schema is required.');
            validateattributes(evidence.EndSampleExclusive,{'numeric'}, ...
                {'scalar','real','finite','integer','>=',evidence.OriginSample});
            assert(~isempty(T)||evidence.EndSampleExclusive==evidence.OriginSample, ...
                'sixgr:truth:RFExecutionCoverage','A nonzero committed interval cannot have an empty execution ledger.');
            ids=string(T.Role)+"|"+string(T.EndpointID);
            expected=string(check.Inventory.Role)+"|"+string(check.Inventory.EndpointID);
            assert(all(ismember(ids,expected)), 'sixgr:truth:RFExecutionEndpointCoverage','Unknown RF endpoint.');
            coverage=check.Inventory;
            coverage.OriginSample=repmat(evidence.OriginSample,height(coverage),1);
            coverage.EndSampleExclusive=repmat(evidence.EndSampleExclusive,height(coverage),1);
            coverage.ExecutedSamples=zeros(height(coverage),1);
            coverage.IntervalCount=zeros(height(coverage),1);
            coverage.CompleteFromOrigin=false(height(coverage),1);
            for k=1:height(coverage)
                rows=T(ids==expected(k),:); rows=sortrows(rows,'StartSample');
                if isempty(rows), continue; end
                a=double(rows.StartSample); b=double(rows.EndSampleExclusive);
                assert(all(isfinite(a)&isfinite(b)&a==fix(a)&b==fix(b)&b>a) && ...
                    a(1)==evidence.OriginSample && b(end)==evidence.EndSampleExclusive && ...
                    all(a(2:end)==b(1:end-1)) && all(rows.SampleCount==b-a) && ...
                    all(rows.SampleRateHz==evidence.SampleRateHz) && ...
                    all(rows.ConfigurationEpoch==evidence.ConfigurationEpoch) && ...
                    all(rows.PhysicalPortCount==coverage.PhysicalPortCount(k)) && ...
                    all(string(rows.Direction)==string(coverage.Direction(k))), ...
                    'sixgr:truth:RFExecutionCoverage','RF execution has a gap, overlap, wrong endpoint or clock.');
                assert(all(isfinite(rows.InputMeanSquare)&rows.InputMeanSquare>=0 & ...
                    isfinite(rows.OutputMeanSquare)&rows.OutputMeanSquare>=0) && ...
                    all(ismember(rows.InputIsAllZero,[0 1])) && ...
                    all(~rows.InputIsAllZero|rows.InputMeanSquare==0) && ...
                    all(abs(rows.InputSquaredMagnitudeSum-rows.InputMeanSquare.*rows.SampleCount.*rows.PhysicalPortCount) ...
                    <=1e-12*max(1,rows.InputSquaredMagnitudeSum)) && ...
                    all(abs(rows.OutputSquaredMagnitudeSum-rows.OutputMeanSquare.*rows.SampleCount.*rows.PhysicalPortCount) ...
                    <=1e-12*max(1,rows.OutputSquaredMagnitudeSum)), ...
                    'sixgr:truth:RFExecutionPower','RF execution sample-energy arithmetic is inconsistent.');
                for field=["InputWaveformSHA256","OutputWaveformSHA256"]
                    assert(all(arrayfun(@(h)~isempty(regexp(char(h),'^[0-9a-f]{64}$','once')),string(rows.(field)))), ...
                        'sixgr:truth:RFExecutionHash','RF execution hashes are missing or invalid.');
                end
                counts=[rows.ConfiguredStageCount rows.ExecutedStageCount rows.AppliedStageCount];
                assert(all(isfinite(counts)&counts>=0&counts==fix(counts),'all') && ...
                    all(rows.AppliedStageCount<=rows.ExecutedStageCount) && ...
                    all(ismember(rows.RFStrictOk,[0 1])), ...
                    'sixgr:truth:RFExecutionStages','Invalid executed RF stage counts or strict outcome.');
                for field=["ClockDomain","PowerPlane","OperatingState","Source"]
                    prototype=sixgr.truth.RFEndpointExecutionLedger.emptyTable(1);
                    assert(all(string(rows.(field))==prototype.(field)), ...
                        'sixgr:truth:RFExecutionScope','RF execution cannot be relabeled as hardware power or sleep state.');
                end
                coverage.ExecutedSamples(k)=sum(b-a); coverage.IntervalCount(k)=height(rows);
                coverage.CompleteFromOrigin(k)=true;
            end
            assert(isempty(T)||all(coverage.CompleteFromOrigin), ...
                'sixgr:truth:RFExecutionEndpointCoverage','A committed interval cannot omit a registered endpoint.');
        end
    end
end
