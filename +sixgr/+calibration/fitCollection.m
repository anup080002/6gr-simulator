function report=fitCollection(folder)
% Audit all planned keys/attempts; never promote a partially covered library.
m=load(fullfile(folder,'campaign.mat'),'p','cases','identity');
audit=sixgr.calibration.summarizeCollection(folder);
sixgr.calibration.auditReferenceDomain(folder);
receipt=jsondecode(fileread(fullfile(folder,'receipt.json')));
report=struct('Schema',"sixgr.link_calibration_fit_report/v1", ...
    'CampaignIdentity',m.identity,'CollectionComplete',logical(receipt.AllEpisodesComplete), ...
    'PrimaryStudyAccepted',false,'ProductionPackageInstalled',false,'Fits',struct([]));
if ~receipt.AllEpisodesComplete
    report.Status="pending_fixed_population_collection";
    sixgr.util.jsonWrite(fullfile(folder,'fitting_status.json'),report); return
end
[~,axis]=sixgr.calibration.historyGrid(m.p,"reference"); axis=axis(:);
records=struct([]); fits=cell(0,1);
for c=1:numel(m.cases)
    key=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(m.cases(c).Config),'UTF-8'))));
    for a=1:numel(m.p.rv_sequence)
        row=struct('CaseID',m.cases(c).ID,'Direction',m.cases(c).Direction, ...
            'Attempt',a,'Passed',false,'Status',"",'ErrorIdentifier',"",'ErrorMessage',"", ...
            'SupportedCellCount',0,'UnsupportedCellCount',0);
        try
            relevant=audit.CaseID==m.cases(c).ID & audit.Attempt==a;
            r=audit(relevant & audit.Role=="reference",:);
            v=audit(relevant & audit.Role=="reference_validation",:);
            supported=logical(r.PopulationSufficient) & logical(v.PopulationSufficient);
            assert(any(supported), 'sixgr:calibration:ConditionalPopulation', ...
                'No independently qualified AWGN conditional cells.');
            shape=repmat(numel(axis),1,a); if isscalar(shape), shape=[shape 1]; end
            reference=struct('SINRAxes_dB',{repmat({axis},1,a)}, ...
                'TrialCount',reshape(r.ConditionalTrials,shape), ...
                'ErrorCount',reshape(r.Errors,shape), ...
                'SupportedMask',reshape(supported,shape),'ConfigurationSHA256',key);
            awgnHeldout=struct('TrialCount',reshape(v.ConditionalTrials,shape), ...
                'ErrorCount',reshape(v.Errors,shape));
            awgnCheck=sixgr.calibration.validateIndependentReference(reference,awgnHeldout,m.p.qualification);
            assert(awgnCheck.Passed,'sixgr:calibration:ReferenceValidation', ...
                'Independent AWGN validation does not bound the conditional BLER difference.');
            roleRows=cell(1,2); roles=["fit","validation"];
            for role=1:2
                roleRows{role}=sixgr.calibration.readFeatureRows(folder, ...
                    m.cases(c).ID,roles(role),a,key);
            end
            fit=sixgr.calibration.fitEffectiveSINR(reference,roleRows{1},roleRows{2},m.p.qualification);
            fit.CaseID=m.cases(c).ID; fit.Direction=m.cases(c).Direction;
            fit.Attempt=a; fit.RVSequence=double(m.p.rv_sequence(1:a));
            fits{end+1}=fit; %#ok<AGROW>
            row.SupportedCellCount=sum(supported);
            row.UnsupportedCellCount=numel(supported)-sum(supported);
            row.Passed=fit.FittingPassed; row.Status="fitted_validation_failed";
            if row.Passed, row.Status="fitted_and_heldout_validated_scope_only"; end
        catch ME
            row.Status="blocked"; row.ErrorIdentifier=string(ME.identifier); row.ErrorMessage=string(ME.message);
        end
        if isempty(records), records=row; else, records(end+1)=row; end %#ok<AGROW>
    end
end
report.Fits=records; report.AllFittingPassed=all([records.Passed]);
report.Status="not_ready_for_production_binding";
% Fitted EESM alone does not establish matching network-provider physical
% keys, resource population, RF profile or the SLS required-key matrix.
save(fullfile(folder,'effective_sinr_fits.mat'),'fits','report','-v7.3');
writetable(struct2table(records),fullfile(folder,'fitting_coverage.csv'));
sixgr.util.jsonWrite(fullfile(folder,'fitting_status.json'),report);
end
