function [weights,patterns]=buildExecutedDataPrecoderEvidence(owner,prepared,ue)
% Applied data weights, never a scalar-PMI reconstruction or receiver oracle.
weights=table(); patterns=table();
cfg=prepared.ReceiverConfig;
if ~logical(sixgr.util.structGet(cfg,'outputs.antennaPatternSamplesEnabled',false)), return; end
identity=sixgr.truth.preparedDataTransmissionIdentity(prepared,ue);
records=owner.DataTransmissions;
hit=arrayfun(@(r)r.Identity.TransmissionID==identity.TransmissionID,records);
assert(nnz(hit)==1 && isequaln(records(hit).Identity,identity) && ...
    records(hit).CommittedAtSample<=owner.Events.NextSampleIndex, ...
    'sixgr:truth:PrecoderTransmissionNotExecuted', ...
    'Prepared or requested weights alone are not evidence of a started transmission.');
tx=prepared.Tx;
if prepared.Direction=="DL"
    bundle=tx.PrecoderBundle;
    assert(isa(bundle,'sixgr.pdsch.PDSCHPrecoderBundle'), ...
        'sixgr:truth:AppliedPrecoderBundleMissing','Retain the exact executed PDSCH precoder bundle.');
    W=bundle.W; matrixSource=bundle.MatrixSource;
    prbSets=bundle.PRGToPRBMap; symbolSets=cell(1,bundle.NSymbolGroups);
    for g=1:bundle.NSymbolGroups
        symbolSets{g}=bundle.ScheduledSymbols(bundle.SymbolGroupIndexPerSymbol==g-1);
    end
    antenna=cfg.lls6g.userContext.RuntimeServingBSAntenna;
    signal="PDSCH";
