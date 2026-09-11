classdef PUCCHIndependentVectorComparison
    % Executed component comparisons against the bounded frozen vector pack.
    % These are NOT received waveform measurements or full NR qualification.
    methods (Static)
        function [summary,details]=build(root,runID)
            manifestPath=fullfile(root,'independent_vector_manifest.json');
            manifest=jsondecode(fileread(manifestPath));
            families=["uci_report","uci_coding","harq_codebook","sr", ...
                "csi_report","resource_set","resource_indicator", ...
                "format_matrix","k1_tdd","collision","power_control","spatial_relation"];
            refs=["uci_serialization","uci_coding_plan","harq_codebook","sr_occasion", ...
                "csi_serialization","resource_selection","resource_indicator_selection", ...
                "format_validation","timing_resolution","collision_resolution", ...
                "power_control","spatial_relation"];
            summary=table(); parts=cell(numel(families),1);
            for k=1:numel(families)
                inputName="pucch_"+families(k)+"_test_vectors.csv";
                expectedName="expected_pucch_"+refs(k)+".csv";
                [inputs,inputHash]=localReadVerified(root,inputName,manifest);
                [expected,expectedHash,oracleClass]=localReadVerified(root,expectedName,manifest);
                d=sixgr.phy.pucch.PUCCHIndependentVectorComparison.compare(families(k),inputs,expected);
                d.RunID=repmat(string(runID),height(d),1);
                d.InputArtifact=repmat(inputName,height(d),1);
                d.InputSHA256=repmat(inputHash,height(d),1);
                d.OracleArtifact=repmat(expectedName,height(d),1);
                d.OracleArtifactSHA256=repmat(expectedHash,height(d),1);
                parts{k}=d;
                mismatches=nnz(d.Status=="FAIL"); unverified=nnz(d.Status=="NOT_EXECUTED");
                status="PASS";
                if unverified>0, status="INCOMPLETE"; end
                if mismatches>0, status="FAIL"; end
                row=table(string(runID),families(k),height(inputs),oracleClass, ...
                    "frozen_reference_pack",string(manifest.profile),expectedHash, ...
                    mismatches,unverified,nnz(d.Status~="NOT_EXECUTED"),status, ...
                    "bounded_component_comparison_not_waveform_truth",false, ...
                    'VariableNames',{'RunID','VectorFamily','VectorCount','OracleClass', ...
                    'OracleImplementation','OracleVersion','OracleArtifactSHA256', ...
                    'MismatchCount','UnverifiedFieldCount','ExecutedComparisonCount', ...
                    'Status','EvidenceClass','TruthQualified'});
                summary=[summary;row]; %#ok<AGROW>
            end
            details=vertcat(parts{:});
        end

        function details=compare(family,inputs,expected)
            % Public in-memory seam permits mutation tests without altering
            % frozen files or giving the DUT access to reference values.
            assert(istable(inputs)&&istable(expected)&& ...
                ismember('CaseID',inputs.Properties.VariableNames)&& ...
                ismember('CaseID',expected.Properties.VariableNames), ...
                'sixgr:phy:pucch:VectorIdentityMismatch','Vector tables require CaseID.');
            ids=string(inputs.CaseID); refIDs=string(expected.CaseID);
            assert(~isempty(ids)&&all(~ismissing(ids)&strlength(ids)>0)&& ...
                all(~ismissing(refIDs)&strlength(refIDs)>0)&& ...
                numel(unique(ids))==numel(ids)&&numel(unique(refIDs))==numel(refIDs)&& ...
                isequal(sort(ids),sort(refIDs)), ...
                'sixgr:phy:pucch:VectorIdentityMismatch', ...
                'Input/reference CaseID sets must be nonempty, unique and identical.');
            [~,order]=ismember(ids,refIDs); expected=expected(order,:);
            fields=setdiff(string(expected.Properties.VariableNames), ...
                ["CaseID","Status","OracleClass","Tolerance_dB"],'stable');
            parts=cell(height(inputs),1);
            for k=1:height(inputs)
                actual=localExecute(string(family),inputs(k,:));
                n=numel(fields); observed=strings(n,1); reference=strings(n,1);
                status=repmat("NOT_EXECUTED",n,1); errorValue=nan(n,1); tolerance=zeros(n,1);
                for f=1:n
                    name=fields(f); reference(f)=localText(expected(k,:),name);
                    if ~isfield(actual,name), continue; end
                    value=actual.(name);
                    if islogical(value)
                        observed(f)=string(value); tokens=lower(reference(f));
                        matched=ismember(tokens,["true","false","1","0"]) && ...
                            (value==ismember(tokens,["true","1"]));
                    elseif isnumeric(value)
                        assert(isscalar(value),'sixgr:phy:pucch:VectorScalarRequired', ...
                            'Comparison values must be scalar or exact text.');
                        observed(f)=string(sprintf('%.17g',value));
                        target=str2double(reference(f));
                        if family=="power_control"
                            tolerance(f)=str2double(localText(expected(k,:),"Tolerance_dB"));
                            assert(isfinite(tolerance(f))&&tolerance(f)>=0, ...
                                'sixgr:phy:pucch:InvalidVectorTolerance','Invalid power tolerance.');
                        end
                        if strlength(reference(f))==0 && isnan(value)
                            matched=true; % Explicit absent ordinal/reference on invalid procedure.
                        else
                            errorValue(f)=abs(double(value)-target);
                            matched=isfinite(value)&&isfinite(target)&&errorValue(f)<=tolerance(f);
                        end
                    else
                        observed(f)=string(value); matched=observed(f)==reference(f);
                    end
                    status(f)="FAIL"; if matched, status(f)="PASS"; end
                end
                parts{k}=table(repmat(string(family),n,1),repmat(ids(k),n,1), ...
                    fields(:),reference,observed,errorValue,tolerance,status, ...
                    repmat(sixgr.phy.pucch.PUCCHUtil.hash(actual),n,1), ...
                    'VariableNames',{'VectorFamily','CaseID','Field','ExpectedValue', ...
                    'ObservedValue','AbsoluteError','Tolerance','Status','DUTResultSHA256'});
            end
            details=vertcat(parts{:});
        end
    end
