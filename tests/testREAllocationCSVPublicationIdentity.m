function ok=testREAllocationCSVPublicationIdentity()
% Exact resource-map CSVs are primary source bytes, not cosmetic UI tables.
root=tempname; mkdir(fullfile(root,'reports','csv'));
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
T=table([0;1],[0;0],[0;12],[12;12],[0;1],[1;1], ...
    [NaN;NaN],["";""],["";""],["000001";"000002"], ...
    repmat("exact_contiguous_re_run",2,1), ...
    'VariableNames',{'absolute_slot','port_index','subcarrier_start', ...
    'subcarrier_count','symbol_index','cell_id','ssb_index0', ...
    'waveform_port_domain','transmit_grid_sha256','allocation_id','coordinate_precision'});
names=["live_re_allocation_snapshot","observed_re_allocation"];
for name=names
    file=fullfile(root,'reports','csv',name+".csv");
    sixgr.util.csvWriteTable(file,T,'PreserveSchema',true);
    original=sixgr.util.sha256File(file);
    before=fileread(file);
    for pass=1:3
        if pass==1, result=sixgr.truth.sanitizeLLSArtifactCSVs(root,'OnlyPaths',file);
        elseif pass==2, result=sixgr.truth.sanitizeLLSArtifactCSVs(root,'OnlyPaths',char(file));
        else, result=sixgr.truth.sanitizeLLSArtifactCSVs(root); end
        row=result.Files(endsWith(result.Files.LogicalPath,name+".csv"),:);
        assert(height(row)==1 && ~row.Changed && row.RemovedColumnCount==0 && ...
            strcmp(original,sixgr.util.sha256File(file)) && strcmp(before,fileread(file)), ...
            'test:REAllocationPublicationMutation', ...
            'Do not prune/rewrite exact RE coordinates or absent beam/hash fields during publication.');
    end
    % The ownership/extension guards still apply to raw-schema artifacts.
    invalid=fullfile(root,'..','outside.csv');
    for pathValue={invalid,string(invalid)}
        try
            sixgr.truth.sanitizeLLSArtifactCSVs(root,'OnlyPaths',pathValue{1});
            error('test:MissingOwnedPathGuard','An outside-run path was accepted.');
        catch cause
            assert(strcmp(cause.identifier,'sixgr:truth:ArtifactCSVOutsideRun'),cause.message);
        end
    end
end
ok=true; fprintf('RE_ALLOCATION_CSV_PUBLICATION_IDENTITY_PASS coordinates=unchanged missing_fields=preserved bytes=identical\n');
end
