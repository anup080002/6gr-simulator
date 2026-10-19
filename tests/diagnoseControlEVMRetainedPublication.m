function receipt=diagnoseControlEVMRetainedPublication(runRoot,outRoot,verifyExisting)
% Replay ONLY exact retained measurements through the production exporter.
% Original trial, IQ and publication artifacts are never modified.
setup6GRSimToolkit('Verbose',false);
if nargin<3, verifyExisting=false; end
assert(islogical(verifyExisting)&&isscalar(verifyExisting));
assert(verifyExisting || ~isfolder(outRoot), ...
    'sixgr:test:ExistingDiagnosticOutput','Use a new diagnostic folder or explicitly verify existing bytes.');
source=fullfile(runRoot,'air_interface','csv','csi_rs_trials.csv');
T=sixgr.util.csvReadTable(source,'TextType','string');
assert(~isempty(T),'sixgr:test:MissingRetainedCSI','Retained actual CSI trials are required.');
trialPath=fullfile(outRoot,'air_interface','csv','csi_rs_trials.csv');
if verifyExisting
    retained=sixgr.util.csvReadTable(trialPath,'TextType','string');
    assert(isequaln(retained,T),'sixgr:test:ChangedReplaySource','Existing replay must bind the same source trials.');
    output=fullfile(outRoot,'air_interface','csv','csi_rs_evm_samples.csv');
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
    'SourceTrials',height(T),'VerifiedPairedRows',checked,'ExactAllSampleComparison',true, ...
    'OutputCSV',string(output),'OutputSHA256',sixgr.util.sha256File(output), ...
    'WriteSeconds',writeSeconds,'VerifySeconds',toc(started), ...
    'VerificationOfExistingCSV',verifyExisting,'Pass',true);
sixgr.util.jsonWrite(fullfile(outRoot,'receipt.json'),receipt);
disp(receipt);
end
