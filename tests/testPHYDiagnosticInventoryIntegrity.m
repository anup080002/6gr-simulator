function ok=testPHYDiagnosticInventoryIntegrity()
% Publication-contract fixtures ONLY, not received PHY measurements.
% This is a corrected-behavior regression: current inventory code is expected
% to fail because it checks names/counts but ignores scanner integrity flags.
% No new consumer clock fields are assumed before their production wiring.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'results','diagnostics','phy_inventory_integrity', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
sixgr.util.ensureFolder(root);
n=9007; T=localFixture(n);
names=["valid_capture";"legacy_unknown_clock";"late_truth"; ...
    "late_construction";"late_source";"late_status";"late_direction"; ...
    "late_snapshot";"late_trial_tuple"];
fields=["";"";"truth_status";"CurveConstruction";"SourceArtifact"; ...
    "Status";"Direction";"SnapshotID";"TBId"];
values=["";"";"proxy";"synthetic_curve";"synthetic";"unavailable"; ...
    "INVALID";"another_snapshot";"another_tb"];
expectedFlag=["";"";"TruthOK";"ConstructionOK";"SourceOK"; ...
    "StatusOK";"DirectionOK";"";""];
passed=false(numel(names),1); sourceHashes=strings(numel(names),1);
sourcePaths=strings(numel(names),1); actualStatus=strings(numel(names),1);
clockStatus=strings(numel(names),1); sourceRows=zeros(numel(names),1);
for k=1:numel(names)
    caseRoot=fullfile(root,names(k)); layout=sixgr.report.resultLayout(caseRoot);
    sixgr.util.ensureFolder(layout.ReportCSVDir);
    sixgr.util.ensureFolder(layout.ReportImageDir);
    path=fullfile(layout.ReportCSVDir,'phy_signal_diagnostic_source.csv');
    data=T;
    if k==2
        % Keep the old declared numbers byte-for-byte after persistence.
        % These do not gain a radio-clock authority merely by re-exporting.
        data.SFN(:)=1; data.AbsoluteSlot(:)=16;
        data.SCS_kHz(:)=15; data.SlotsPerFrame(:)=10;
        data(:,{'CarrierNFrame','CarrierNSlot','RuntimeAbsoluteSlotIndex0', ...
            'SFNSource','SlotConvention','AbsoluteSlotConvention','AbsoluteSlotSource'})=[];
    elseif k>2
        data.(fields(k))(end)=values(k);
    end
    sixgr.util.csvWriteTable(path,data,'PreserveSchema',true);
    sourcePaths(k)=string(path);
    sourceHashes(k)=string(sixgr.util.sha256File(path));
    scan=sixgr.truth.scanPHYSignalDiagnosticCSV(path,127);
    assert(scan.RowCount==n && scan.MaxChunkRows<=127 && ...
        sum(scan.PanelSeriesCounts.RowCount)==n, ...
        'test:DiagnosticCSVRecordLoss','Quoted CSV lost or duplicated records: %s.',names(k));
    assert(scan.ClockContract.RowsChecked==n && scan.ClockContract.MaxChunkRows<=127);
    if strlength(expectedFlag(k))>0
        assert(~scan.(expectedFlag(k)), ...
            'test:DiagnosticLateCorruptionIgnored','Scanner ignored final-row %s.',fields(k));
    elseif k==8
        assert(numel(scan.DL.SnapshotIDs)==2,'Scanner ignored the final snapshot identity.');
    elseif k==9
        assert(~scan.DL.TupleConsistent,'Scanner ignored the final trial identity.');
    end
    % Exercise actual quoted-file parsing separately from inventory metadata.
    clocks=localReadClocks(path,n,data.Notes(1));
    if k<=2
        if k==1
            assert(clocks.RadioClockSourceContractConsistent);
            clockStatus(k)="consistent";
        else
            assert(~clocks.RadioClockSourceContractConsistent && ...
                clocks.Groups.Status=="unavailable");
            clockStatus(k)="unavailable";
        end
    else
        clockStatus(k)="not_a_sample_authenticity_test";
    end
    availability=sixgr.truth.phySignalDiagnosticAvailability(path,layout.ReportImageDir);
    out=sixgr.truth.exportTop50VisualizationEvidenceInventory(caseRoot,struct());
    row=out.InventoryTable(out.InventoryTable.VisualID==9,:);
    assert(height(row)==1 && row.SourceRowCount==n-5 && ...
        row.ResolvedSourceArtifact=="reports/csv/phy_signal_diagnostic_source.csv", ...
        'test:DiagnosticWrongPanel','Expected the exact capture-local TX panel.');
    sourceRows(k)=row.SourceRowCount; actualStatus(k)=row.AvailabilityStatus;
    if k<=2
        % Unknown absolute radio time must not erase independently available
        % capture-local I/Q. No image/PHY PASS or clock qualification claimed.
        passed(k)=availability.Source=="observed" && ...
            row.PlotCanBeRegeneratedFromCSV && row.AvailabilityStatus=="validated_reconstructible";
        assert(row.ReconstructionScope=="capture_local_samples_not_radio_clock_qualification");
        if k==1
            assert(row.RadioClockStatus=="consistent" && row.RadioClockSourceContractConsistent && ...
                availability.DLRadioClockSourceContractConsistent);
        else
            assert(row.RadioClockStatus=="unavailable" && ~row.RadioClockSourceContractConsistent && ...
                availability.DLRadioClockStatus=="unavailable");
        end
    else
        assert(availability.Source=="not_available", ...
            'test:DiagnosticAvailabilityFalseCredit','Existing availability accepted %s.',names(k));
        passed(k)=~row.PlotCanBeRegeneratedFromCSV && ...
            row.AvailabilityStatus~="validated_reconstructible";
    end
    assert(string(sixgr.util.sha256File(path))==sourceHashes(k), ...
        'test:DiagnosticSourceModified','A publication consumer rewrote its input CSV.');
    fprintf('PHY_INVENTORY_CASE name=%s rows=%d passed=%d status=%s source_sha256=%s\n', ...
        names(k),n,passed(k),actualStatus(k),sourceHashes(k));
