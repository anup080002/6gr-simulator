classdef PUCCHPowerVectorEvidence
    % Power-vector arithmetic plus actual IFFT/CP waveform measurements.
    methods (Static)
        function value=build(root,runID,profilePath)
            profile=sixgr.lls6g.config.readConfigFile(profilePath);
            required={'profile_id','research_class','evidence_scope','fixture_factory', ...
                'format','information_bits','minimum_grid_prbs','start_prb', ...
                'rnti','resource_id','configuration_epoch'};
            assert(all(isfield(profile,required)), ...
                'sixgr:phy:pucch:MissingPowerFixtureProfile','Power fixture profile is incomplete.');
            assert(string(profile.fixture_factory)=="sixgr.phy.pucch.PUCCHFixtureFactory.connected", ...
                'sixgr:phy:pucch:UnsupportedPowerFixture','Unknown explicit power waveform fixture factory.');
            manifest=jsondecode(fileread(fullfile(root,'independent_vector_manifest.json')));
            input=readVerified(root,'pucch_power_control_test_vectors.csv',manifest);
            expected=readVerified(root,'expected_pucch_power_control.csv',manifest);
            comparison=sixgr.phy.pucch.PUCCHIndependentVectorComparison.compare('power_control',input,expected);
            [~,indices]=ismember(string(input.CaseID),string(expected.CaseID));
            expected=expected(indices,:);
            contract=sixgr.phy.pucch.PUCCHUtil.readAllStrings(fullfile(root,'desired_pucch_csv_contract.csv'));
            index=find(contract.FileName=="pucch_power_control.csv");
            assert(isscalar(index),'sixgr:phy:pucch:MissingArtifactContract','Missing power CSV contract.');
            columns=split(contract.RequiredColumns(index),'|');
            value=array2table(strings(height(input),numel(columns)),'VariableNames',cellstr(columns));
            profileHash=sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256(profilePath);
            for k=1:height(input)
                mu=str2double(input.Mu(k)); mrb=str2double(input.MRB(k));
                f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(double(profile.format), ...
                    string(profile.information_bits),'SCS',15*2^mu, ...
                    'NSizeGrid',max(double(profile.minimum_grid_prbs),double(profile.start_prb)+mrb), ...
                    'RNTI',double(profile.rnti),'ResourceID',double(profile.resource_id), ...
                    'ConfigurationEpoch',double(profile.configuration_epoch));
                resource=f.Assignment.Resource.Data;
                resource.StartPRB=double(profile.start_prb); resource.NumPRBs=mrb;
                resource=sixgr.phy.pucch.PUCCHResource(resource);
                power=f.Assignment.PowerControlState.Data;
                names={'Mu','MRB','P0dBm','PathlossdB','DeltaFdB','DeltaTFdB', ...
                    'ClosedLoopAdjustmentdB','PCMAXdBm'};
                for j=1:numel(names), power.(names{j})=str2double(input.(names{j})(k)); end
                power.StateID=input.CaseID(k); power.TPCCommandSource="independent_power_vector";
                power=sixgr.phy.pucch.PUCCHPowerControlState(power);
                a=f.Assignment.Data; a.PowerControlStateID=power.Data.StateID;
                a.AssignmentSource="component_power_vector_fixture";
                a.ConnectedModeEvidenceEligible=false;
                assignment=sixgr.phy.pucch.PUCCHTransmissionAssignment( ...
                    a,resource,power,f.Assignment.SpatialRelationState);
                tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,assignment,f.Report);
                target=str2double(expected.ExpectedTransmitPowerdBm(k));
                tolerance=str2double(expected.Tolerance_dB(k));
                err=tx.Power.MeasuredWaveformPowerdBm-target;
                checked=comparison(string(comparison.CaseID)==string(input.CaseID(k)),:);
                passed=all(checked.Status=="PASS")&&isfinite(err)&&abs(err)<=tolerance;
                value.RunID(k)=string(runID); value.CaseID(k)=input.CaseID(k);
                for name=["P0dBm","PathlossdB","DeltaFdB","DeltaTFdB","PCMAXdBm"]
                    value.(name)(k)=input.(name)(k);
                end
                value.BandwidthTermdB(k)=number(tx.Power.BandwidthTermdB);
                value.TPCAdjustmentdB(k)=input.ClosedLoopAdjustmentdB(k);
                value.RequestedPowerdBm(k)=number(tx.Power.RequestedPowerdBm);
                value.AppliedPowerdBm(k)=number(tx.Power.AppliedPowerdBm);
                value.MeasuredWaveformPowerdBm(k)=number(tx.Power.MeasuredWaveformPowerdBm);
                value.PowerError_dB(k)=number(err);
                value.Clipped(k)=sixgr.phy.pucch.PUCCHUtil.boolString(tx.Power.Clipped);
                value.Status(k)="FAIL"; if passed, value.Status(k)="PASS"; end
                value.ExpectedTransmitPowerdBm(k)=number(target);
                value.Tolerance_dB(k)=number(tolerance);
                value.MeasurementReferenceDomain(k)=tx.Power.MeasurementReferenceDomain;
                value.MeasurementReferencePlane(k)="post_ifft_cp_pre_node_rf";
                value.ActiveSymbolIndices0JSON(k)=string(jsonencode(tx.Power.MeasurementActiveSymbolIndices0));
                value.MeasurementSampleCount(k)=double(tx.Power.MeasurementSampleCount);
                value.MeasuredSlotAveragePowerdBm(k)=number(tx.Power.MeasuredSlotAveragePowerdBm);
                value.WaveformSHA256(k)=tx.WaveformSHA256;
                value.WaveformSampleCount(k)=size(tx.Waveform,1);
                value.SampleRateHz(k)=tx.OFDMInfo.SampleRate;
                value.Numerology(k)=mu; value.AllocatedPRBCount(k)=mrb;
                value.AssignmentJSON(k)=string(jsonencode(assignment.Data));
                value.ResourceJSON(k)=string(jsonencode(resource.Data));
                value.PowerStateJSON(k)=string(jsonencode(power.Data));
                value.PowerStateSHA256(k)=power.Digest;
                value.WaveformAmplitudeUnit(k)="sqrt_mW";
                value.EvidenceScope(k)=string(profile.evidence_scope);
                value.ProfileSHA256(k)=profileHash;
            end
        end
    end
end
function t=readVerified(root,name,manifest)
index=find(string({manifest.files.path})==string(name));
assert(isscalar(index),'sixgr:phy:pucch:UnverifiedVectorFile','Missing manifest entry.');
hash=sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256(fullfile(root,name));
assert(strcmpi(hash,string(manifest.files(index).sha256)), ...
    'sixgr:phy:pucch:VectorHashMismatch','Power vector hash mismatch.');
t=sixgr.phy.pucch.PUCCHUtil.readAllStrings(fullfile(root,name));
assert(height(t)==manifest.files(index).rows,'sixgr:phy:pucch:VectorRowCountMismatch','Power vector row count mismatch.');
end
function value=number(x)
value=string(sprintf('%.17g',double(x)));
end