else
    W=tx.PrecodeInfo.MatrixPorts; matrixSource=string(tx.PrecodeInfo.Source);
    assert(ismatrix(W),'sixgr:truth:AppliedULPrecoderShape', ...
        'UL matrix evidence must retain its actual port-by-layer orientation.');
    prbSets={double(tx.PUSCH.PRBSet(:).')};
    sa=double(tx.PUSCH.SymbolAllocation);
    symbolSets={sa(1)+(0:sa(2)-1)};
    antenna=cfg.lls6g.userContext.RuntimeUEAntenna;
    signal="PUSCH";
end
validateattributes(W,{'double','single'},{'nonempty','finite'});
projection=records(hit).WaveformToElementMatrix;
validateattributes(projection,{'double','single'},{'2d','nonempty','finite'});
assert(size(projection,1)==prepared.NumPhysicalTransmitAntennas && ...
    size(projection,2)==size(tx.Waveform,2) && ...
    size(W,1)==size(projection,2) && size(W,3)==numel(prbSets) && ...
    size(W,4)==numel(symbolSets), ...
    'sixgr:truth:AppliedPrecoderPhysicalDomainMismatch', ...
    'The exported matrix must address the actual physical transmitter columns.');
array=antenna.ArrayObj;
assert(isa(array,'phased.NRRectangularPanelArray'), ...
    'sixgr:truth:AppliedPrecoderArrayUnavailable','Use the installed physical array, not rebuilt geometry.');
positions=double(getElementPosition(array).');
assert(isequal(size(positions),[size(projection,1) 3]) && ...
    isequal(size(antenna.ElementPositions_m),size(positions)) && ...
    norm(positions-double(antenna.ElementPositions_m),'fro')<=1e-10, ...
    'sixgr:truth:AppliedPrecoderElementOrderMismatch', ...
    'Physical waveform column ordering must agree with the installed array element ordering.');
fc=double(antenna.Fc_Hz); validateattributes(fc,{'double'},{'scalar','positive','finite'});
az=localAxis(cfg,'Azimuth'); el=localAxis(cfg,'Elevation');
for p=1:size(W,3)
    for g=1:size(W,4)
        page=double(W(:,:,p,g));
        if prepared.Direction=="DL"
            shapeBytes=typecast(uint64([size(page,1) size(page,2)]),'uint8');
            valueBytes=typecast([real(page(:));imag(page(:))],'uint8');
            bundleDigest=string(sixgr.util.sha256Hex([shapeBytes(:);valueBytes(:)]));
            assert(bundleDigest==bundle.MatrixDigestPerSlice(p,g), ...
                'sixgr:truth:AppliedPrecoderDigestMismatch','The retained matrix digest changed after mapping.');
        end
        % The stream owner applies this mapping after PUSCH/PDSCH preparation.
        % MatrixPorts can still be logical-port-domain (notably 1 port onto
        % multiple UE elements). Never pad it or rebuild the applied mapping.
        page=double(projection)*page;
        sha=sixgr.phy.mimo.MatrixContract.digest(page);
        for layer=1:size(W,2)
            vector=page(:,layer);
            assert(sum(abs(vector).^2)>0,'sixgr:truth:ZeroAppliedPrecoderLayer', ...
                'An active data layer cannot have an all-zero physical weight vector.');
            r=localIdentity(identity,signal,p-1,g-1,layer-1,sha,fc,numel(vector));
            r.ElementIndex0=(0:numel(vector)-1).';
            % writetable numeric output is not binary64 round-trip safe.
            % Explicit 17-digit decimal strings preserve the hashed matrix
            % exactly when a CSV consumer parses these numeric values.
            r.WeightReal=compose('%.17g',real(vector));
            r.WeightImag=compose('%.17g',imag(vector));
            r.ElementX_m=positions(:,1); r.ElementY_m=positions(:,2); r.ElementZ_m=positions(:,3);
            r.MatrixSource=repmat(string(matrixSource),height(r),1);
            r.PRBSet0=repmat(string(jsonencode(prbSets{p})),height(r),1);
            r.SymbolSet0=repmat(string(jsonencode(symbolSets{g})),height(r),1);
            r.Source=repmat("executed_data_precoder_mapping_shared_transmission_started",height(r),1);
            r.ReferencePlane=repmat("physical_element_data_grid_before_node_rf",height(r),1);
            weights=[weights;r]; %#ok<AGROW>
            % pattern() uses receive/steering-vector weights; the waveform
            % applies X=W*S. Conjugate the actual transmit column for this
            % diagnostic only. Never change W, its scale or transmitted IQ.
            d=sixgr.truth.sampleAppliedDataPrecoderPattern(array,fc,az,el,vector);
            assert(isequal(size(d),[numel(el) numel(az)]) && ...
                ~any(isnan(d(:)) | d(:)==Inf), ...
                'sixgr:truth:AppliedPrecoderPatternInvalid','Runtime array must return a valid angular directivity grid.');
            [azGrid,elGrid]=meshgrid(az,el);
            r=localIdentity(identity,signal,p-1,g-1,layer-1,sha,fc,numel(d));
            r.Azimuth_deg=azGrid(:); r.Elevation_deg=elGrid(:); r.Directivity_dBi=d(:);
            r.PatternKind=repmat("data_precoder_directivity_before_node_rf",height(r),1);
            r.PatternSource=repmat("executed_matrix_and_installed_NRRectangularPanelArray",height(r),1);
            r.CoordinateFrame=repmat("local_array_before_runtime_orientation",height(r),1);
            r.ArrayClass=repmat(string(class(array)),height(r),1);
            r.ElementModel=repmat(string(antenna.ElementModel),height(r),1);
            r.SelectedBeamApplied=true(height(r),1);
            r.OverTheAirMeasurement=false(height(r),1);
            patterns=[patterns;r]; %#ok<AGROW>
        end
    end
end
end

function r=localIdentity(id,signal,prg,group,layer,sha,fc,n)
r=table(repmat(id.TransmissionID,n,1),repmat(id.PHYGrantContextId,n,1), ...
    repmat(id.Direction,n,1),repmat(signal,n,1),repmat(id.UEIndex,n,1), ...
    repmat(id.StartSample,n,1),repmat(id.EndSampleExclusive,n,1), ...
    repmat(id.SampleRateHz,n,1),repmat(fc,n,1), ...
    repmat(prg,n,1),repmat(group,n,1),repmat(layer,n,1),repmat(sha,n,1), ...
    'VariableNames',{'TransmissionID','PHYGrantContextId','Direction','Signal','UEIndex', ...
    'StartSample','EndSampleExclusive','SampleRate_Hz','Frequency_Hz', ...
    'PRGIndex0','SymbolGroupIndex0','LayerIndex0','MatrixSHA256'});
r.MatrixDigestConvention=repmat("sixgr-mimo-matrix-v1",n,1);
end

function axis=localAxis(cfg,name)
prefix="outputs.antennaPattern"+name;
lo=double(sixgr.util.structGet(cfg,prefix+"Min_deg",NaN));
hi=double(sixgr.util.structGet(cfg,prefix+"Max_deg",NaN));
step=double(sixgr.util.structGet(cfg,prefix+"Step_deg",NaN));
assert(all(isfinite([lo hi step])) && hi>lo && step>0, ...
    'sixgr:truth:AppliedPatternSamplingConfig','Angular sampling must come from valid YAML policy.');
axis=lo:step:hi;
if axis(end)<hi-1e-9, axis(end+1)=hi; end
end
