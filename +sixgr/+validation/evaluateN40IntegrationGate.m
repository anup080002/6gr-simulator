function out=evaluateN40IntegrationGate(runFolder,options)
%EVALUATEN40INTEGRATIONGATE Read retained execution, never repair or replay it.
% CRC failures are measured radio outcomes. Missing enabled-path coverage,
% software exceptions, identity mismatches and missing publication fail the
% integration gate separately. No minimum BLER or rank change is imposed.
arguments
    runFolder {mustBeTextScalar}
    options.CriteriaPath {mustBeTextScalar} = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), ...
        'simulator','configs','validation','n40_integration_gate.yaml')
    options.RequireContinuation (1,1) logical = true
end
c=sixgr.lls6g.config.readConfigFile(options.CriteriaPath);
assert(string(c.contract)=="sixgr.n40.integration_gate/v1", ...
    'sixgr:validation:N40GateCriteria','Unknown integration criteria contract.');
window=double([c.continuation_start_slot c.checkpoint_slot c.completed_slots]);
assert(all(isfinite(window))&&all(window==fix(window))&&window(1)>0&& ...
    window(1)<window(2)&&window(2)==window(3), ...
    'sixgr:validation:N40GateCriteria','Require an earlier continuation checkpoint and the terminal required checkpoint.');
root=string(runFolder); rows=repmat(emptyCheck(),0,1); radio=table(); children={};
identity=struct(); checkpoint=struct(); resumeCheckpoint=struct();
summaryPath=fullfile(root,'reports','csv','sweep_summary.csv');
if isfile(summaryPath) || isfolder(fullfile(root,'sweeps'))
    attempt('sweep_children','identity',summaryPath,@sweepChildren);
    attempt('sweep_artifact_index','publication',fullfile(root,'reports','csv','sweep_artifact_index.csv'),@sweepIndex);
    attempt('sweep_comparative_publication','publication',fullfile(root,'reports','sweep_comparison_receipt.json'),@sweepPublication);
else
    attempt('execution_identity','identity',fullfile(root,'meta','execution_identity.json'),@executionIdentity);
    attempt('completed_slots','coverage',fullfile(root,'reports','csv','live_stage_status.csv'),@completedSlots);
    for k=1:numel(c.primary_tables)
        spec=c.primary_tables(k);
        if iscell(c.primary_tables), spec=c.primary_tables{k}; end
        attempt("primary_"+string(spec.id),'physical_execution',fullfile(root,string(spec.path)),@()primary(spec));
    end
    for path=string(c.required_nonempty_tables(:)).'
        attempt("coverage_"+replace(path,'/','_'),'coverage',fullfile(root,path),@()nonempty(path));
    end
    attempt('access_complete','coverage',fullfile(root,'control','csv','rrc_setup_complete.csv'),@accessComplete);
    attempt('original_csi_binding','causality',fullfile(root,'air_interface','csv','csi_rs_trials.csv'),@originalCSIBinding);
    attempt('received_csi','causality',fullfile(root,'control','csv','received_csi_reports.csv'),@receivedCSI);
    attempt('completed_csi_application','causality',fullfile(root,'air_interface','csv','dl_pdsch_trials.csv'),@csiApplication);
    attempt('accepted_srs_application','causality',fullfile(root,'packet_flow','csv','live_ul_scheduler_grants.csv'),@srsApplication);
    attempt('executed_mcs_transitions','causality',fullfile(root,'air_interface','csv'),@executedMCSTransitions);
    attempt('checkpoint60','checkpoint',fullfile(root,'meta','latest_slot_checkpoint.json'),@checkpoint60);
    attempt('final_manifest','publication',fullfile(root,'meta','scenario_manifest.json'),@finalManifest);
    attempt('final_status_mirrors','publication',fullfile(root,'reports','csv','result_status_summary.csv'),@statusMirrors);
    attempt('causal_chain','publication',fullfile(root,'reports','csv','causal_phy_chain_gate.csv'),@causalGate);
    attempt('browser_publication','publication',fullfile(root,'published','browser_publication_receipt.json'),@browserPublication);
    if options.RequireContinuation
        attempt('actual_checkpoint_continuation','checkpoint',fullfile(root,'meta','n40_checkpoint_continuation.json'),@continuation);
    else
        r=emptyCheck(); r.CheckID="actual_checkpoint_continuation"; r.Category="checkpoint";
        r.Required=false; r.Status="NOT_EVALUATED"; r.Detail="Baseline evaluation cannot qualify continuation.";
        rows(end+1)=r;
    end
end
checks=struct2table(rows);
out=struct('ContractVersion',"sixgr.n40.integration_gate/v1", ...
    'RunFolder',root,'Ok',~isempty(rows)&&all(checks.Passed(checks.Required)), ...
    'FinalAccepted',false,'RequireContinuation',options.RequireContinuation, ...
    'Checks',checks,'RadioOutcomes',radio,'Identity',identity,'ChildResults',{children}, ...
    'CriteriaPath',string(options.CriteriaPath),'CriteriaSHA256',sixgr.util.sha256File(options.CriteriaPath), ...
    'StandardsConformanceQualified',false);
