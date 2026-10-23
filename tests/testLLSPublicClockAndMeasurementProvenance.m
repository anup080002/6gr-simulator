function ok=testLLSPublicClockAndMeasurementProvenance(retainedCSV)
% Public projection regression; no PHY execution or performance qualification.
% Retained receiver evidence is read-only. Boundary rows below are declared
% adapter fixtures, not new simulated measurements or replacement run rows.
% No argument: portable declared-adapter checks only. Supply the original
% v140 CSV explicitly to add the retained physical-evidence projection audit.
setup6GRSimToolkit('Verbose',false);
retainedRequested=nargin>=1;
originalBytes=''; raw=table(); before=table(); published=table();
meta=struct('logical_run_id',"declared_public_projection_audit",'run_id',140);
contract=sixgr.truth.llsOutputContract();
checks={@declaredClockBoundaries,@declaredMissingSFN,@declaredMeasurementUnits, ...
    @declaredExplicitPercent,@declaredAmbiguousLegacy};
sourceMode="declared_adapter_only";
if retainedRequested
    assert(isfile(retainedCSV),'test:MissingRetainedPublicEvidence', ...
        'Supply the original retained receiver CSV; do not generate substitute evidence.');
    assert(sixgr.util.sha256File(retainedCSV)== ...
        "8f96f52fd30fdb2780f9850848030218aa48619d7b400c35adfe6b42754b28ac", ...
        'test:RetainedPublicEvidenceHash','Require the unchanged original v140 receiver CSV.');
    originalBytes=fileread(retainedCSV);
    raw=localRead(retainedCSV);
    assert(height(raw)==1 && raw.Frame==2 && raw.SFN==1 && raw.Slot==16, ...
        'test:RetainedPublicEvidenceIdentity','This reproducer requires the original v140 singleton.');
    meta.logical_run_id="retained_v140_public_projection_audit";
    before=raw; randomBefore=rng;
    actual=sixgr.truth.buildLLSPublicOutputTables(struct('pdsch_table',raw),contract,meta);
    assert(isequaln(before,raw)&&isequaln(randomBefore,rng)&& ...
        strcmp(originalBytes,fileread(retainedCSV)),'Projection changed original evidence or RNG.');
    published=actual.pdsch_runtime_event_table;
    checks=[{@retainedClock,@retainedMeasurements,@retainedCapsules},checks,{@csvRoundTrip}];
    sourceMode="declared_adapter_and_explicit_retained_v140";
else
    fprintf('PUBLIC_CLOCK_MEASUREMENT_RETAINED_REPLAY_NOT_REQUESTED no_physical_evidence_claim=1\n');
end
passed=0; failures=strings(0,1);
for k=1:numel(checks)
    try
        checks{k}(); passed=passed+1;
        fprintf('PUBLIC_CLOCK_MEASUREMENT_GROUP_PASS %s\n',func2str(checks{k}));
    catch cause
        failures(end+1,1)=string(func2str(checks{k}))+": "+string(cause.identifier)+": "+string(cause.message); %#ok<AGROW>
        fprintf('PUBLIC_CLOCK_MEASUREMENT_GROUP_FAIL %s\n',failures(end));
    end
end
if retainedRequested
    assert(strcmp(originalBytes,fileread(retainedCSV))&&isequaln(before,raw), ...
        'Retained original CSV/source table changed.');
end
fprintf('PUBLIC_CLOCK_MEASUREMENT_SUMMARY passed=%d failed=%d source_mode=%s no_PHY_execution=1\n', ...
    passed,numel(failures),sourceMode);
