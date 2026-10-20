function availability=phySignalDiagnosticAvailability(csvPath,imageDir)
% Same persisted-artifact contract, scanning all rows in bounded chunks.
availability=struct('Source',"not_available",'DL',"not_available", ...
    'UL',"not_available",'Reason',"source_csv_missing");
s=sixgr.truth.scanPHYSignalDiagnosticCSV(csvPath);
if s.RowCount==0, return; end
required=["SnapshotID","Panel","Series","PointIndex","XValue","YValue", ...
    "Direction","CurveConstruction","truth_status","SourceArtifact","Status"];
missing=required(~ismember(required,s.Columns));
if ~isempty(missing)
    availability.Reason="source_schema_missing:"+strjoin(missing,"|"); return;
end
flags=[s.TruthOK s.ConstructionOK s.SourceOK s.StatusOK s.DirectionOK];
failures=["truth_status_not_real_lls_evidence", ...
    "curve_construction_not_same_trial_runtime_snapshot", ...
    "source_artifact_not_runtime_phy_arrays_same_trial", ...
    "source_rows_not_available","source_direction_invalid"];
if ~all(flags), availability.Reason=failures(find(~flags,1)); return; end
requiredPanels=["time_domain","spectrum","channel_estimate", ...
    "pre_equalization_re_cloud","post_equalization_constellation","kpi"];
reasons=strings(0,1); valid=false;
for direction=["DL","UL"]
    d=s.(direction); why="";
    if d.RowCount==0, why="snapshot_missing";
    elseif d.SnapshotMissing || numel(d.SnapshotIDs)~=1, why="snapshot_id_not_unique";
    elseif ~all(ismember(requiredPanels,d.Panels)), why="essential_panel_missing";
    elseif ~d.TupleConsistent, why="trial_tuple_not_unique";
    else
        valid=true;
        info=dir(fullfile(imageDir,lower(direction)+"_phy_signal_diagnostic.png"));
        if ~isempty(info) && info(1).bytes>0
            availability.(direction)="derived";
        else, why="image_missing";
        end
    end
    if strlength(why)>0, reasons(end+1,1)=lower(direction)+"_"+why; end %#ok<AGROW>
end
if valid, availability.Source="observed"; end
availability.Reason=strjoin(reasons,"|");
end