end
% Keep baseline evidence even when the expected current defect is reproduced.
receipt=table(names,fields,passed,actualStatus,clockStatus,sourceRows,sourcePaths,sourceHashes, ...
    'VariableNames',{'Case','CorruptedField','ExpectedBehaviorPassed','InventoryStatus', ...
    'IndependentClockStatus','SelectedPanelRows','SourceCSV','SourceSHA256'});
sixgr.util.csvWriteTable(fullfile(root,'regression_receipt.csv'),receipt,'PreserveSchema',true);
assert(all(passed),'test:DiagnosticInventoryIntegrity', ...
    'Inventory failed corrected behavior for %s. Preserved evidence: %s', ...
    strjoin(names(~passed),', '),root);
fprintf('PHY_INVENTORY_INTEGRITY_PASS cases=%d rows_per_csv=%d chunk=127 scope=declared_publication_fixture_no_PHY root=%s\n', ...
    numel(names),n,root);
ok=true;
end

function summary=localReadClocks(path,expectedRows,expectedNote)
% Same quoted-reader contract as the production scanner, including multiline
% metadata. This is a file-level test, not in-memory string substitution.
fid=fopen(path,'rt','n','UTF-8');
assert(fid>=0,'Cannot open declared fixture.');
closer=onCleanup(@() fclose(fid));
header=erase(fgetl(fid),char(65279));
parsed=textscan(header,'%q','Delimiter',',','Whitespace','');
names=string(parsed{1}(:).'); clear closer;
ds=tabularTextDatastore(char(path),'Delimiter',',','ReadSize',127, ...
    'TextType','string','VariableNamingRule','preserve','ReadVariableNames',false, ...
    'NumHeaderLines',1,'VariableNames',cellstr(names), ...
    'TextscanFormats',repmat({'%q'},size(names)));
selected=[sixgr.truth.PHYDiagnosticClockContract.inputColumns(),"Notes"];
ds.SelectedVariableNames=cellstr(names(ismember(names,selected)));
state=sixgr.truth.PHYDiagnosticClockContract.initialize();
while hasdata(ds)
    chunk=read(ds);
    assert(all(string(chunk.Notes)==expectedNote), ...
        'test:DiagnosticQuotedFieldChanged','Embedded comma, quote or newline changed during import.');
    state=sixgr.truth.PHYDiagnosticClockContract.observe(state,chunk);
end
summary=sixgr.truth.PHYDiagnosticClockContract.summarize(state);
assert(summary.RowsChecked==expectedRows && summary.MaxChunkRows<=127);
end

function T=localFixture(n)
panels=repmat("time_domain",n,1);
panels(2:6)=["spectrum";"channel_estimate";"pre_equalization_re_cloud"; ...
    "post_equalization_constellation";"kpi"];
T=table(repmat("declared_inventory_fixture",n,1),panels,repmat("tx",n,1), ...
    (1:n)',zeros(n,1),ones(n,1),repmat("DL",n,1), ...
    repmat("runtime_same_trial_phy_signal_snapshot",n,1), ...
    repmat("real_lls_evidence",n,1),repmat("runtime_phy_arrays_same_trial",n,1), ...
    repmat("available",n,1),repmat(777,n,1),ones(n,1),ones(n,1), ...
    repmat(4660,n,1),repmat("declared_fixture_tb",n,1), ...
    'VariableNames',{'SnapshotID','Panel','Series','PointIndex','XValue','YValue', ...
    'Direction','CurveConstruction','truth_status','SourceArtifact','Status', ...
    'Frame','Slot','UEIndex','RNTI','TBId'});
T.CellID=ones(n,1); T.SFN=zeros(n,1); T.AbsoluteSlot=zeros(n,1);
T.CarrierNFrame=zeros(n,1); T.CarrierNSlot=zeros(n,1);
T.RuntimeAbsoluteSlotIndex0=zeros(n,1); T.SCS_kHz=repmat(30,n,1);
T.SlotsPerFrame=repmat(20,n,1);
T.SFNSource=repmat("executed_nrCarrierConfig_NFrame_mod1024",n,1);
T.SlotConvention=repmat("one_based_absolute_slot",n,1);
T.AbsoluteSlotConvention=repmat("zero_based_absolute_slot",n,1);
T.AbsoluteSlotSource=repmat("executed_runtime_absolute_slot_index0",n,1);
T.SampleIndex=(0:n-1)'; T.IValue=ones(n,1)/4; T.QValue=zeros(n,1);
T.Notes=repmat("declared fixture, ""quoted"" metadata"+newline+"not another record",n,1);
end
