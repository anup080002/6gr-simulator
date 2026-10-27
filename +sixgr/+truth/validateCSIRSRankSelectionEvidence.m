function validateCSIRSRankSelectionEvidence(decision,prepared,reception,csi)
if isstruct(decision)&&isfield(decision,'ContractVersion') && ...
        string(decision.ContractVersion)=="sixgr.portable_TypeI_MMSE_rank_decision/v1"
    sixgr.truth.validatePortableCSIRankSelectionEvidence(decision,prepared,reception,csi);
    return;
end

% Validate retained MaxSE operands against the ORIGINAL completed receiver.
% No receiver, PMI/CQI/rank search, channel or RF execution occurs here.
% Arithmetic consistency is not independent optimality, decoded BLER or
% standardized accuracy. PMI hashes are retained identities, not a replay
% of unretained candidate matrices. This v1 adapter is release-pinned.
id='sixgr:truth:CSIRankSelectionEvidenceMismatch';
required=["ContractVersion","Source","MATLABRelease","RankDomain", ...
    "RequestedRankDomain","ObjectiveByRank","SelectedRank","SelectedObjective", ...
    "TiePolicy","ObjectiveDefinition","Classification","ReferencePlane", ...
    "ChannelSHA256","DisturbanceSHA256","Configuration","Candidates", ...
    "RankSearchCallCount","AdditionalRankSearches","DecodedBLERAvailable", ...
    "IndependentSelectionQualityVerified","StandardizedAccuracyQualified", ...
    "MeasurementID","MeasurementDigest","MeasurementSlot", ...
    "ReportConfigID","ReportConfigurationEpoch"];
localStruct(decision,required,id);
localEqualsText(decision.ContractVersion,"sixgr.native_MaxSE_rank_decision/v1",id);
localEqualsText(decision.Source,"original_nr5g_nrCQISelect_per_admissible_rank",id);
localEqualsText(decision.MATLABRelease,"2026a",id);
localEqualsText(decision.TiePolicy,"first_rank_returned_by_MATLAB_max",id);
localEqualsText(decision.ObjectiveDefinition, ...
    "sum_codewords_layers_times_one_minus_model_BLER_times_CQI_spectral_efficiency",id);
localEqualsText(decision.Classification,"MATLAB_BEHAVIOR_IMPLEMENTATION_POLICY",id);
localEqualsText(decision.ReferencePlane, ...
    "native_CQI_selection_model_on_supplied_received_channel_and_disturbance",id);
for field=["DecodedBLERAvailable","IndependentSelectionQualityVerified","StandardizedAccuracyQualified"]
    assert(islogical(decision.(field))&&isscalar(decision.(field))&&~decision.(field),id, ...
        'A model decision cannot acquire measurement/accuracy authority.');
end
assert(isstruct(prepared)&&isscalar(prepared)&&isfield(prepared,'ReceiverConfig')&& ...
    isfield(prepared,'Carrier')&&isa(prepared.Carrier,'nrCarrierConfig')&& ...
    isstruct(reception)&&isscalar(reception)&&isfield(reception,'CSIMeasurementState')&& ...
    isa(reception.CSIMeasurementState,'sixgr.phy.mimo.CSIMeasurementState'),id, ...
    'The original prepared configuration and immutable reception state are required.');
state=reception.CSIMeasurementState;
cfg=prepared.ReceiverConfig;
carrier=prepared.Carrier;
request=sixgr.util.structGet(cfg,'phy.csi.reportConfiguration',[]);
assert(isstruct(request)&&isscalar(request)&&all(isfield(request, ...
    {'ReportConfigID','Epoch','CodebookType','N1','N2','FrequencyGranularity'})),id, ...
    'Use the original installed report, not the returned report as its own authority.');
localEqualsText(decision.MeasurementID,state.MeasurementID,id);
localEqualsText(decision.MeasurementDigest,state.Digest,id);
localEqualsText(decision.ReportConfigID,request.ReportConfigID,id);
localInteger(decision.MeasurementSlot,0,id);
localInteger(decision.ReportConfigurationEpoch,0,id);
assert(isequal(decision.MeasurementSlot,state.Slot)&& ...
    isequal(decision.ReportConfigurationEpoch,double(request.Epoch))&& ...
    state.Slot==double(carrier.NFrame)*double(carrier.SlotsPerFrame)+double(carrier.NSlot)+1,id, ...
    'Observation slot and report epoch must retain their original authorities.');
