function [observations,pairs]=collectDMRSCSIRSComparisonEvidence(runRoot,dlTrials,csirsTrials)
% Read-only post-reception NMSE evidence. Independent observations are NOT
% a DMRS-versus-CSI-RS comparison. Never subtract means across unlike pilots,
% RF/reference planes, spatial maps, operating points or receiver clocks.
arguments
    runRoot {mustBeTextScalar}
    dlTrials table
    csirsTrials table
end
root=string(java.io.File(char(runRoot)).getCanonicalPath());
assert(isfolder(root),'sixgr:report:ChannelComparisonRunScope','Use an existing run root.');
% Converting an empty struct array loses scalar field types in MATLAB.
% Slice a typed scalar table instead; no placeholder row is published.
observations=struct2table(prototype(),'AsArray',true); observations=observations([],:);
pairs=struct2table(pairPrototype(),'AsArray',true); pairs=pairs([],:);
operands=cell(0,1);
inputs={dlTrials,csirsTrials}; channels=["PDSCH","CSI-RS"];
for family=1:2
    trials=inputs{family};
    for k=1:height(trials)
        trial=trials(k,:); relative=textField(trial,"ChannelEstimateResourcesCSV");
        status="";
        if ~hasText(relative)
            status="unavailable_resource_archive_not_retained";
        elseif ~all(ismember(["ChannelEstimateResourcesCSVSHA256","ChannelEstimateMATFile", ...
                "ChannelEstimateMATFileSHA256"],string(trial.Properties.VariableNames))) || ...
                ~hasText(textField(trial,"ChannelEstimateMATFile")) || ...
                ~hasText(textField(trial,"ChannelEstimateResourcesCSVSHA256")) || ...
                ~hasText(textField(trial,"ChannelEstimateMATFileSHA256"))
            status="unavailable_incomplete_archive_binding";
        else
            try
                [rows,archive,csvHash,matHash]=readArchive(root,trial,channels(family));
            catch ex
                if strcmp(ex.identifier,'sixgr:report:ChannelComparisonMissingArtifact')
                    status="unavailable_declared_archive_missing";
                else
                    rethrow(ex); % Corruption is not absence and must not be hidden.
                end
            end
        end
        if strlength(status)>0
            record=population(trial,channels(family));
            record.Status=status; record.PairingStatus="unavailable_independent_operands";
            record=bindArtifact(record,trial,k,channels(family));
            observations=[observations;struct2table(record,'AsArray',true)]; %#ok<AGROW>
            operands{end+1,1}=[]; %#ok<AGROW>
            continue;
        end
        resourceIDs=NaN;
        if family==2
            assert(ismember('ResourceID',rows.Properties.VariableNames), ...
                'sixgr:report:ChannelComparisonResourceIdentity','CSI-RS needs actual resource identities.');
            ids=numbers(rows,'ResourceID');
            assert(all(isfinite(ids) & ids>=0 & ids==fix(ids)), ...
                'sixgr:report:ChannelComparisonResourceIdentity','Invalid CSI-RS resource identity.');
            resourceIDs=unique(ids,'stable').';
        end
        for resource=resourceIDs
            part=rows;
            if family==2, part=rows(ids==resource,:); end
            [record,operand]=observation(trial,part,archive,channels(family),resource);
            record=bindArtifact(record,trial,k,channels(family));
            record.ResourcesCSVSHA256=csvHash;
            record.ArchiveMATSHA256=matHash;
            observations=[observations;struct2table(record,'AsArray',true)]; %#ok<AGROW>
            operands{end+1,1}=operand; %#ok<AGROW>
        end
    end