out.FinalAccepted=out.Ok && options.RequireContinuation;

    function attempt(id,category,path,action)
        r=emptyCheck(); r.CheckID=string(id); r.Category=string(category); r.Artifact=string(path);
        try
            r.Detail=string(action()); r.Passed=true; r.Status="PASS";
        catch cause
            r.Status="FAILED_EVIDENCE";
            if contains(cause.identifier,'Missing'), r.Status="MISSING_EVIDENCE"; end
            if contains(cause.identifier,'Identity'), r.Status="IDENTITY_MISMATCH"; end
            if contains(cause.identifier,'Software'), r.Status="SOFTWARE_FAILURE"; end
            if contains(cause.identifier,'RadioCoverage'), r.Status="RADIO_COVERAGE_INCOMPLETE"; end
            r.Detail=string(cause.identifier)+": "+string(cause.message);
        end
        rows(end+1)=r;
    end
    function detail=sweepChildren()
        T=readCSV(summaryPath); need(T,["Label","RunFolder","Returned","Ok","RunID","ConfigHash"]);
        labels=string(c.sweep_labels(:));
        require(height(T)==numel(labels)&&isequal(sort(string(T.Label)),sort(labels)), ...
            'Coverage','Require exactly the configured independent sweep children.');
        ids=strings(height(T),1); hashes=ids; executions=ids;
        allChildren=true;
        for j=1:height(T)
            childRoot=string(T.RunFolder(j));
            try
            require(startsWith(canonical(childRoot),canonical(fullfile(root,'sweeps'))+filesep), ...
                'Identity','Child folder is outside this sweep.');
            child=sixgr.validation.evaluateN40IntegrationGate(childRoot, ...
                'CriteriaPath',options.CriteriaPath,'RequireContinuation',options.RequireContinuation);
            children{end+1}=child;
            ids(j)=field(child.Identity,'RunID',""); hashes(j)=field(child.Identity,'ConfigHash',"");
            executions(j)=field(child.Identity,'ExecutionID',"");
            childConfig=readJSON(fullfile(childRoot,'meta','scenario_config_resolved.json'));
            labelIndex=find(labels==string(T.Label(j)));
            allChildren=allChildren && ids(j)==string(T.RunID(j)) && hashes(j)==string(T.ConfigHash(j)) && ...
                truth(T.Returned(j))&&truth(T.Ok(j))&&child.Ok && ...
                sixgr.util.structGet(childConfig,'simulation.snr_db',NaN)==double(c.sweep_snr_db(labelIndex));
            catch cause
                allChildren=false;
                r=emptyCheck(); r.CheckID="child_evaluation"; r.Category="identity"; r.Required=true;
                r.Status="FAILED_EVIDENCE"; r.Detail=string(cause.identifier)+": "+string(cause.message);
                if numel(children)<j
                    children{j}=struct('RunFolder',childRoot,'Ok',false,'Checks',struct2table(r));
                else
                    children{j}.Checks=[children{j}.Checks;struct2table(r)];
                end
            end
        end
        require(numel(unique(ids))==height(T)&&numel(unique(executions))==height(T), ...
            'Identity','Sweep children must have independent run and execution identities.');
        require(allChildren,'ChildFailure','One or more children failed acceptance/identity/configured SNR; inspect ChildResults.');
        detail="Both configured children passed independently.";
    end
    function detail=sweepIndex()
        S=readCSV(summaryPath);
        T=readCSV(fullfile(root,'reports','csv','sweep_artifact_index.csv'));
        need(T,["Label","PointRunID","PointConfigHash","ArtifactRole","RelativePath","Bytes","SHA256","EvidenceClass","ParentPrimaryWaveformRowsCopied"]);
        roles=string(c.parent_index_roles(:));
        require(height(T)==height(S)*numel(roles),'Coverage','Wrong parent artifact index count.');
        require(numel(unique(string(T.RelativePath)))==height(T),'Identity','Duplicate parent artifact paths.');
        for j=1:height(S)
            hit=string(T.Label)==string(S.Label(j));
            require(isequal(sort(string(T.ArtifactRole(hit))),sort(roles)),'Coverage','Missing or duplicate child artifact roles.');
            I=readJSON(fullfile(string(S.RunFolder(j)),'meta','execution_identity.json'));
            require(string(I.RunID)==string(S.RunID(j))&&string(I.ConfigHash)==string(S.ConfigHash(j)), ...
                'Identity','Summary child identity is stale.');
            require(all(string(T.PointRunID(hit))==string(I.RunID))&&all(string(T.PointConfigHash(hit))==string(I.ConfigHash)), ...
                'Identity','Parent index child identity differs.');
            for k=find(hit).'
                path=inside(root,T.RelativePath(k));
                require(startsWith(canonical(path),canonical(S.RunFolder(j))+filesep),'Identity','Indexed file belongs to a different child.');
                verifyFile(path,T.SHA256(k)); d=dir(path);
                require(d.bytes==num(T.Bytes(k)),'Identity','Indexed byte count differs.');
            end
        end
        require(all(string(T.EvidenceClass)=="measured_child_run_artifact")&&all(num(T.ParentPrimaryWaveformRowsCopied)==0), ...
            'Identity','Parent index mislabels child truth.');
        detail="Exact child identities, artifact roles/counts, bytes and SHA-256 verified.";
    end
    function detail=sweepPublication()
        R=readJSON(fullfile(root,'reports','sweep_comparison_receipt.json'));
        S=readCSV(summaryPath);
        T=readCSV(fullfile(root,'reports','csv','sweep_comparison_manifest.csv'));
        need(T,["SourceRelativePath","CombinedArtifact","SourcePoints","SourceSignature","OutputSHA256","Status","EvidenceClass"]);
        require(truth(R.Complete)&&R.CompletedPoints==numel(c.sweep_labels)&&R.TotalPoints==numel(c.sweep_labels)&& ...
            R.FailedArtifacts==0&&R.ArtifactCount==height(T)&&height(T)>0,'Publication','Incomplete comparative receipt/count.');
        require(all(string(T.Status)=="written")&&numel(unique(string(T.SourceRelativePath)))==height(T), ...
            'Publication','Failed or duplicate comparative outputs.');
        % Match Python json.dumps(sort_keys=True) v3 exactly. This selected
        % gate declares integer SNR values; Python number() serializes floats.
        labels=string(c.sweep_labels(:)); points=strings(numel(labels),1); childRoots=points;
        for j=1:numel(labels)
            hit=find(string(S.Label)==labels(j)); require(isscalar(hit),'Identity','Ambiguous sweep label.');
            childRoots(j)=string(S.RunFolder(hit)); status="failed"; if truth(S.Ok(hit)), status="passed"; end
            points(j)="["+j+", "+string(jsonencode(char(labels(j))))+", "+string(jsonencode(char(status)))+", "+sprintf('%.1f',c.sweep_snr_db(j))+"]";
        end
        actualSources=strings(0,1);
        for j=1:numel(childRoots)
            for extension=["*.csv","*.png"]
                listing=dir(fullfile(childRoots(j),'**',extension));
                for n=1:numel(listing)
                    absolute=string(fullfile(listing(n).folder,listing(n).name));
                    actualSources(end+1,1)=replace(extractAfter(absolute,strlength(childRoots(j))+1),'\','/'); %#ok<AGROW>
                end
            end
        end
        require(isequal(sort(unique(actualSources(:))),sort(string(T.SourceRelativePath(:)))), ...
            'Coverage','Comparative manifest omits or invents completed child artifacts.');
        for k=1:height(T)
            verifyFile(inside(root,T.CombinedArtifact(k)),T.OutputSHA256(k));
            sources=strings(0,1); indices=strings(0,1);
            for j=1:numel(labels)
                path=inside(childRoots(j),T.SourceRelativePath(k));
                if isfile(path)
                    sources(end+1)="["+j+", "+string(jsonencode(char(sixgr.util.sha256File(path))))+"]"; %#ok<AGROW>
                    indices(end+1)=string(j); %#ok<AGROW>
                end
            end
            require(~isempty(sources)&&strjoin(indices,'|')==string(T.SourcePoints(k)),'Identity','Comparative source membership differs.');
            token='{"points": ['+strjoin(points,', ')+'], "sources": ['+strjoin(sources,', ')+'], "version": 3}';
            require(jsonHash(token)==string(T.SourceSignature(k)),'Identity','Comparative source bytes/signature are stale.');
        end
        P=readCSV(fullfile(root,'reports','csv','sweep_measurement_plot_manifest.csv'));
        need(P,["CampaignCSV","CampaignPNG","ObservedRowCount"]);
        require(height(P)>0&&R.StandardizedMeasurementPlotCount==height(P),'Publication','Measurement plot count differs.');
        for j=1:height(P)
            V=readCSV(inside(root,P.CampaignCSV(j)));
            require(height(V)==num(P.ObservedRowCount(j)),'Publication','Measurement plot CSV row count differs.');
            require(isfile(inside(root,P.CampaignPNG(j))),'MissingArtifact','Missing measurement plot.');
        end
        for path=string(c.parent_required_plots(:)).'
            require(isfile(inside(root,path)),'MissingArtifact',"Missing required parent plot "+path);
        end
        detail="Comparative source/output hashes, exact counts and required plots verified.";
    end
    function detail=executionIdentity()
        identity=readJSON(fullfile(root,'meta','execution_identity.json'));
        for name=["RunID","ExecutionID","ConfigHash"]
            require(textPresent(field(identity,name,"")),'MissingIdentity',"Missing "+name);
        end
        require(isSHA(identity.ConfigHash),'Identity','ConfigHash must be SHA-256.');
        stored=readJSON(fullfile(root,'meta','scenario_config_identity.json'));
        require(string(field(stored,'ConfigHash',""))==string(identity.ConfigHash),'Identity','Resolved config identity differs.');
        % Re-encoding JSON can lose MATLAB array shape/NaN distinctions.
        % The original publisher's file seal is the byte-level authority.
        verifyFile(fullfile(root,'meta','scenario_config_resolved.json'),stored.ResolvedJSONSHA256);
        detail="Retained resolved scenario and execution identity agree.";
    end
    function detail=completedSlots()
        T=readCSV(fullfile(root,'reports','csv','live_stage_status.csv'));
        need(T,["CompletedSlots","TotalSlots"]);
        require(any(num(T.CompletedSlots)==c.completed_slots & num(T.TotalSlots)==c.completed_slots), ...
            'Coverage','The canonical owner has not completed the requested slot horizon.');
        S=readCSV(fullfile(root,'reports','csv','slot_trace.csv')); need(S,"CanonicalSlot");
        slots=unique(num(S.CanonicalSlot));
        require(all(ismember((1:c.completed_slots).',slots)),'Coverage','Canonical slot trace has a missing slot.');
        require(~isfile(fullfile(root,'meta','sweep_execution_failure.json')),'SoftwareFailure','Retained sweep exception exists.');
        detail="Every canonical slot through the configured horizon is retained.";
    end
    function detail=primary(spec)
        T=readCSV(fullfile(root,string(spec.path))); require(~isempty(T),'MissingRows','Enabled physical path has no rows.');
        checkIdentity(T);
        if ismember('Crash',T.Properties.VariableNames)
            require(all(num(T.Crash)==0),'SoftwareFailure',"Crashes in "+string(spec.id));
        end
        if ismember('Status',T.Properties.VariableNames)
            require(~any(contains(upper(string(T.Status)),["CRASH","EXCEPTION"])),'SoftwareFailure','Software failure status in primary table.');
        end
        if ismember('FallbackFlag',T.Properties.VariableNames)
            require(all(num(T.FallbackFlag)==0),'Proxy','Primary execution includes fallback rows.');
        end
        if ismember('ApproximationMode',T.Properties.VariableNames)
            token=lower(strtrim(string(T.ApproximationMode)));
            require(~any(ismember(token,["proxy","fast_proxy","synthetic","fallback","logistic","lut"])),'Proxy','Approximate rows in waveform evidence.');
        end
        attempted=NaN; passed=NaN; failed=NaN;
        if all(ismember({'CRCApplicable','CRCPass'},T.Properties.VariableNames))
            applicable=num(T.CRCApplicable)==1; values=num(T.CRCPass);
            require(all(ismember(values(applicable),[0 1])),'Malformed','Applicable CRC must be an observed Boolean.');
            attempted=nnz(applicable); passed=nnz(applicable & values==1); failed=nnz(applicable & values==0);
        end
        R=table(string(spec.id),height(T),attempted,passed,failed, ...
            'VariableNames',{'Signal','Rows','ApplicableCRCCount','CRCPassCount','CRCFailCount'});
        radio=[radio;R];
        detail="Retained "+height(T)+" physical rows; observed CRC failures are not software failures.";
    end
    function detail=nonempty(path)
        T=readCSV(fullfile(root,path)); require(~isempty(T),'MissingRows','Required executed path has no rows.');
        detail="Retained "+height(T)+" rows.";
    end
    function detail=accessComplete()
        T=readCSV(fullfile(root,'control','csv','rrc_setup_complete.csv')); need(T,["RunId","Decoded"]);
        require(all(string(T.RunId)==string(field(identity,'RunID',""))),'Identity','Access belongs to another run.');
        require(any(num(T.Decoded)==1),'RadioCoverage','No received RRC setup completion; access coverage incomplete.');
        detail="Received bounded RRC setup completion (not ASN.1 interoperability qualification).";
    end
    function detail=originalCSIBinding()
        T=readCSV(fullfile(root,'air_interface','csv','csi_rs_trials.csv'));
        need(T,["Slot","UEIndex","ServingCell","CellID","ReceiverID", ...
            "ObservationSampleRateHz","MeasurementClockEpoch","CSIObservationPopulationBindingJSON", ...
            "PhysicalMeasurementPlaneBindingJSON","PhysicalMeasurementPlaneBindingSHA256", ...
            "ReceiverWindowID","ObservationStartSample","ObservationEndSampleExclusive", ...
            "DLMeasurementAuthorityRequired","DLMeasurementAuthorityEligible", ...
            "DLMeasurementAuthorityStatus","DLMeasurementInstallationSHA256"]);
        require(~isempty(T),'MissingCoverage','No original CSI receiver observations.');
        for j=1:height(T)
            status=string(T.DLMeasurementAuthorityStatus(j));
            require(status~="missing_original_DL_measurement_configuration_binding", ...
                'Identity','Original CSI configuration/cell binding was absent at authority stamping.');
            planeToken=string(T.PhysicalMeasurementPlaneBindingJSON(j));
            require(jsonHash(planeToken)==string(T.PhysicalMeasurementPlaneBindingSHA256(j)), ...
                'Identity','Original CSI receiver-plane seal differs.');
            p=jsondecode(planeToken);
            require(string(p.ContractVersion)=="sixgr.csirs.original_measurement_plane/v1"&& ...
                string(p.ReceiverID)==string(T.ReceiverID(j))&&string(p.ReceiverWindowID)==string(T.ReceiverWindowID(j))&& ...
                p.ObservationStartSample==num(T.ObservationStartSample(j))&& ...
                p.ObservationEndSampleExclusive==num(T.ObservationEndSampleExclusive(j))&& ...
                p.SampleRateHz==num(T.ObservationSampleRateHz(j)), ...
                'Identity','CSI receiver identity/window differs from its original sealed plane receipt.');
            b=jsondecode(string(T.CSIObservationPopulationBindingJSON(j)));
            require(num(T.ServingCell(j))==num(T.CellID(j))&&num(T.ServingCell(j))==b.ServingCell&& ...
                num(T.Slot(j))==b.SourceSlot&&num(T.ObservationSampleRateHz(j))==b.SampleRateHz&& ...
                num(T.MeasurementClockEpoch(j))==b.PhysicalConfigurationEpoch&&textPresent(T.ReceiverID(j)), ...
                'Identity','Original CSI row disagrees with queued/completed physical cell or clock binding.');
            required=num(T.DLMeasurementAuthorityRequired(j)); eligible=num(T.DLMeasurementAuthorityEligible(j));
            require(ismember(required,[0 1])&&ismember(eligible,[0 1]),'Identity','Missing original CSI authority flags.');
            if required==1
                if eligible==1
                    require(status=="post_installation_original_received_measurement"&& ...
                        isSHA(T.DLMeasurementInstallationSHA256(j)),'Identity','Eligible CSI lacks its original installation authority.');
                else
                    require(ismember(status,string(c.csi_diagnostic_authority_statuses)), ...
                        'Identity','Ineligible CSI has inconsistent original installation authority.');
                end
            end
        end
        detail="Original CSI cell/clock binding and installation authority status are consistent; diagnostic observations remain ineligible.";
    end
    function detail=receivedCSI()
        T=readCSV(fullfile(root,'control','csv','received_csi_reports.csv'));
        need(T,["ReportIdentity","ObservationID","CSIUCIDecodeOk","DeliveryStatus"]);
        delivered=num(T.CSIUCIDecodeOk)==1 & string(T.DeliveryStatus)=="delivered_to_runtime_scheduler";
        require(any(delivered),'RadioCoverage','No independently decoded CSI report delivered to the scheduler.');
        require(all(strlength(string(T.ObservationID(delivered)))>0),'MissingIdentity','Delivered report lacks receiver observation.');
        if ismember('ExecutionID',T.Properties.VariableNames)
            require(all(string(T.ExecutionID(delivered))==string(identity.ExecutionID)),'Identity','CSI execution differs.');
        end
        detail="Decoded CSI delivery retained; rejected or censored reports are not converted to successes.";
    end
    function detail=csiApplication()
        T=readCSV(fullfile(root,'air_interface','csv','dl_pdsch_trials.csv'));
        need(T,["CompletedCSIApplicationVerified","CompletedCSIApplicationEvidenceJSON", ...
            "CompletedCSIApplicationEvidenceSHA256","CompletedCSIApplicationReportIdentity", ...
            "CompletedCSIApplicationReportObservationID"]);
        R=readCSV(fullfile(root,'control','csv','received_csi_reports.csv'));
        need(R,["ReportIdentity","ObservationID","CSIUCIDecodeOk","DeliveryStatus"]);
        chosen=find(num(T.CompletedCSIApplicationVerified)==1); require(~isempty(chosen),'MissingCoverage','No completed CSI-to-PDSCH application.');
        for j=chosen.'
            token=string(T.CompletedCSIApplicationEvidenceJSON(j));
            require(jsonHash(token)==string(T.CompletedCSIApplicationEvidenceSHA256(j)),'Identity','Completed CSI capsule hash differs.');
            e=jsondecode(token); a=e.AdmittedCSI;
            hit=string(R.ReportIdentity)==string(a.ReportIdentity) & string(R.ObservationID)==string(a.ObservationID);
            require(nnz(hit)==1 && num(R.CSIUCIDecodeOk(hit))==1 && ...
                string(R.DeliveryStatus(hit))=="delivered_to_runtime_scheduler",'Identity','Application does not join one received CSI report.');
            require(a.AvailableAtSample<=e.DecisionClock.AtSample && ...
                e.DecisionClock.AtSample<=e.FirstActiveSample && e.FirstActiveSample<e.CompletedAtSample, ...
                'Causality','CSI application precedes received information or physical completion.');
            require(truth(e.WaveformApplicationVerified)&&e.AdditionalPHYExecutions==0, ...
                'Coverage','CSI application must belong to the original completed waveform.');
            frozen=field(e,'FrozenApplication',struct());
            require(string(field(frozen,'ReportIdentity',""))==string(a.ReportIdentity) && ...
                string(field(frozen,'ObservationID',""))==string(a.ObservationID) && ...
                string(T.CompletedCSIApplicationReportIdentity(j))==string(a.ReportIdentity) && ...
                string(T.CompletedCSIApplicationReportObservationID(j))==string(a.ObservationID), ...
                'Identity','Frozen CSI operands and published row must retain the admitted report identity.');
            % This n40 Type-I scheduler admits an atomic RI/PMI/CRI tuple.
            % Rank deferral retains the entire previous accepted report.
            for name=["RI","PMI","CRI"]
                require(sameFinite(field(frozen,"Reported"+name,NaN),field(a,name,NaN)), ...
                    'Identity',"Frozen reported "+name+" differs from the admitted CSI report.");
            end
            require(sameFinite(field(frozen,'FrozenNumLayers',NaN),a.RI) && ...
                sameFinite(field(frozen,'FrozenPMI',NaN),a.PMI) && ...
                sameFinite(field(frozen,'FrozenCSIResourceIndex',NaN),a.CRI), ...
                'Identity','Frozen selected CSI rank/PMI/resource identity is missing or differs from the admitted tuple.');
            need(T,"Layers");
            require(sameFinite(T.Layers(j),field(frozen,'FrozenNumLayers',NaN)), ...
                'Identity','Completed PDSCH layer count differs from the frozen selected CSI rank.');
        end
        detail="Verified original completed CSI-to-PDSCH capsules: "+numel(chosen);
    end
    function detail=srsApplication()
        G=readCSV(fullfile(root,'packet_flow','csv','live_ul_scheduler_grants.csv'));
        need(G,["Slot","GrantContextId","AcceptedSRSSpatialDecisionJSON","AcceptedSRSSpatialDecisionSHA256"]);
        U=readCSV(fullfile(root,'air_interface','csv','ul_pusch_trials.csv')); need(U,["GrantContextId","Slot","DecodeAttempted"]);
        S=readCSV(fullfile(root,'control','csv','srs_trials.csv'));
        need(S,["Slot","UEIndex","RNTI","SRSConfigurationContextID","ObservationStartSample","ObservationEndSampleExclusive"]);
        chosen=find(strlength(strtrim(string(G.AcceptedSRSSpatialDecisionJSON)))>0);
        joined=0;
        for j=chosen.'
            token=string(G.AcceptedSRSSpatialDecisionJSON(j)); e=jsondecode(token);
            require(jsonHash(token)==string(G.AcceptedSRSSpatialDecisionSHA256(j)),'Identity','Accepted SRS capsule hash differs.');
            require(e.AvailableSlot<=num(G.Slot(j)) && e.ProducerSlot<=e.AvailableSlot, ...
                'Causality','UL grant used unavailable SRS information.');
            source=num(S.Slot)==e.ProducerSlot & num(S.UEIndex)==e.TargetId & num(S.RNTI)==e.RNTI & ...
                string(S.SRSConfigurationContextID)==string(e.SRSConfigurationContextID) & ...
                num(S.ObservationStartSample)==e.ObservationStartSample & ...
                num(S.ObservationEndSampleExclusive)==e.ObservationEndSampleExclusive;
            require(nnz(source)==1,'Identity','Accepted SRS capsule does not join one actual receiver observation.');
            hit=string(U.GrantContextId)==string(G.GrantContextId(j)) & num(U.Slot)==num(G.Slot(j)) & num(U.DecodeAttempted)==1;
            joined=joined+nnz(hit);
        end
        require(joined>0,'MissingCoverage','No retained accepted SRS decision joins an executed PUSCH receiver attempt.');
        detail="Accepted SRS decisions joined to completed PUSCH trials: "+joined;
    end
    function detail=executedMCSTransitions()
        config=readJSON(fullfile(root,'meta','scenario_config_resolved.json'));
        policy=sixgr.util.structGet(config,'link_adaptation.mcs_transition',struct());
        require(truth(field(policy,'enabled',false)),'Coverage', ...
            'Selected n40 acceptance requires the configured MCS transition policy.');
        defaults=sixgr.config.defaultConfig();
        bootstrap=double(sixgr.util.structGet(config,'link_adaptation.bootstrap_mcs_index', ...
            sixgr.util.structGet(config,'link_adaptation.bootstrapMCSIndex', ...
            defaults.phy.linkAdaptation.bootstrapMCSIndex)));
        slotSeconds=double(sixgr.util.structGet(config,'frame_timing.slot_duration_ms',NaN))/1000;
        require(isscalar(bootstrap)&&isfinite(bootstrap)&&bootstrap>=0&&bootstrap==fix(bootstrap)&& ...
            isscalar(slotSeconds)&&isfinite(slotSeconds)&&slotSeconds>0, ...
            'Causality','Require the configured bootstrap MCS and canonical slot duration.');
        count=0;
        for direction=["DL","UL"]
            file="dl_pdsch_trials.csv";
            if direction=="UL", file="ul_pusch_trials.csv"; end
            T=readCSV(fullfile(root,'air_interface','csv',file));
            need(T,["Slot","RNTI","ServingCell","GrantContextId","HarqID","MCSIndex","IsRetransmission", ...
                "MCSTransitionReceiptJSON","MCSTransitionReceiptSHA256","MCSTransitionAppliedMCS"]);
            checkIdentity(T);
            chosen=find(num(T.IsRetransmission)==0);
            require(~isempty(chosen),'MissingCoverage','No executed new-data MCS policy evidence.');
            [~,order]=sort(num(T.Slot(chosen))); chosen=chosen(order);
            records=struct('ID',{},'Scope',{},'Point',{},'MCS',{},'Generation',{},'Slot',{},'PID',{},'Context',{},'Row',{});
            feedbackPath=fullfile(root,'control','csv','gnb_harq_feedback_observations.csv');
            if direction=="UL", feedbackPath=fullfile(root,'harq','csv','runtime_harq_process_timeline.csv'); end
            feedback=table();
            if isfile(feedbackPath), feedback=readCSV(feedbackPath); end
            for j=chosen.'
                token=string(T.MCSTransitionReceiptJSON(j));
                require(textPresent(token)&&jsonHash(token)==string(T.MCSTransitionReceiptSHA256(j)), ...
                    'Identity','Executed MCS transition receipt is missing or corrupt.');
                e=jsondecode(token);
                require(truth(e.Enabled)&&string(e.Direction)==direction && ...
                    sameFinite(e.DataSlot,T.Slot(j))&&sameFinite(e.RNTI,T.RNTI(j))&& ...
                    sameFinite(e.ServingCell,T.ServingCell(j))&& ...
                    string(e.GrantContextId)==string(T.GrantContextId(j)) && ...
                    sameFinite(e.AppliedMCS,T.MCSIndex(j))&&sameFinite(e.AppliedMCS,T.MCSTransitionAppliedMCS(j)), ...
                    'Identity','MCS receipt does not belong to the original executed grant.');
                require(sameFinite(e.MaxUpStep,policy.max_up_step)&& ...
                    sameFinite(e.MaxDownStep,policy.max_down_step)&& ...
                    sameFinite(e.RequiredACKCount,policy.increase_ack_count), ...
                    'Identity','Executed MCS policy differs from resolved configuration.');
                operands=[e.RawTargetMCS e.EffectivePreviousMCS e.PolicySelectedMCS e.AppliedMCS e.ACKCount e.NACKCount];
                require(all(isfinite(operands)&operands>=0&operands==fix(operands)) && ...
                    isfinite(e.DecisionSlot)&&e.DecisionSlot>=1&&e.DecisionSlot==fix(e.DecisionSlot)&& ...
                    e.DecisionSlot<=e.DataSlot && textPresent(e.RawTargetAuthority), ...
                    'Causality','MCS transition has unavailable operands or an invalid decision clock.');
                scope=direction+"|cell="+string(e.ServingCell)+"|rnti="+string(e.RNTI);
                require(string(e.ScopeKey)==scope&&textPresent(e.SpatialPoint),'Identity', ...
                    'MCS receipt has a different scope or missing spatial operating point.');
                previous=find(string({records.Scope})==scope,1,'last');
                previousMCS=bootstrap; generation=0;
                if isempty(previous)
                    require(mcsGateNullNumber(e.PreviousCommittedMCS),'Identity', ...
                        'The first executed transmission cannot claim a prior committed MCS.');
                else
                    previousMCS=records(previous).MCS; generation=records(previous).Generation;
                    require(sameFinite(e.PreviousCommittedMCS,previousMCS)&& ...
                        records(previous).Slot<=e.DecisionSlot,'Causality', ...
                        'The MCS anchor differs from the preceding actual committed transmission.');
                end
                require(sameFinite(e.EffectivePreviousMCS,previousMCS)&& ...
                    sameFinite(e.OperatingPointGeneration,generation),'Identity', ...
                    'MCS anchor/generation was not derived from the actual transmitted history.');
                require(numel(unique(string(e.ACKIdentities)))==e.ACKCount&& ...
                    numel(unique(string(e.NACKIdentities)))==e.NACKCount, ...
                    'Identity','MCS feedback counts differ from retained used identities.');
                require(isempty(intersect(string(e.ACKIdentities),string(e.NACKIdentities))), ...
                    'Identity','One feedback event cannot be both ACK and NACK.');
                for outcome=["ACK","NACK"]
                    used=string(e.(outcome+"Identities"));
                    for id=reshape(used,1,[])
                        source=find(string({records.ID})==id);
                        require(numel(source)==1,'Identity','Used MCS feedback has no unique original executed transmission.');
                        source=records(source);
                        require(source.Scope==scope&&source.Point==string(e.SpatialPoint)&& ...
                            source.MCS==previousMCS&&source.Generation==generation, ...
                            'Causality','Used feedback belongs to a different spatial point, MCS or transmission generation.');
                        mcsGateFeedback(feedback,T,source,direction,outcome,e.DecisionSlot,slotSeconds);
                    end
                end
                require(e.PolicySelectedMCS<=e.RawTargetMCS && e.AppliedMCS<=e.PolicySelectedMCS && ...
                    truth(e.FinalCapacityReduction)==(e.AppliedMCS<e.PolicySelectedMCS), ...
                    'Identity','Final MCS exceeds its policy/capacity ceiling.');
                if e.PolicySelectedMCS>e.EffectivePreviousMCS
                    require(e.PolicySelectedMCS-e.EffectivePreviousMCS<=e.MaxUpStep && ...
                        e.ACKCount>=e.RequiredACKCount&&e.NACKCount==0 && ...
                        string(e.Reason)=="received_ACK_confirmed_up_step", ...
                        'Causality','MCS increase lacks bounded, confirmed received feedback.');
                end
                if e.NACKCount>0
                    require(e.PolicySelectedMCS<=min(e.RawTargetMCS,max(0,e.EffectivePreviousMCS-e.MaxDownStep)), ...
                        'Causality','Received NACK did not reduce the admissible new-data MCS.');
                end
                pid=num(T.HarqID(j));
                require(isscalar(pid)&&isfinite(pid)&&pid>=0&&pid==fix(pid),'Identity', ...
                    'Executed MCS evidence requires the original HARQ process.');
                id=scope+"|slot="+string(e.DataSlot)+"|pid="+string(pid);
                require(~any(string({records.ID})==id),'Identity','Duplicate executed new-data MCS identity.');
                if isempty(previous)||records(previous).Point~=string(e.SpatialPoint)||previousMCS~=e.AppliedMCS
                    generation=generation+1;
                end
                records(end+1)=struct('ID',id,'Scope',scope,'Point',string(e.SpatialPoint), ...
                    'MCS',e.AppliedMCS,'Generation',generation,'Slot',e.DataSlot,'PID',pid, ...
                    'Context',string(e.GrantContextId),'Row',j); %#ok<AGROW>
                count=count+1;
            end
        end
        detail="Original executed MCS transition receipts verified: "+count;
    end
    function detail=checkpoint60()
        base=sixgr.runtime.SlotCheckpoint.storageRoot(root);
        latest=readJSON(fullfile(root,'meta','latest_slot_checkpoint.json'));
        require(latest.CompletedSlotOneBased==c.checkpoint_slot && latest.NextSlotOneBased==c.checkpoint_slot+1, ...
            'Coverage','The current child must retain its actual terminal checkpoint pointer.');
        % Original and resumed terminal generations coexist. The restored
        % child pointer, not directory order, owns the current endpoint.
        checkpoint=verifyCheckpoint(base,c.checkpoint_slot,string(latest.Checkpoint));
        resumeCheckpoint=verifyCheckpoint(base,c.continuation_start_slot,"");
        require(string(checkpoint.Source.SHA256)==string(resumeCheckpoint.Source.SHA256), ...
            'Identity','Continuation and terminal checkpoints have different source inventories.');
        detail="Original continuation and selected terminal checkpoint payload/config/source bytes verified.";
    end
    function record=verifyCheckpoint(base,slot,selected)
        entries=dir(fullfile(base,sprintf('after_slot_%06d_*',slot),'checkpoint.json'));
        paths=strings(numel(entries),1);
        for j=1:numel(entries), paths(j)=canonical(fullfile(entries(j).folder,'state.mat')); end
        if strlength(selected)>0
            hit=paths==canonical(selected);
            require(nnz(hit)==1,'Identity','Terminal pointer must select one retained checkpoint of the required slot.');
            path=paths(hit);
        else
            require(numel(paths)==1,'MissingCheckpoint','Require exactly one original continuation checkpoint.');
            path=paths(1);
        end
        record=readJSON(fullfile(fileparts(path),'checkpoint.json'));
        require(record.CompletedSlotOneBased==slot && record.NextSlotOneBased==slot+1 && ...
            string(record.Status)=="complete",'Coverage','Checkpoint receipt has the wrong completed/next slot or status.');
        verifyFile(path,record.StateSHA256);
        verifyFile(fullfile(fileparts(path),record.ScientificScenarioFile),record.ScientificScenarioSHA256);
        require(canonical(record.RunFolder)==canonical(root),'Identity','Checkpoint belongs to another child.');
        repo=fileparts(fileparts(fileparts(mfilename('fullpath'))));
        require(~isempty(record.Source.Files),'MissingSource','Checkpoint source inventory is absent.');
        for j=1:numel(record.Source.Files)
            verifyFile(fullfile(repo,record.Source.Files(j).Path),record.Source.Files(j).SHA256);
        end
    end
    function detail=finalManifest()
        M=readJSON(fullfile(root,'meta','scenario_manifest.json'));
        require(string(field(M,'ExecutionID',""))==string(field(identity,'ExecutionID',"")),'Identity','Manifest execution differs.');
        for name=string(c.manifest_true_fields(:)).'
            require(isfield(M,name)&&truth(M.(name)),'Publication',"Required manifest field not true: "+name);
        end
        for name=string(c.manifest_zero_fields(:)).'
            require(isfield(M,name)&&isnumeric(M.(name))&&isscalar(M.(name))&&M.(name)==0, ...
                'Publication',"Required failure count not zero: "+name);
        end
        detail="All configured terminal truth/objective/publication gates passed.";
    end
    function detail=causalGate()
        T=readCSV(fullfile(root,'reports','csv','causal_phy_chain_gate.csv'));
        need(T,["Pass","RunID","ConfigHash"]);
        require(~isempty(T)&&all(num(T.Pass)==1),'Coverage','Causal PHY chain gate failed.');
        require(all(string(T.RunID)==string(identity.RunID))&&all(string(T.ConfigHash)==string(identity.ConfigHash)), ...
            'Identity','Causal gate belongs to another execution configuration.');
        detail="Required causal chain evidence passed.";
    end
    function detail=statusMirrors()
        T=readCSV(fullfile(root,'reports','csv','result_status_summary.csv'));
        M=readJSON(fullfile(root,'reports','json','result_status_summary.json'));
        require(height(T)==1,'Malformed','Canonical final status must contain exactly one row.');
        for name=["ResultOk","RuntimeTruthContractOk","PublicationQualified","ScenarioObjectiveOk"]
            need(T,name);
            require(isfield(M,name)&&truth(T.(name))&&truth(M.(name)), ...
                'Publication',"Final CSV/JSON verdict missing or disagrees: "+name);
        end
        detail="Canonical final CSV and JSON status both retain successful required verdicts.";
    end
    function detail=browserPublication()
        M=readJSON(fullfile(root,'published','browser_publication_receipt.json'));
        require(string(M.RunID)==string(identity.RunID),'Identity','Publication belongs to another run.');
        require(string(M.Status)=="PASS" && truth(M.BrowserMaterialized) && ...
            M.MissingRequiredTableCount==0 && M.MissingRequiredChartCount==0, ...
            'Publication','Required tables/charts were not materialized.');
        backend=string(M.PublicationBackend);
        require((backend=="filesystem"&&truth(M.FilesystemPersisted)) || ...
            (backend=="mysql_web"&&truth(M.DatabasePersisted)), ...
            'Publication','Publication backend has no successful persistence receipt.');
        detail="Required browser CSV/chart publication has a successful retained receipt.";
    end
    function detail=continuation()
        M=readJSON(fullfile(root,'meta','n40_checkpoint_continuation.json'));
        require(string(M.ContractVersion)=="sixgr.n40.checkpoint_continuation/v1" && ...
            truth(M.Ok)&&truth(M.Compared)&&truth(M.Equivalent),'Coverage','Actual baseline/resume comparison did not pass.');
        for name=["RunID","ExecutionID","ConfigHash"]
            require(string(field(M,name,""))==string(field(identity,name,"")) && textPresent(field(M,name,"")), ...
                'Identity',"Continuation identity differs: "+name);
        end
        require(M.CheckpointSlot==c.continuation_start_slot && M.NextSlot==c.continuation_start_slot+1 && M.FinalCompletedSlot==c.completed_slots, ...
            'Coverage','Continuation did not cross the configured checkpoint-to-terminal boundary.');
        require(string(M.CheckpointStateSHA256)==string(field(resumeCheckpoint,'StateSHA256',"")) && ...
            string(M.SourceSHA256)==string(field(field(resumeCheckpoint,'Source',struct()),'SHA256',"")), ...
            'Identity','Continuation checkpoint/source differs.');
        verifyFile(M.ChecksPath,M.ChecksSHA256); verifyFile(M.BaselineInventoryPath,M.BaselineInventorySHA256);
        verifyFile(M.ResumedAcceptancePath,M.ResumedAcceptanceSHA256);
        A=readJSON(M.ResumedAcceptancePath);
        require(truth(A.Ok),'Coverage','Resumed final reports failed acceptance.');
        require(canonical(M.ReferenceFolder)==canonical(root),'Identity','Continuation baseline folder differs.');
        C=readCSV(M.ChecksPath); need(C,"Passed"); require(~isempty(C)&&all(num(C.Passed)==1),'Coverage','Continuation comparison contains missing/failed checks.');
        detail="Actual same-lineage checkpoint continuation compared successfully.";
    end
    function checkIdentity(T)
        need(T,["RunID","ExecutionID","ConfigHash"]);
        for name=["RunID","ExecutionID","ConfigHash"]
            expected=string(field(identity,name,""));
            require(textPresent(expected)&&all(string(T.(name))==expected),'Identity',"Primary rows disagree on "+name);
        end
    end
end

function mcsGateFeedback(F,T,source,direction,outcome,decisionSlot,slotSeconds)
% Join an original policy credit to receiver evidence. DL observes decoded
% UCI, which need not equal the hidden PDSCH CRC; UL uses the gNB decoder.
require(~isempty(F),'MissingEvidence','Used MCS feedback has no retained receiver evidence.');
decisionSeconds=(decisionSlot-1)*slotSeconds;
if direction=="DL"
    need(F,["SourceSlot","RNTI","ServingCell","HarqID","PHYGrantContextId", ...
        "FeedbackOutcome","HARQFeedbackApplied","ReceiverUsable","StaleFeedbackIgnored", ...
        "DecodeAttempted","ReceiverExecutionStatus","IsRetransmission","DueSlot", ...
        "Slot","AvailableAtSample","ObservationSampleRateHz"]);
    hit=num(F.SourceSlot)==source.Slot & num(F.RNTI)==num(T.RNTI(source.Row)) & ...
        num(F.ServingCell)==num(T.ServingCell(source.Row)) & num(F.HarqID)==source.PID & ...
        string(F.PHYGrantContextId)==source.Context;
    require(nnz(hit)==1,'Identity','Used DL MCS feedback does not join one original received UCI outcome.');
    r=F(hit,:);
    require(string(r.FeedbackOutcome)==outcome&&num(r.HARQFeedbackApplied)==1&& ...
        num(r.ReceiverUsable)==1&&num(r.StaleFeedbackIgnored)==0&& ...
        num(r.DecodeAttempted)==1&&string(r.ReceiverExecutionStatus)=="executed"&& ...
        num(r.IsRetransmission)==0,'Causality', ...
        'Used DL MCS feedback was not the applied, usable original receiver outcome.');
    available=num(r.AvailableAtSample); fs=num(r.ObservationSampleRateHz);
    due=num(r.DueSlot); delivered=num(r.Slot);
    require(isfinite(due)&&isfinite(delivered)&&source.Slot<=due&&due<=delivered&& ...
        delivered<=decisionSlot,'Causality','DL MCS feedback was not due/delivered before its control decision.');
else
    need(T,["CRCPass","HARQFeedbackDueSlot","DataDecodeAvailableAtSample","DataReceiveSampleRateHz"]);
    need(F,["Direction","RNTI","Slot","HarqID","PHYGrantContextId","IsRetransmission", ...
        "CurrentDecodeOK","FeedbackDueSlot","DataDecodeAvailableAtSample", ...
        "DataReceiveSampleRateHz","FeedbackMechanism","FeedbackEvidenceSource"]);
    hit=string(F.Direction)=="UL" & num(F.Slot)==source.Slot & ...
        num(F.RNTI)==num(T.RNTI(source.Row)) & num(F.HarqID)==source.PID & ...
        string(F.PHYGrantContextId)==source.Context;
    require(nnz(hit)==1,'Identity','Used UL MCS feedback does not join one original PUSCH decoder attempt.');
    r=F(hit,:); crc=num(T.CRCPass(source.Row));
    require(any(crc==[0 1])&&num(r.CurrentDecodeOK)==crc&& ...
        (outcome=="ACK")==logical(crc)&&num(r.IsRetransmission)==0&& ...
        string(r.FeedbackMechanism)=="gnb_pusch_decoder"&& ...
        string(r.FeedbackEvidenceSource)=="same_waveform_pusch_rx_crc", ...
        'Causality','Used UL MCS outcome differs from the actual gNB PUSCH decoder.');
    available=num(r.DataDecodeAvailableAtSample); fs=num(r.DataReceiveSampleRateHz);
    due=num(r.FeedbackDueSlot);
    require(sameFinite(available,num(T.DataDecodeAvailableAtSample(source.Row)))&& ...
        sameFinite(fs,num(T.DataReceiveSampleRateHz(source.Row)))&& ...
        sameFinite(due,num(T.HARQFeedbackDueSlot(source.Row)))&& ...
        source.Slot<=due&&due<=decisionSlot,'Causality', ...
        'Used UL decoder feedback was not available at its original configured delivery boundary.');
end
require(isscalar(available)&&isfinite(available)&&available>=0&& ...
    isscalar(fs)&&isfinite(fs)&&fs>0&&available/fs<=decisionSeconds+1e-12, ...
    'Causality','MCS feedback receiver completion is later than the actual control decision.');
end

function tf=mcsGateNullNumber(value)
tf=isempty(value)||(isnumeric(value)&&isscalar(value)&&isnan(value));
end

function r=emptyCheck()
r=struct('CheckID',"",'Category',"",'Status',"NOT_EVALUATED", ...
    'Passed',false,'Required',true,'Artifact',"",'Detail',"");
end
function T=readCSV(path)
require(isfile(path),'MissingArtifact',"Missing "+string(path));
% All retained exports are comma-delimited with one explicit header row.
% Do not infer headers or numeric types from a small mixed identity table:
% hashes/IDs can look numeric and must retain their exact serialized text.
opts=detectImportOptions(path,'FileType','text','Delimiter',',', ...
    'VariableNamesLine',1,'VariableNamingRule','preserve');
opts.DataLines=[2 Inf];
opts=setvartype(opts,opts.VariableNames,'string');
opts=setvaropts(opts,opts.VariableNames,'WhitespaceRule','preserve');
T=readtable(path,opts);
end
function M=readJSON(path)
require(isfile(path),'MissingArtifact',"Missing "+string(path)); M=jsondecode(fileread(path));
end
function need(T,names)
require(all(ismember(string(names),string(T.Properties.VariableNames))),'MissingColumns', ...
    "Required columns: "+strjoin(string(names),', '));
end
function require(ok,id,message)
assert(isscalar(ok)&&ok,"sixgr:validation:N40Gate"+id,'%s',message);
end
function v=field(s,name,fallback)
v=fallback; if isstruct(s)&&isscalar(s)&&isfield(s,name), v=s.(name); end
end
function n=num(v)
if isnumeric(v)||islogical(v), n=double(v); else
    s=lower(string(v)); n=str2double(s); n(s=="true")=1; n(s=="false")=0;
end
end
function tf=truth(v)
n=num(v); tf=isscalar(n)&&isfinite(n)&&n==1;
end
function tf=sameFinite(a,b)
a=num(a); b=num(b);
tf=isscalar(a)&&isscalar(b)&&isfinite(a)&&isfinite(b)&&a==b;
end
function tf=textPresent(v)
s=string(v); tf=isscalar(s)&&~ismissing(s)&&strlength(strtrim(s))>0;
end
function tf=isSHA(v)
tf=textPresent(v)&&~isempty(regexp(char(string(v)),'^[0-9a-fA-F]{64}$','once'));
end
function p=canonical(p)
p=string(char(java.io.File(char(string(p))).getCanonicalPath()));
end
function verifyFile(path,sha)
require(isfile(path),'MissingArtifact',"Missing hash-bound artifact "+string(path));
require(isSHA(sha)&&strcmpi(string(sixgr.util.sha256File(path)),string(sha)),'Identity',"Artifact SHA-256 differs: "+string(path));
end
function hash=jsonHash(token)
hash=string(sixgr.util.sha256Hex(uint8(unicode2native(char(token),'UTF-8'))));
end

function path=inside(root,relative)
require(textPresent(relative),'MissingArtifact','Empty artifact path.');
path=canonical(fullfile(root,string(relative)));
require(startsWith(path,canonical(root)+filesep),'Identity','Artifact escapes its owning run folder.');
end