for pair={"CSIMeasurementID","MeasurementID"; "CSIMeasurementDigest","MeasurementDigest"; ...
        "CSIReportConfigID","ReportConfigID"}.'
    assert(isfield(csi,pair{1}),id,'Missing returned measurement/report identity.');
    localEqualsText(csi.(pair{1}),decision.(pair{2}),id);
end
assert(all(isfield(csi,{'CSIMeasurementSlot','CSIConfigurationEpoch','RI'}))&& ...
    isequal(csi.CSIMeasurementSlot,state.Slot)&& ...
    isequal(csi.CSIConfigurationEpoch,decision.ReportConfigurationEpoch)&& ...
    isequal(csi.RI,decision.SelectedRank),id,'Returned decision identity differs from the original receiver.');
% The full native H is NOT the reduced, double snapshot tensor in Digest.
assert(isfield(reception,'CSIRSChannelEstimate')&&isfield(reception,'CSIRSNoiseVar'),id, ...
    'Retain original native selection H and measured noise.');
H=reception.CSIRSChannelEstimate;
assert(isnumeric(H)&&ndims(H)==4&&~isempty(H)&&all(isfinite(H(:)))&& ...
    size(H,1)==12*carrier.NSizeGrid&&size(H,2)==carrier.SymbolsPerSlot&& ...
    size(H,3)==size(state.ChannelEstimate,1)&&size(H,4)==size(state.ChannelEstimate,2),id, ...
    'Original full CSI estimate dimensions do not match this reception.');
localHash(decision.ChannelSHA256,id);
localEqualsText(decision.ChannelSHA256,sixgr.phy.waveform.WaveformHash.runtimeArray(H),id);
assert(isnumeric(state.NoiseVariance)&&isnumeric(reception.CSIRSNoiseVar),id,'Measured noise must be numeric.');
noise=double(state.NoiseVariance);
assert(isreal(noise)&&isscalar(noise)&&isfinite(noise)&&noise>=0&& ...
    isequal(noise,double(reception.CSIRSNoiseVar)),id,'Measured noise must remain the original scalar.');
R=state.InterferenceCovariance;
includesNoise=state.InterferenceCovarianceIncludesNoise;
if isa(R,'sixgr.phy.mimo.InterferenceCovarianceState')
    includesNoise=R.IncludesNoise;
    R=R.Matrix;
end
if isempty(R)
    disturbance=noise;
else
    assert(isnumeric(R)&&isequal(size(R),[size(H,3) size(H,3)])&&all(isfinite(R(:))),id, ...
        'Original disturbance covariance has invalid dimensions.');
    disturbance=double(R);
    if ~includesNoise, disturbance=disturbance+noise*eye(size(H,3)); end
end
localHash(decision.DisturbanceSHA256,id);
localEqualsText(decision.DisturbanceSHA256,sixgr.phy.waveform.WaveformHash.runtimeArray(disturbance),id);
domain=localConfiguration(decision.Configuration,cfg,carrier,request,state,id);
assert(isequal(decision.RequestedRankDomain,domain)&&isequal(decision.RankDomain,domain),id, ...
    'The actual independent CSI facade must retain its original allowed rank population.');
assert(isa(decision.ObjectiveByRank,'double')&&isreal(decision.ObjectiveByRank)&& ...
    isequal(size(decision.ObjectiveByRank),[max(domain) 1])&& ...
    iscell(decision.Candidates)&&isequal(size(decision.Candidates),[1 numel(domain)])&& ...
    isequal(decision.RankSearchCallCount,double(numel(domain)))&& ...
    isequal(decision.AdditionalRankSearches,0),id,'Incomplete rank population or invalid search count.');
tables=nrCQITables;
number=find(strcmpi(localCQITable(decision.Configuration.CQITable,id), ...
    ["table1","table2","table3","table4-r17"]));
tableData=tables.("CQITable"+number);
expected=nan(max(domain),1);
fields=["Rank","WidebandCQI","ModelEstimatedTransportBLER","CodewordLayerCounts", ...
    "CQITableSpectralEfficiency","Objective","Status","RankSearchPMI","RankSearchPrecoderSHA256"];