end
% Exact source rows remain distinct. No de-duplication by reused observation
% IDs, no independent-trial count, no statistical qualification.
for d=find(observations.Method=="PDSCH_DMRS").'
    for c=find(observations.Method=="CSI_RS").'
        if isempty(operands{d}) || isempty(operands{c}), continue; end
        if observations.UEIndex(d)~=observations.UEIndex(c) || ...
                observations.Slot(d)~=observations.Slot(c), continue; end
        [compatible,reason]=compatiblePair(observations(d,:),operands{d},observations(c,:),operands{c});
        if observations.PairingStatus(d)~="paired_exact_common_operands", observations.PairingStatus(d)=reason; end
        if observations.PairingStatus(c)~="paired_exact_common_operands", observations.PairingStatus(c)=reason; end
        if ~compatible, continue; end
        p=pairPrototype(); p.DMRSObservationRow=d; p.CSIRSObservationRow=c;
        p.DMRSObservationID=observations.ObservationID(d); p.CSIRSObservationID=observations.ObservationID(c);
        p.CSIRSResourceID=observations.ResourceID(c); p.ReferencePlane=observations.ReferencePlane(d);
        p.ComparedValues=observations.ComparedValues(d);
        p.DMRSNMSELinear=observations.NMSELinear(d); p.CSIRSNMSELinear=observations.NMSELinear(c);
        p.DeltaNMSELinear=p.DMRSNMSELinear-p.CSIRSNMSELinear;
        % Exact zero NMSE is -Inf dB. Its difference is not a finite dB gain.
        if all(isfinite([observations.NMSE_dB(d),observations.NMSE_dB(c)]))
            p.DeltaNMSE_dB=observations.NMSE_dB(d)-observations.NMSE_dB(c);
            p.DeltaNMSEdBAvailable=true;
        end
        p.DMRSResourcesCSV=observations.ResourcesCSV(d); p.DMRSResourcesCSVSHA256=observations.ResourcesCSVSHA256(d);
        p.CSIRSResourcesCSV=observations.ResourcesCSV(c); p.CSIRSResourcesCSVSHA256=observations.ResourcesCSVSHA256(c);
        for name=["RunID","ExecutionID","ConfigHash","SweepPointIndex","Seed","ConfiguredSNR_dB","UEIndex","CellID","Slot", ...
                "ReceiverID","ReceiverClockDomain","ReceiverClockEpoch", ...
                "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz"]
            p.(name)=observations.(name)(d);
        end
        pairs=[pairs;struct2table(p,'AsArray',true)]; %#ok<AGROW>
    end
end
end

function [T,a,csvHash,matHash]=readArchive(root,trial,channel)
required=["ChannelEstimateResourcesCSVSHA256","ChannelEstimateMATFile","ChannelEstimateMATFileSHA256","Slot","UEIndex"];
assert(all(ismember(required,string(trial.Properties.VariableNames))), ...
    'sixgr:report:ChannelComparisonBinding','A declared resource archive needs its complete owner and checksums.');
csvHash=string(trial.ChannelEstimateResourcesCSVSHA256); matHash=string(trial.ChannelEstimateMATFileSHA256);
csvPath=artifact(root,string(trial.ChannelEstimateResourcesCSV),"csv",csvHash);
matPath=artifact(root,string(trial.ChannelEstimateMATFile),"mat",matHash);
T=sixgr.util.csvReadTable(csvPath,'TextType','string');
archiveVariables=whos('-file',char(matPath)); available=string({archiveVariables.name});
selected=intersect(["Contract","Resources","ResourcesCSVSHA256","ReferenceEvidence","Snapshot","Score","Metrics"],available);
a=load(char(matPath),selected{:});
assert(string(sixgr.util.sha256File(csvPath))==csvHash && string(sixgr.util.sha256File(matPath))==matHash, ...
    'sixgr:report:ChannelComparisonChecksum','Archive changed during readback.');
assert(isfield(a,'Resources') && istable(a.Resources) && isfield(a,'ReferenceEvidence'), ...
    'sixgr:report:ChannelComparisonArchiveSchema','Retain both complex resource operands and reference provenance.');
if channel=="PDSCH"
    % Both shared and isolated production archives retain the receiver
    % snapshot. The isolated producer predates the outer Contract field.
    assert(isfield(a,'Snapshot') && a.Snapshot.Contract=="PDSCH_pilot_channel_capture/v1" && ...
        (~isfield(a,'Contract') || a.Contract=="scored_data_channel_resource_archive/v1"), ...
        'sixgr:report:ChannelComparisonArchiveSchema','Use the actual data receiver snapshot.');