assert(isempty(failures),'test:PublicClockMeasurementFailures','%s',strjoin(failures,newline));
ok=true;

    function retainedClock()
        localClock(published,raw);
        assert(published.SFN~=published.Frame,'SFN is zero based; Frame is a distinct one-based owner field.');
    end

    function retainedMeasurements()
        localMeasurements(published,raw);
        assert(published.MCS==raw.MCSIndex && published.PRBLength==raw.PRBCount && ...
            published.NumLayers==raw.Layers && published.TBSBits==raw.TBSize_bits, ...
            'Executed allocation/MCS aliases changed.');
    end

    function retainedCapsules()
        fields=localCapsuleFields();
        for name=fields
            assert(ismember(name,string(published.Properties.VariableNames))&& ...
                isequaln(published.(name),raw.(name)),'Original field changed: %s',name);
        end
        for prefix=["DLSCHFinalOutcome","SharedDLSCHOutcome"]
            token=string(published.(prefix+"JSON"));
            assert(string(sixgr.util.sha256Hex(char(token)))==string(published.(prefix+"SHA256")), ...
                'Original JSON digest mismatch: %s',prefix);
        end
    end

    function declaredClockBoundaries()
        source=localFixture(); snapshot=source;
        tables=localAllFamilies(source,contract,meta);
        for name=localFamilies()
            localClock(tables.(name),source);
        end
        assert(isequaln(source,snapshot),'Adapter changed declared source clocks.');
    end

    function declaredMissingSFN()
        source=removevars(localFixture(),'SFN');
        tables=localAllFamilies(source,contract,meta);
        for name=localFamilies()
            t=tables.(name);
            assert(all(isnan(t.SFN)),'A missing SFN was invented from Frame for %s.',name);
            assert(ismember('Frame',t.Properties.VariableNames)&&isequaln(t.Frame,source.Frame), ...
                'Keep original Frame independently for %s.',name);
        end
    end

    function declaredMeasurementUnits()
        source=localFixture();
        source.EVM_rms=[0.01;1.5;0;NaN];
        source.EVMReferenceSource=repmat("declared_paired_symbol_reference_not_physical_evidence",4,1);
        source.EVMValueStatus=["DECLARED";"DECLARED";"DECLARED";"NOT_AVAILABLE"];
        source.EVMStatus=["DECLARED";"DECLARED";"DECLARED";"NOT_AVAILABLE"];
        source.ChannelEstimateSource=repmat("declared_resource_estimator_fixture",4,1);
        tables=localAllFamilies(source,contract,meta);
        for name=["pdsch_runtime_event_table","pusch_runtime_event_table"]
            localMeasurements(tables.(name),source);
        end
        % Explicit unknowns are not replaced by conversion-method labels.
        source.EVMReferenceSource(:)=""; source.EVMValueStatus(:)=""; source.EVMStatus(:)="";
        tables=localAllFamilies(source,contract,meta);
        localMeasurements(tables.pdsch_runtime_event_table,source);
    end

    function declaredExplicitPercent()
        source=localFixture();
        source.EVM_percent=[0.5;150;0;NaN];
        source.EVMReferenceSource=repmat("declared_explicit_percent_reference",4,1);
        tables=localAllFamilies(source,contract,meta);
        for name=["pdsch_runtime_event_table","pusch_runtime_event_table"]
            t=tables.(name);
            assert(isequaln(t.EVM_percent,source.EVM_percent),'Explicit percent must not be rescaled.');
            assert(all(t.EVMUnitConversionSource(1:3)=="explicit_percent")&& ...
                isequal(t.EVMSource,source.EVMReferenceSource), ...
                'Unit conversion must stay separate from the original reference source.');
        end
    end

    function declaredAmbiguousLegacy()
        for legacyName=["EVM","PostEqEVM"]
            source=localFixture(); source.(legacyName)=[0.01;1.5;150;NaN];
            tables=localAllFamilies(source,contract,meta);
            for name=["pdsch_runtime_event_table","pusch_runtime_event_table"]
                t=tables.(name);
                assert(all(isnan(t.EVM_percent))&& ...
                    all(t.EVMUnitConversionSource=="unavailable_ambiguous_legacy_EVM_unit"), ...
                    'An ambiguous legacy field must not gain units from its magnitude.');
            end
        end
    end

    function csvRoundTrip()
        % Only derived audit output is written, never the retained run CSV.
        retainedClock(); retainedMeasurements(); retainedCapsules();
        folder=tempname; mkdir(folder);
        file=fullfile(folder,'public_clock_and_measurement_projection.csv');
        sixgr.util.csvWriteTable(file,published,'RoundTripNumericText',true);
        loaded=localRead(file);
        localClock(loaded,raw); localMeasurements(loaded,raw);
        for name=localCapsuleFields()
            assert(isequaln(loaded.(name),raw.(name)), ...
                'CSV round trip changed original receipt field %s.',name);
        end
        fprintf('PUBLIC_CLOCK_MEASUREMENT_AUDIT_CSV %s\n',file);
    end
end

function T=localRead(file)
% These production files are comma CSV with quoted JSON fields. Automatic
% delimiter inference can mistake the many separators inside JSON receipts
% for the delimiter and collapse the entire header into one variable.
opts=detectImportOptions(file,'Delimiter',',','VariableNamingRule','preserve', ...
    'TextType','string','Encoding','UTF-8');