for k=1:numel(domain)
    candidate=decision.Candidates{k}; rankValue=domain(k);
    localStruct(candidate,fields,id);
    assert(isequal(candidate.Rank,rankValue),id,'Candidate rank order/population changed.');
    ncw=1+(rankValue>4);
    for field=["WidebandCQI","ModelEstimatedTransportBLER","CodewordLayerCounts","CQITableSpectralEfficiency"]
        value=candidate.(field);
        assert(isnumeric(value)&&isreal(value)&&isequal(size(value),[1 ncw]),id, ...
            'Each original candidate must retain the complete codeword operand vectors.');
    end
    q=candidate.WidebandCQI; bler=candidate.ModelEstimatedTransportBLER;
    assert(all(isnan(q)|(isfinite(q)&q==fix(q)&q>=0&q<=15))&& ...
        all(isnan(bler)|(isfinite(bler)&bler>=0&bler<=1)),id,'Invalid CQI or model-estimated BLER.');
    layers=floor((rankValue+(0:ncw-1))/ncw);
    assert(isequal(candidate.CodewordLayerCounts,layers),id,'Codeword layer split changed.');
    spectral=nan(1,ncw);
    status="native_CQI_unavailable";
    if any(q==0)
        expected(rankValue)=0;
        status="native_out_of_range_CQI_zero_objective";
    elseif all(~isnan(q))
        assert(all(isfinite(bler)),id,'Available model objective needs all original BLER operands.');
        values=tableData.SpectralEfficiency(q+1);
        spectral=reshape(values,1,ncw);
        % Same multiplication/order as the producer, not a refit or rescore.
        expected(rankValue)=(layers.*(1-bler))*values;
        status="native_model_objective_available_not_decoded_BLER";
    end
    assert(isequaln(candidate.CQITableSpectralEfficiency,spectral)&& ...
        isequaln(candidate.Objective,expected(rankValue)),id,'Candidate operand/arithmetic mismatch.');
    localEqualsText(candidate.Status,status,id);
    localStruct(candidate.RankSearchPMI,["i1","i2"],id);
    for field=["i1","i2"]
        value=candidate.RankSearchPMI.(field);
        assert(isnumeric(value)&&isreal(value)&&~isempty(value)&&ndims(value)<=3&& ...
            all(isnan(value(:))|(isfinite(value(:))&value(:)==fix(value(:))&value(:)>=0)),id, ...
            'Retain the native candidate PMI index operands.');
    end
    localHash(candidate.RankSearchPrecoderSHA256,id);
end
[best,rankValue]=max(expected);
assert(isequaln(decision.ObjectiveByRank,expected)&&isfinite(best)&& ...
    isequal(decision.SelectedRank,rankValue)&&isequal(decision.SelectedObjective,best),id, ...
    'Complete original objective population and deterministic first maximum must agree.');
end

function domain=localConfiguration(actual,cfg,carrier,request,state,id)
% Check effective native settings against prepared ownership. Do not create
% another selector/config normalizer. Unused native defaults are shape-checked
% only; their presence is not independent verification of an executed search.
fields=["NStartBWP","NSizeBWP","CQITable","CodebookType","PanelDimensions", ...
    "CodebookMode","CQIFormatIndicator","PMIFormatIndicator","RIRestriction", ...
    "CodebookSubsetRestriction","I2Restriction","NumberOfBeams","PhaseAlphabetSize", ...
    "SubbandAmplitude","SubbandSize","PRGBundleSize"];
localStruct(actual,fields,id);
assert(isequal(actual.NStartBWP,double(carrier.NStartGrid))&& ...
    isequal(actual.NSizeBWP,double(carrier.NSizeGrid)),id,'Original native BWP changed.');
table=sixgr.util.structGet(cfg,'phy.csi.cqiTable',sixgr.util.structGet(cfg,'phy.csi.dlCQITable','table1'));
localEqualsText(localCQITable(actual.CQITable,id),localCQITable(table,id),id);
codebook=lower(regexprep(localText(request.CodebookType,id),'[^a-zA-Z0-9]',''));
typeII=codebook=="typeii";
assert(typeII||ismember(codebook,["typeisinglepanel","type1singlepanel"]),id,'Unsupported decision codebook.');
expected="type1SinglePanel"; maximum=8;
if typeII, expected="type2"; maximum=2; end
localEqualsText(lower(localText(actual.CodebookType,id)),lower(expected),id);
assert(isequal(actual.PanelDimensions,[double(sixgr.util.structGet(request,'Panels',1)), ...
    double(request.N1),double(request.N2)]),id,'Original panel dimensions changed.');
for field=["CodebookMode","NumberOfBeams","PhaseAlphabetSize","SubbandSize"]
    localInteger(actual.(field),1,id);