else
    assert(isfield(a,'Contract') && a.Contract=="scored_CSI_RS_nominal_channel_resources/v1", ...
        'sixgr:report:ChannelComparisonArchiveSchema','Use the scored CSI-RS producer archive.');
end
if isfield(a,'ResourcesCSVSHA256')
    assert(string(a.ResourcesCSVSHA256)==csvHash,'sixgr:report:ChannelComparisonChecksum','MAT/CSV binding disagrees.');
end
required=["Channel","Slot","UEIndex","ConfiguredSNR_dB","SubcarrierIndex0","SymbolIndex0", ...
    "RxBranchIndex0","ReferencePortIndex0","HReal","HImag","ReferenceHReal","ReferenceHImag", ...
    "ChannelErrorEnergy","ReferenceChannelEnergy","ChannelEstimateSource","ChannelReferenceSource", ...
    "ChannelReferencePlane","ReferenceUsedByReceiver","GainOrPhaseFitted"];
assert(~isempty(T) && all(ismember(required,string(T.Properties.VariableNames))) && ...
    height(T)==height(a.Resources) && all(ismember(string(T.Properties.VariableNames),string(a.Resources.Properties.VariableNames))), ...
    'sixgr:report:ChannelComparisonResourceSchema','A complete nonempty per-resource archive is required.');
for name=string(T.Properties.VariableNames)
    expected=a.Resources.(name); actual=T.(name);
    if isnumeric(expected) || islogical(expected)
        same=isequaln(numbers(T,name),double(expected));
    else
        same=isequaln(string(actual),string(expected));
    end
    assert(same,'sixgr:report:ChannelComparisonArchiveClosure','MAT and CSV differ at %s.',name);
end
assert(all(string(T.Channel)==channel),'sixgr:report:ChannelComparisonObservationIdentity','Wrong channel archive.');
for name=["Slot","UEIndex"]
    assert(all(numbers(T,name)==numbers(trial,name)), ...
        'sixgr:report:ChannelComparisonObservationIdentity','Wrong owning %s.',name);
end
idField="ChannelEstimateObservationID";
if channel=="CSI-RS", idField="CSIChannelEstimateObservationID"; end
assert(ismember(idField,string(trial.Properties.VariableNames)) && ismember(idField,string(T.Properties.VariableNames)) && ...
    strlength(string(trial.(idField)))>0 && all(string(T.(idField))==string(trial.(idField))), ...
    'sixgr:report:ChannelComparisonObservationIdentity','Wrong observation identity.');
for name=["CellID","SweepPointIndex","ConfiguredSNR_dB","ExecutionID","ConfigHash"]
    if ismember(name,string(trial.Properties.VariableNames)) && ismember(name,string(T.Properties.VariableNames))
        assert(all(string(T.(name))==string(trial.(name))), ...
            'sixgr:report:ChannelComparisonObservationIdentity','Resource %s differs from its owner.',name);
    end
end
e=a.ReferenceEvidence;
assert(all(isfield(e,{'ReferencePlane','RFImpairmentsIncluded','ReceiverEstimatorInput','GainOrPhaseFitted'})) && ...
    ~e.ReceiverEstimatorInput && ~e.GainOrPhaseFitted && ...
    all(numbers(T,'ReferenceUsedByReceiver')==0 & numbers(T,'GainOrPhaseFitted')==0) && ...
    all(string(T.ChannelReferencePlane)==string(e.ReferencePlane)), ...
    'sixgr:report:ChannelComparisonReferencePolicy','Do not score oracle-fed or fitted channel estimates.');
for name=["AdditionalChannelExecutions","AdditionalRFExecutions"]
    if isfield(e,name)
        assert(isequal(e.(name),0),'sixgr:report:ChannelComparisonReferencePolicy', ...
            'Do not substitute a rerun for retained same-execution reference operands.');
    end
end
if ismember('ReferenceRFImpairmentsIncluded',T.Properties.VariableNames)
    assert(all(numbers(T,'ReferenceRFImpairmentsIncluded')==double(e.RFImpairmentsIncluded)), ...
        'sixgr:report:ChannelComparisonReferencePolicy','Resource and archive RF scopes disagree.');