opts.VariableNamesLine=1;
opts.DataLines=[2 Inf];
textNames=string(opts.VariableNames);
textNames=textNames(endsWith(textNames,"JSON")|endsWith(textNames,"SHA256")| ...
    endsWith(textNames,"Source")|endsWith(textNames,"Status")|endsWith(textNames,"Stage")| ...
    endsWith(textNames,"Scope")|endsWith(textNames,"Policy")|endsWith(textNames,"TransmissionID"));
opts=setvartype(opts,cellstr(textNames),'string');
opts=setvaropts(opts,cellstr(textNames),'WhitespaceRule','preserve');
T=readtable(file,opts);
end

function localClock(T,source)
assert(height(T)==height(source)&&ismember('Frame',T.Properties.VariableNames), ...
    'test:PublicFrameLost','Public rows must retain original Frame separately from SFN.');
assert(isequaln(T.SFN,source.SFN)&&isequaln(T.Frame,source.Frame)&&isequaln(T.Slot,source.Slot), ...
    'test:PublicClockChanged','Preserve explicit SFN, Frame and Slot independently, including unknown SFN.');
end

function localMeasurements(T,source)
for name=["EVMReferenceSource","EVMValueStatus","EVMStatus"]
    assert(ismember(name,string(T.Properties.VariableNames))&&isequaln(T.(name),source.(name)), ...
        'test:PublicMeasurementProvenanceLost','Original measurement field missing/changed: %s',name);
end
assert(isequaln(T.ChannelEstimationSource,source.ChannelEstimateSource), ...
    'test:PublicEstimatorSourceLost','Public estimator alias must retain the actual producer source.');
expected=100*double(source.EVM_rms); measured=double(T.EVM_percent);
finite=isfinite(expected);
assert(all(isnan(measured(~finite)))&&all(abs(measured(finite)-expected(finite))<= ...
    1e-12*max(1,abs(expected(finite)))), ...
    'test:PublicEVMUnitChanged','EVM_rms is fractional RMS even above one; do not infer units from magnitude.');
assert(all(T.EVMUnitConversionSource(finite)=="fractional_rms_times_100"), ...
    'Keep fractional-to-percent conversion separate from measurement reference provenance.');
end

function source=localFixture()
% 15-kHz-style declared clocks at first frame, SFN wrap, and unknown SFN.
% These are adapter inputs only; they do not qualify a physical clock producer.
source=table([1;1024;1025;1025],[0;1023;0;NaN],[1;10231;10241;10242], ...
    'VariableNames',{'Frame','SFN','Slot'});
source.Direction=repmat("DL",4,1);
source.SourceSignal=repmat("received_CSI_UCI",4,1);
source.ReportIdentity="declared_report_"+string((1:4)');
source.CSIUCIDecodeOk=true(4,1);
source.DeliveredSlot=source.Slot;
end

function tables=localAllFamilies(source,contract,meta)
base=struct();
for name=["pdsch_table","pusch_table","pdcch_dci_table","pucch_table", ...
        "prach_table","srs_table","csi_rs_table","trs_receiver_tracking_table","ssb_pbch_table"]
    base.(name)=source;
end
tables=sixgr.truth.buildLLSPublicOutputTables(base,contract,meta,source);
end

function names=localFamilies()
names=["pdsch_runtime_event_table","pusch_runtime_event_table","pdcch_dci_public_table", ...
    "pucch_uci_table","prach_detection_table","srs_measurement_table", ...
    "csi_rs_runtime_event_table","csi_report_table","trs_receiver_tracking_public_table", ...
    "ssb_pbch_cell_search_table"];
end

function fields=localCapsuleFields()
fields=["DLSCHFinalOutcomeAvailable","DLSCHFinalOutcomeStage","DLSCHFinalOutcomeJSON", ...
    "DLSCHFinalOutcomeSHA256","DLSCHSuccessfulDecodedBits","DLSCHSuccessfulDecodedBitsScope", ...
    "DLSCHAggregateGoodBitsPolicy","SharedDLSCHOutcomeAvailable","SharedDLSCHOutcomeStage", ...
    "SharedDLSCHOutcomeJSON","SharedDLSCHOutcomeSHA256","SharedDLSCHOutcomeTransmissionID", ...
    "SharedDLSCHOutcomeDecoderSHA256","SharedDLSCHOutcomeTransportCreditBound"];
end