end
assert(islogical(actual.SubbandAmplitude)&&isscalar(actual.SubbandAmplitude)&& ...
    isnumeric(actual.PRGBundleSize)&&isreal(actual.PRGBundleSize)&& ...
    (isempty(actual.PRGBundleSize)|| ...
    (isscalar(actual.PRGBundleSize)&&isfinite(actual.PRGBundleSize)&&actual.PRGBundleSize>=1)),id, ...
    'Malformed native configuration snapshot.');
if typeII
    assert(all(isfield(request,{'NumberOfBeams','PhaseAlphabetSize'}))&& ...
        isequal(actual.NumberOfBeams,double(request.NumberOfBeams))&& ...
        isequal(actual.PhaseAlphabetSize,double(request.PhaseAlphabetSize))&& ...
        isequal(actual.SubbandAmplitude,false),id,'Original Type-II configuration changed.');
else
    assert(isfield(request,'CodebookMode')&&isequal(actual.CodebookMode,double(request.CodebookMode)),id, ...
        'Original Type-I codebook mode changed.');
end
format=lower(localText(request.FrequencyGranularity,id));
localEqualsText(lower(localText(actual.CQIFormatIndicator,id)),format,id);
localEqualsText(lower(localText(actual.PMIFormatIndicator,id)),format,id);
if format=="subband"
    assert(isequal(actual.SubbandSize,double(sixgr.util.structGet(request,'SubbandSize',4))),id, ...
        'Original subband size changed.');
end
for field=["CodebookSubsetRestriction","I2Restriction"]
    assert(isequal(actual.(field),double(sixgr.util.structGet(request,field,[]))),id, ...
        'Original codebook restriction changed.');
end
limit=min([double(sixgr.util.structGet(cfg,'phy.csi.maxRank', ...
    min(size(state.ChannelEstimate,1),size(state.ChannelEstimate,2)))), ...
    size(state.ChannelEstimate,1),size(state.ChannelEstimate,2)]);
limit=min(limit,double(sixgr.util.structGet(request,'MaxRank',limit)));
localInteger(limit,1,id);
domain=1:limit;
for restriction={sixgr.util.structGet(cfg,'phy.csi.rankDomain',[]), ...
        sixgr.util.structGet(request,'AllowedRanks',[])}
    value=double(restriction{1});
    if isempty(value), continue; end
    assert(isvector(value)&&all(isfinite(value)&value>=1&value==fix(value)),id,'Invalid original rank restriction.');
    domain=intersect(domain,value(:).','stable');
end
policy=sixgr.mimo.resolveRankPolicy(cfg);
if policy.FixedRankAnchor
    fixed=double(sixgr.util.structGet(cfg,'phy.pdsch.numLayers',sixgr.util.structGet(cfg,'phy.pdsch.nLayers',1)));
    assert(isscalar(fixed)&&ismember(fixed,domain),id,'Original fixed-rank authority changed.');
    domain=fixed;
end
assert(~isempty(domain)&&all(domain<=maximum),id,'No supported original rank population.');
restriction=zeros(1,maximum); restriction(domain)=1;
assert(isequal(actual.RIRestriction,restriction),id,'Original RI restriction changed.');
end

function localStruct(value,names,id)
assert(isstruct(value)&&isscalar(value)&& ...
    isequal(sort(string(fieldnames(value))),sort(names(:))),id,'Incomplete or augmented decision operand schema.');
end
function token=localText(value,id)
assert((isstring(value)&&isscalar(value))||(ischar(value)&&isrow(value)),id,'Expected one original text token.');
token=string(value);
assert(~ismissing(token)&&strlength(strtrim(token))>0,id,'Missing original text token.');
end
function localEqualsText(value,expected,id)
assert(localText(value,id)==localText(expected,id),id,'Original text/identity token mismatch.');
end
function localHash(value,id)
token=localText(value,id);
assert(~isempty(regexp(char(token),'^[0-9A-Fa-f]{64}$','once')),id,'Missing original SHA256 identity.');
end
function token=localCQITable(value,id)
token=lower(localText(value,id));
% Native validatestring accepts table4 and stores its canonical table4-r17.
if token=="table4", token="table4-r17"; end
assert(ismember(token,["table1","table2","table3","table4-r17"]),id,'Invalid CQI table.');
end
function localInteger(value,minimum,id)
assert(isa(value,'double')&&isreal(value)&&isscalar(value)&&isfinite(value)&& ...
    value>=minimum&&value==fix(value)&&value<flintmax,id,'Expected exact scalar original integer.');
end