end
h=complex(numbers(T,'HReal'),numbers(T,'HImag')); ref=complex(numbers(T,'ReferenceHReal'),numbers(T,'ReferenceHImag'));
assert(all(isfinite(h)) && all(isfinite(ref)), ...
    'sixgr:report:ChannelComparisonIncompleteOperands','Do not discard unavailable per-resource operands.');
assert(close(numbers(T,'ChannelErrorEnergy'),abs(h-ref).^2) && ...
    close(numbers(T,'ReferenceChannelEnergy'),abs(ref).^2), ...
    'sixgr:report:ChannelComparisonEnergyClosure','Stored energies must equal actual complex-operand energies.');
for item={"ChannelNMSEErrorEnergy",sum(abs(h-ref).^2); "ChannelNMSEReferenceEnergy",sum(abs(ref).^2); ...
        "ChannelEstimateErrorEnergy",sum(abs(h-ref).^2); "ChannelEstimateReferenceEnergy",sum(abs(ref).^2); ...
        "ChannelNMSEComparedComplexValues",height(T); "ChannelEstimateComparedValues",height(T)}.'
    name=string(item{1}); expected=item{2};
    if ismember(name,string(trial.Properties.VariableNames))
        assert(close(numbers(trial,name),expected),'sixgr:report:ChannelComparisonEnergyClosure','Owning trial %s disagrees.',name);
    end
end
end