end

function [t,hash,oracleClass]=localReadVerified(root,name,manifest)
index=find(string({manifest.files.path})==name);
assert(isscalar(index),'sixgr:phy:pucch:UnverifiedVectorFile','Missing/duplicate manifest entry %s.',name);
entry=manifest.files(index); path=fullfile(root,name);
hash=sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256(path);
assert(strcmpi(hash,string(entry.sha256)), ...
    'sixgr:phy:pucch:VectorHashMismatch','Frozen reference hash mismatch: %s.',name);
t=sixgr.phy.pucch.PUCCHUtil.readAllStrings(path);
assert(height(t)==entry.rows,'sixgr:phy:pucch:VectorRowCountMismatch','Manifest row count mismatch: %s.',name);
oracleClass=string(entry.oracle_class);
end

function out=localExecute(family,row)
% Expected values are deliberately not an argument to this DUT adapter.
switch family
    case "uci_report"
        a=sixgr.phy.pucch.UCIReportSerializer.serializeVector(row);
        out=struct('Sequence1Bits',sixgr.phy.pucch.PUCCHUtil.bitString(a.Sequence1.Bits), ...
            'Sequence2Bits',sixgr.phy.pucch.PUCCHUtil.bitString(a.Sequence2.Bits), ...
            'Sequence1Length',numel(a.Sequence1.Bits),'Sequence2Length',numel(a.Sequence2.Bits), ...
            'TotalInformationBits',a.InformationBitCount,'Part2PaddingBits',a.PaddingBitCount);
    case "uci_coding"
        a=sixgr.phy.pucch.UCIEncodingPlan.fromVector(row);
        out=struct('Scheme',a.Scheme,'CRCPolynomial',a.CRCPolynomial,'CRCBits',a.CRCBits, ...
            'SegmentationExpected',a.SegmentationExpected,'ExpectedValid',a.Valid);
    case "harq_codebook"
        a=sixgr.phy.pucch.HARQACKCodebookBuilder.buildVector(row);
        out=struct('ExpectedBitTokens',join(a.BitTokens,""),'ExpectedBitCount',numel(a.BitTokens), ...
            'ExpectedEventOrder',join(a.EventOrder,"|"),'DTXCount',nnz(a.DTXMask));
    case "sr"
        a=sixgr.phy.pucch.SchedulingRequestState.fromVector(row); a=a.Data;
        out=struct('IsSROccasion',a.IsOccasion,'TransmitPUCCH',a.Transmit, ...
            'SRValue',a.Value,'ExpectedResourceSource',a.ResourceSource);
    case "csi_report"
        states=sixgr.phy.pucch.CSIReportBuilder.buildVector(row);
        data=arrayfun(@(x)x.Data,states);
        report=sixgr.phy.pucch.UCIReport(struct('ReportID',localText(row,"CaseID"), ...
            'RNTI',1,'ServingCell',0,'ComponentCarrier',0,'ULBWP',0, ...
            'ConfigurationEpoch',str2double(localText(row,"ConfigurationEpoch")), ...
            'TargetSlot',0,'PriorityIndex',0,'HARQACKReport',struct([]), ...
            'SchedulingRequestReports',struct([]),'CSIReports',data, ...
            'ReportSource',"independent_vector_procedure_state",'TriggeringEventIDs',"vector"));
        a=sixgr.phy.pucch.UCIReportSerializer.serialize(report);
        out=struct('ExpectedCSIPart1Bits',sixgr.phy.pucch.PUCCHUtil.bitString(a.Sequence1.Bits), ...
            'ExpectedCSIPart2Bits',sixgr.phy.pucch.PUCCHUtil.bitString(a.Sequence2.Bits), ...
            'Part1Length',numel(a.Sequence1.Bits),'Part2Length',numel(a.Sequence2.Bits), ...
            'ExpectedReportOrder',join(string([data.ReportID]),"|"));
    case "resource_set"
        a=sixgr.phy.pucch.PUCCHResourceSetResolver.resolveVector(row);
        out=struct('SelectedResourceSource',a.SelectedResourceSource,'SelectedSetID',a.SelectedSetID, ...
            'ExpectedValid',a.Valid,'ExpectedErrorID',a.ErrorID);
    case "resource_indicator"
        a=sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(row);
        out=struct('ExpectedOrdinal',a.Ordinal,'ExpectedValid',a.Valid,'ExpectedErrorID',a.ErrorID);
    case "format_matrix"
        a=sixgr.phy.pucch.PUCCHFormatValidator.validateVector(row);
        out=struct('ExpectedValid',a.Valid,'ExpectedErrorID',a.ErrorID, ...
            'ExpectedFormat',a.Format,'ParameterMutationAllowed',a.ParameterMutated);
        % No waveform was generated by the format validator.
    case "k1_tdd"
        a=sixgr.phy.pucch.PUCCHTimingResolver.resolveVector(row);
        out=struct('ExpectedDueSlot',a.DueSlot,'ExpectedLegal',a.Legal, ...
            'ExpectedStartSymbol',a.StartSymbol,'SymbolShiftAllowed',a.SymbolShiftApplied, ...
            'ExpectedErrorID',a.ErrorID);
    case "collision"
        a=sixgr.phy.pucch.PUCCHCollisionResolver.resolveVector(row);
        out=struct('ExpectedAction',a.ResolutionAction,'UnresolvedCollisionAllowed',a.UnresolvedCollision);
        % Decision text is not evidence of an executed PUCCH count or PUSCH multiplexing.
    case "power_control"
        a=sixgr.phy.pucch.PUCCHPowerController.resolveVector(row);
        out=struct('BandwidthTermdB',a.BandwidthTermdB,'UnclippedPowerdBm',a.RequestedPowerdBm, ...
            'ExpectedTransmitPowerdBm',a.AppliedPowerdBm,'Clipped',a.Clipped);
    case "spatial_relation"
        a=sixgr.phy.pucch.PUCCHSpatialRelationState.resolveVector(row);
        out=struct('ExpectedValid',a.Valid,'ExpectedBeamSource',a.BeamSource, ...
            'ExpectedPathlossReferenceRSID',a.PathlossReferenceRSID,'ExpectedErrorID',a.ErrorID);
    otherwise
        error('sixgr:phy:pucch:UnsupportedVectorFamily','No executed adapter for %s.',family);
end
end

function value=localText(row,name)
value=string(row.(name));
if ismissing(value), value=""; end
end
