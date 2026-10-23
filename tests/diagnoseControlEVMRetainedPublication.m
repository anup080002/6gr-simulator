function receipt=diagnoseControlEVMRetainedPublication(runRoot,outRoot,verifyExisting,sourceRelativePath,selectedSlots)
% Replay ONLY exact retained measurements through the production exporter.
% Original trial, IQ and publication artifacts are never modified.
setup6GRSimToolkit('Verbose',false);
if nargin<3, verifyExisting=false; end
if nargin<4, sourceRelativePath="air_interface/csv/csi_rs_trials.csv"; end
if nargin<5, selectedSlots=[]; end
assert(islogical(verifyExisting)&&isscalar(verifyExisting));
sourceRelativePath=replace(string(sourceRelativePath),"\","/");
assert(isscalar(sourceRelativePath) && ~isempty(regexp(char(sourceRelativePath), ...
    '^(air_interface|control)/csv/(csi_rs|srs|trs|pbch|prach)_trials\.csv$','once')), ...
    'sixgr:test:InvalidRetainedControlSource','Select an explicit run-owned physical control table.');
assert(verifyExisting || ~isfolder(outRoot), ...
    'sixgr:test:ExistingDiagnosticOutput','Use a new diagnostic folder or explicitly verify existing bytes.');
source=fullfile(runRoot,sourceRelativePath);
T=sixgr.util.csvReadTable(source,'TextType','string');
assert(~isempty(T),'sixgr:test:MissingRetainedCSI','Retained actual control trials are required.');
sourceTotal=height(T); selectedRows=(1:sourceTotal).';
if ~isempty(selectedSlots)
    validateattributes(selectedSlots,{'numeric'},{'vector','finite','integer','positive'});
    assert(ismember('Slot',T.Properties.VariableNames) && ...
        all(ismember(selectedSlots,double(T.Slot))), ...
        'sixgr:test:MissingSelectedControlTrial','Every explicitly selected slot must have a retained row.');
    selectedRows=find(ismember(double(T.Slot),selectedSlots));
    T=T(selectedRows,:);
end
[~,trialName,extension]=fileparts(sourceRelativePath);
trialPath=fullfile(outRoot,'air_interface','csv',trialName+extension);
sampleFiles=struct('csi_rs_trials','csi_rs_evm_samples.csv','srs_trials','srs_evm_samples.csv', ...
    'trs_trials','trs_evm_samples.csv','pbch_trials','ssb_evm_samples.csv','prach_trials','prach_evm_samples.csv');
if verifyExisting
    retained=sixgr.util.csvReadTable(trialPath,'TextType','string');
    assert(isequaln(retained,T),'sixgr:test:ChangedReplaySource','Existing replay must bind the same source trials.');
    output=fullfile(outRoot,'air_interface','csv',sampleFiles.(trialName));
    assert(isfile(output),'sixgr:test:MissingReplayCSV','Existing CSV is required.');
    writeSeconds=NaN;
else
    for k=1:height(T)
        sixgr.report.readControlEVMPairs(T(k,:),source,true);
        relative=T.ControlEVMSamplesMATFile(k);
        target=fullfile(outRoot,relative); sixgr.util.ensureDir(target);
        copyfile(fullfile(runRoot,relative),target);
    end
    sixgr.util.csvWriteTable(trialPath,T,'PreserveSchema',true,'RoundTripNumericText',true);
    started=tic;
    [output,rewritten]=sixgr.report.exportControlEVMSamples(trialPath,T);
    writeSeconds=toc(started); assert(rewritten);
end
% Stream independently back from disk. Compare EVERY paired sample against
% its exact MAT source, not just EVM aggregates or the exporter's row count.
ds=tabularTextDatastore(output,'Delimiter',',','TextType','string','ReadSize',8192);
fields={'SampleIndex','ReferenceReal','ReferenceImag','MeasuredReal','MeasuredImag', ...
    'SourceTrialRow','PortIndex','MeasurementDomain','ObservationID'};
ds.SelectedVariableNames=fields;
block=table(); offset=1; checked=0; started=tic;
for k=1:height(T)
    records=sixgr.report.readControlEVMPairs(T(k,:),source);
    for e=reshape(records,1,[])
        first=1; count=numel(e.SampleIndex);
        while first<=count
            if offset>height(block)
                assert(hasdata(ds),'sixgr:test:TruncatedEVMCSV','CSV omitted measured samples.');
                block=read(ds); offset=1;
                % %.17g is deliberately quoted by the production writer.
                % Datastore infers %q/string for these columns; explicitly
                % decode decimal text before comparing to MAT doubles.
                for field=string(fields(1:7))
                    if ~isnumeric(block.(field))
                        block.(field)=str2double(block.(field));
                    end
                    assert(all(isfinite(block.(field))), ...
                        'sixgr:test:MalformedEVMCSVNumber','Expected finite measured numbers.');
                end
            end
            n=min(count-first+1,height(block)-offset+1);
            rows=offset:offset+n-1; samples=first:first+n-1;
            for field=string(fields(1:5))
                expected=e.(field)(samples); actual=block.(field)(rows);
                assert(isequal(actual(:),double(expected(:))), ...
                    'sixgr:test:RetainedEVMSampleMismatch','Exact paired sample changed: %s.',field);
            end
            assert(all(block.SourceTrialRow(rows)==k) && all(block.PortIndex(rows)==e.PortIndex) && ...
                all(string(block.MeasurementDomain(rows))==string(e.MeasurementDomain)) && ...
                all(string(block.ObservationID(rows))==string(e.ObservationID)), ...
                'sixgr:test:RetainedEVMIdentityMismatch','Sample ownership changed at a chunk boundary.');
            first=first+n; offset=offset+n; checked=checked+n;
        end
    end
end
assert(offset>height(block)&&~hasdata(ds) && checked==sum(T.ControlEVMSamplesCount), ...
    'sixgr:test:RetainedEVMExtraSamples','No invented, duplicated or omitted CSV samples.');
receipt=struct('Scope',"retained_measurement_export_replay_not_new_PHY", ...
    'SourceTrialCSV',string(source),'SourceTrialSHA256',sixgr.util.sha256File(source), ...
    'SourceTotalTrialRows',sourceTotal,'SelectedSourceTrialRows',selectedRows, ...
    'ExplicitSelectedSlots',selectedSlots,'CompleteSourceTableReplayed',numel(selectedRows)==sourceTotal, ...
    'SourceTrials',height(T),'VerifiedPairedRows',checked,'ExactAllSampleComparison',true, ...
    'OutputCSV',string(output),'OutputSHA256',sixgr.util.sha256File(output), ...
    'WriteSeconds',writeSeconds,'VerifySeconds',toc(started), ...
    'VerificationOfExistingCSV',verifyExisting,'Pass',true);
sixgr.util.jsonWrite(fullfile(outRoot,'receipt.json'),receipt);
disp(receipt);
end