function path=artifact(root,relative,extension,digest)
portable=replace(relative,'\','/');
assert(isscalar(portable) && ~ismissing(portable) && ...
    ~isempty(regexp(char(portable),char("^channel_estimation/"+extension+"/[^/]+\."+extension+"$"),'once')), ...
    'sixgr:report:ChannelComparisonRunScope','Use run-relative channel_estimation artifacts only.');
path=string(java.io.File(char(fullfile(root,relative))).getCanonicalPath());
assert(startsWith(path,root+filesep,'IgnoreCase',ispc), ...
    'sixgr:report:ChannelComparisonRunScope','An archive cannot escape the owning run.');
assert(isfile(path),'sixgr:report:ChannelComparisonMissingArtifact','Missing declared archive %s.',relative);
assert(isscalar(digest) && ~ismissing(digest) && ~isempty(regexp(char(digest),'^[0-9a-f]{64}$','once')) && ...
    string(sixgr.util.sha256File(path))==digest,'sixgr:report:ChannelComparisonChecksum','Archive checksum mismatch.');
end

function [out,op]=observation(trial,T,a,channel,resource)
out=population(trial,channel); out.ResourceID=resource;
out.ReferencePlane=string(a.ReferenceEvidence.ReferencePlane);
out.ReferenceRFImpairmentsIncluded=double(a.ReferenceEvidence.RFImpairmentsIncluded);
out.ReferenceUsedByReceiver=0; out.GainOrPhaseFitted=0;
out.ChannelEstimateSource=string(T.ChannelEstimateSource(1));
out.ChannelReferenceSource=string(T.ChannelReferenceSource(1));
assert(hasText(out.ChannelEstimateSource) && hasText(out.ChannelReferenceSource) && ...
    all(string(T.ChannelEstimateSource)==out.ChannelEstimateSource) && ...
    all(string(T.ChannelReferenceSource)==out.ChannelReferenceSource), ...
    'sixgr:report:ChannelComparisonResourceSchema','Each observation needs explicit, consistent estimator/reference sources.');
keys=zeros(height(T),4);
for k=1:4
    names=["SubcarrierIndex0","SymbolIndex0","RxBranchIndex0","ReferencePortIndex0"];
    keys(:,k)=numbers(T,names(k));
end

assert(all(isfinite(keys) & keys>=0 & keys==fix(keys),'all') && size(unique(keys,'rows'),1)==height(T), ...
    'sixgr:report:ChannelComparisonResourcePopulation','Each scored resource/branch/port must occur exactly once.');
[keys,order]=sortrows(keys);
op=struct('Keys',keys,'H',complex(numbers(T,'HReal'),numbers(T,'HImag')), ...
    'Reference',complex(numbers(T,'ReferenceHReal'),numbers(T,'ReferenceHImag')), ...
    'TXMap',[],'RXMap',[],'Amplitude',NaN,'GridIdentity',"");
op.H=op.H(order); op.Reference=op.Reference(order);
e=a.ReferenceEvidence;
if channel=="CSI-RS"
    assert(isfield(e,'Resources'),'sixgr:report:ChannelComparisonSpatialIdentity','Retain CSI-RS resource matrices.');
    hit=find([e.Resources.ResourceID]==resource);
    assert(isscalar(hit),'sixgr:report:ChannelComparisonSpatialIdentity','Exactly one executed map per CSI resource.');
    entry=e.Resources(hit); op.TXMap=double(entry.WaveformPrecoderMatrix);
    assert(string(entry.WaveformPrecoderDigest)==string(sixgr.phy.mimo.MatrixContract.digest(op.TXMap)) && ...
        all(string(T.WaveformPrecoderDigest)==string(entry.WaveformPrecoderDigest)), ...
        'sixgr:report:ChannelComparisonSpatialIdentity','CSI-RS matrix and digest must match actual resource rows.');
    op.RXMap=eye(numel(unique(keys(:,3))));
    op.Amplitude=double(e.TXAmplitudeScale);
else
    snapshot=a.Snapshot;
    out.NumReferencePorts=snapshot.GridShape(4);
    carrier=snapshot.Carrier;
    op.GridIdentity=string(jsonencode(struct('NStartGrid',carrier.NStartGrid, ...
        'NSizeGrid',carrier.NSizeGrid,'SubcarrierSpacing',carrier.SubcarrierSpacing, ...
        'CyclicPrefix',string(carrier.CyclicPrefix))));
    if all(isfield(e,{'WaveformToElementMatrix','LayerToWaveformMatrix','ReceiverChannelOperator','TXAmplitudeScale'}))
        op.TXMap=double(e.WaveformToElementMatrix)*double(e.LayerToWaveformMatrix);
        op.RXMap=double(e.ReceiverChannelOperator.ReceiveCombiningMatrix);
        op.Amplitude=double(e.TXAmplitudeScale);
    end
end
out.NumReferencePorts=numel(unique(keys(:,4)));
out.NumReceiveBranches=numel(unique(keys(:,3)));
if ~isempty(op.TXMap)
    assert(size(op.TXMap,2)==out.NumReferencePorts && all(isfinite(op.TXMap),'all'), ...
        'sixgr:report:ChannelComparisonSpatialIdentity','Executed map must cover all scored ports.');
    out.WaveformPrecoderSHA256=string(sixgr.phy.mimo.MatrixContract.digest(op.TXMap));
end
out.ErrorEnergy=sum(abs(op.H-op.Reference).^2); out.ReferenceEnergy=sum(abs(op.Reference).^2);
out.ComparedValues=numel(op.H); out.NMSEAvailable=out.ReferenceEnergy>0;
out.Status="independent_resource_NMSE_not_paired_comparison";
if out.NMSEAvailable
    out.NMSELinear=out.ErrorEnergy/out.ReferenceEnergy; out.NMSE_dB=10*log10(out.NMSELinear);
else
    out.Status="undefined_zero_reference_energy";
end
end

function out=population(trial,channel)
out=prototype(); out.Method="PDSCH_DMRS"; out.Channel=channel;
idField="ChannelEstimateObservationID";
if channel=="CSI-RS", out.Method="CSI_RS"; idField="CSIChannelEstimateObservationID"; end
out.ObservationID=textField(trial,idField);
for name=["Slot","UEIndex","ConfiguredSNR_dB","SweepPointIndex","RandomSeed","ChannelSeed"]
    out.(name)=firstNumber(trial,name);
end
out.Seed=firstNumber(trial,["Seed","RandomSeed"]);
out.CellID=firstNumber(trial,["CellID","ServingCell","BaseStationID"]);
for name=["RunID","ExecutionID","ConfigHash","ScenarioID","RunTag","ReceiverID","ReceiverClockDomain"]
    out.(name)=textField(trial,name);
end
out.ObservationStartSample=firstNumber(trial,["ObservationStartSample","RXStartSample"]);
out.ObservationEndSampleExclusive=firstNumber(trial,["ObservationEndSampleExclusive","RXEndSampleExclusive"]);
out.ObservationSampleRateHz=firstNumber(trial,["ObservationSampleRateHz","SharedStreamSampleRateHz"]);
% An RF-configuration revision is not a sample-clock epoch. Never infer an
% endpoint from UE/cell or turn measurement/configuration epochs into clocks.
out.ReceiverClockEpoch=firstNumber(trial,"ReceiverClockEpoch");
end

function out=bindArtifact(out,trial,k,channel)
out.SourceTrialRow=k; out.SourceArtifact="air_interface/csv/dl_pdsch_trials.csv";
if channel=="CSI-RS", out.SourceArtifact="air_interface/csv/csi_rs_trials.csv"; end
out.ResourcesCSV=replace(textField(trial,"ChannelEstimateResourcesCSV"),'\','/');
out.ResourcesCSVSHA256=textField(trial,"ChannelEstimateResourcesCSVSHA256");
out.ArchiveMAT=replace(textField(trial,"ChannelEstimateMATFile"),'\','/');
out.ArchiveMATSHA256=textField(trial,"ChannelEstimateMATFileSHA256");
end

function value=textField(T,name)
value="";
if ismember(name,string(T.Properties.VariableNames)), value=string(T.(name)); end
assert(isscalar(value),'sixgr:report:ChannelComparisonMetadata','One scalar metadata value per source row.');
end
function yes=hasText(value)
yes=~ismissing(value) && strlength(strtrim(value))>0 && ...
    ~any(startsWith(value,["not_recorded_by_active_","not_emitted_by_active_", ...
    "field_not_emitted_by_active_","not_applicable_for_active_"])) && value~="not_applicable";
end

function [yes,reason]=compatiblePair(d,dp,c,cp)
yes=false; reason="incompatible_reference_plane_or_RF_scope";
if d.ReferencePlane~=c.ReferencePlane || d.ReferenceRFImpairmentsIncluded~=c.ReferenceRFImpairmentsIncluded, return; end
reason="missing_or_different_execution_population";
for name=["RunID","ExecutionID","ConfigHash"]
    if ~hasText(d.(name)) || ~hasText(c.(name)) || d.(name)~=c.(name), return; end
end
for name=["SweepPointIndex","Seed","ConfiguredSNR_dB","UEIndex","CellID","Slot"]
    if ~isfinite(d.(name)) || ~isfinite(c.(name)) || d.(name)~=c.(name), return; end
end
reason="missing_or_different_actual_receiver_clock";
for name=["ReceiverID","ReceiverClockDomain"]
    if ~hasText(d.(name)) || ~hasText(c.(name)) || d.(name)~=c.(name), return; end
end
for name=[ ...
        "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz","ReceiverClockEpoch"]
    if ~isfinite(d.(name)) || ~isfinite(c.(name)) || d.(name)~=c.(name), return; end
end
if d.ReceiverClockEpoch<0 || d.ReceiverClockEpoch~=fix(d.ReceiverClockEpoch) || ...
        d.ObservationStartSample<0 || d.ObservationStartSample~=fix(d.ObservationStartSample) || ...
        d.ObservationEndSampleExclusive<=d.ObservationStartSample || ...
        d.ObservationEndSampleExclusive~=fix(d.ObservationEndSampleExclusive) || ...
        d.ObservationSampleRateHz<=0, return; end
reason="missing_or_different_grid_and_spatial_operator";
if strlength(dp.GridIdentity)==0 || dp.GridIdentity~=cp.GridIdentity || isempty(dp.TXMap) || ...
        isempty(cp.TXMap) || ~isequal(dp.TXMap,cp.TXMap) || isempty(dp.RXMap) || ...
        ~isequal(dp.RXMap,cp.RXMap) || ~isfinite(dp.Amplitude) || dp.Amplitude~=cp.Amplitude, return; end
reason="different_time_frequency_branch_port_support";
if ~isequal(dp.Keys,cp.Keys), return; end
reason="different_independent_reference_operands";
if ~isequal(dp.Reference,cp.Reference), return; end
reason="unavailable_independent_NMSE";
if ~d.NMSEAvailable || ~c.NMSEAvailable, return; end
yes=true; reason="paired_exact_common_operands";
end

function value=numbers(T,name)
value=sixgr.truth.numericMeasurementColumn(T.(name),name);
end
function value=firstNumber(T,names)
value=NaN;
for name=names
    if ismember(name,string(T.Properties.VariableNames)), value=numbers(T,name); return; end
end
end
function yes=close(a,b)
yes=isequaln(a,b);
if ~yes && isequal(size(a),size(b)) && all(isfinite(a),'all') && all(isfinite(b),'all')
    yes=all(abs(a-b)<=256*eps(max(1,max(abs([a(:);b(:)])))),'all');
end
end
function p=prototype()
p=struct('Method',"",'Channel',"",'ObservationID',"",'ResourceID',NaN, ...
    'SourceTrialRow',NaN,'SourceArtifact',"",'ResourcesCSV',"",'ResourcesCSVSHA256',"", ...
    'ArchiveMAT',"",'ArchiveMATSHA256',"",'RunID',"",'ExecutionID',"",'ConfigHash',"", ...
    'ScenarioID',"",'RunTag',"",'Seed',NaN,'RandomSeed',NaN,'ChannelSeed',NaN, ...
    'SweepPointIndex',NaN,'ConfiguredSNR_dB',NaN,'UEIndex',NaN,'CellID',NaN,'Slot',NaN, ...
    'ObservationStartSample',NaN,'ObservationEndSampleExclusive',NaN,'ObservationSampleRateHz',NaN, ...
    'ReceiverID',"",'ReceiverClockDomain',"",'ReceiverClockEpoch',NaN, ...
    'ReferencePlane',"",'ReferenceRFImpairmentsIncluded',NaN, ...
    'ChannelEstimateSource',"",'ChannelReferenceSource',"",'WaveformPrecoderSHA256',"", ...
    'NumReferencePorts',NaN,'NumReceiveBranches',NaN,'ErrorEnergy',NaN,'ReferenceEnergy',NaN, ...
    'ComparedValues',NaN,'NMSELinear',NaN,'NMSE_dB',NaN,'NMSEAvailable',false,'Status',"", ...
    'PairingStatus',"no_same_UE_slot_counterpart",'ReferenceUsedByReceiver',NaN, ...
    'GainOrPhaseFitted',NaN,'StatisticallyQualified',false);
end
function p=pairPrototype()
p=struct('DMRSObservationRow',NaN,'CSIRSObservationRow',NaN,'DMRSObservationID',"", ...
    'CSIRSObservationID',"",'CSIRSResourceID',NaN,'RunID',"",'ExecutionID',"",'ConfigHash',"", ...
    'SweepPointIndex',NaN,'Seed',NaN,'ConfiguredSNR_dB',NaN,'UEIndex',NaN,'CellID',NaN,'Slot',NaN, ...
    'ReceiverID',"",'ReceiverClockDomain',"",'ReceiverClockEpoch',NaN, ...
    'ObservationStartSample',NaN,'ObservationEndSampleExclusive',NaN,'ObservationSampleRateHz',NaN, ...
    'ReferencePlane',"",'ComparedValues',NaN,'DMRSNMSELinear',NaN,'CSIRSNMSELinear',NaN, ...
    'DeltaNMSELinear',NaN,'DeltaNMSE_dB',NaN,'DeltaNMSEdBAvailable',false, ...
    'DMRSResourcesCSV',"",'DMRSResourcesCSVSHA256',"",'CSIRSResourcesCSV',"",'CSIRSResourcesCSVSHA256',"", ...
    'PairingStatus',"paired_exact_common_operands", ...
    'Definition',"DMRS_minus_CSI_RS_NMSE_on_identical_independent_reference_and_resource_support", ...
    'EvidenceScope',"engineering_comparison_not_normative_or_statistically_qualified");
end
