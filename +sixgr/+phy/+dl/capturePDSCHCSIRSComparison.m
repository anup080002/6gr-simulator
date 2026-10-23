function capture=capturePDSCHCSIRSComparison(rx)
% Retain both ACTUAL estimates from one receiver grid, without a reference.
% These operands are post-reception diagnostics; no CSI/PDSCH decision reads
% them. A later owner must bind executed spatial/power maps and its reference.
capture=struct('Contract',"same_grid_PDSCH_CSI_RS_estimates/v1", ...
    'Status',"unavailable_no_received_CSI_RS_estimate",'Resources',struct([]), ...
    'ReferenceUsedByReceiver',false,'AdditionalReceiverExecutions',0);
required={'EffectiveLayerChannelEstimate','DMRSIndices','DMRSSymbols', ...
    'Carrier','ReceiverChannelOperator','OFDMInfo','RxGrid','CSIRSChannelEstimation','CSIRSInfo'};
assert(isstruct(rx) && isscalar(rx) && all(isfield(rx,required)), ...
    'sixgr:phy:dl:PairedChannelCaptureSchema','Capture original completed receiver operands.');
est=rx.CSIRSChannelEstimation;
if ~isfield(est,'Available') || ~isequal(est.Available,true), return; end
h=rx.EffectiveLayerChannelEstimate;
if isempty(h)
    capture.Status="unavailable_effective_layer_estimate_not_retained"; return;
end
shape=[size(h,1),size(h,2),size(h,3),size(h,4)];
assert(isequal(shape(1:3),[size(rx.RxGrid,1),size(rx.RxGrid,2),size(rx.RxGrid,3)]) && ...
    shape(1)==12*rx.Carrier.NSizeGrid && shape(2)==rx.Carrier.SymbolsPerSlot, ...
    'sixgr:phy:dl:PairedChannelCapturePlane','Both estimators must use the same native FFT/receive branches.');
indices=double(rx.DMRSIndices(:)); symbols=rx.DMRSSymbols(:);
assert(numel(indices)==numel(symbols) && ~isempty(indices) && ...
    all(isfinite(indices) & indices>=1 & indices<=prod(shape([1 2 4])) & indices==fix(indices)) && ...
    numel(unique(indices))==numel(indices) && all(isfinite(symbols) & abs(symbols)>0), ...
    'sixgr:phy:dl:PairedChannelCaptureSupport','Retain actual unique DMRS indices and symbols.');
[k,l,~]=ind2sub(shape([1 2 4]),indices);
support=unique([k-1,l-1],'rows');
resources=sixgr.util.structGet(rx.CSIRSInfo,'Resources',struct([]));
if isempty(resources)
    if ~all(isfield(rx,{'CSIRSIndices','CSIRSSymbols'})) || ~isfield(rx.CSIRSInfo,'ResourceID'), return; end
    resources=struct('ResourceID',rx.CSIRSInfo.ResourceID, ...
        'Indices',rx.CSIRSIndices,'Symbols',rx.CSIRSSymbols);
end
capture.Carrier=rx.Carrier;
capture.ReceiverOFDMInfo=rx.OFDMInfo;
capture.ReceiverChannelOperator=rx.ReceiverChannelOperator;
capture.ReceivedGridSHA256=string(sixgr.phy.waveform.WaveformHash.runtimeArray(rx.RxGrid));
capture.GridShape=shape;
capture.DMRSPilotIndices=indices; capture.DMRSPilotSymbols=symbols;
capture.DMRSFullEstimateSHA256=string(sixgr.phy.waveform.WaveformHash.runtimeArray(h));
capture.EvaluationSupport="DMRS_pilot_coordinate_union_within_received_CSI_RS_sounded_PRBs";
capture.EstimationSupport="actual_native_interpolation_in_same_received_slot_not_equal_pilot_support";
capture.MeasurementPlane="same_post_front_end_native_OFDM_grid_before_equalization";
for ordinal=1:numel(resources)
    resource=resources(ordinal);
    if isfield(est,'ResourceMeasurements')
        measurement=est.ResourceMeasurements(ordinal);
        assert(measurement.ResourceID==resource.ResourceID, ...
            'sixgr:phy:dl:PairedChannelCaptureResource','Keep actual installed resource identity/order.');
        if ~measurement.Available, continue; end
        ch=measurement.Hest; info=measurement.EstimationInfo;
    else
        assert(numel(resources)==1 && isfield(rx,'CSIRSChannelEstimate'), ...
            'sixgr:phy:dl:PairedChannelCaptureResource','A singleton estimate cannot stand for multiple resources.');
        ch=rx.CSIRSChannelEstimate; info=est;
    end
    cshape=[size(ch,1),size(ch,2),size(ch,3),size(ch,4)];
    assert(isequal(cshape(1:3),shape(1:3)), ...
        'sixgr:phy:dl:PairedChannelCapturePlane','CSI-RS must retain the original receiver grid/branch dimensions.');
    ci=double(resource.Indices(:)); cs=resource.Symbols(:);
    assert(~isempty(ci) && numel(ci)==numel(cs) && ...
        all(isfinite(ci) & ci>=1 & ci<=prod(cshape([1 2 4])) & ci==fix(ci)) && ...
        numel(unique(ci))==numel(ci) && all(isfinite(cs) & abs(cs)>0), ...
        'sixgr:phy:dl:PairedChannelCaptureSupport','Retain the actual CSI-RS pilot coordinates and symbols.');
    [ck,cl,~]=ind2sub(cshape([1 2 4]),ci);
    evalSupport=support(ismember(floor(support(:,1)/12),unique(floor((ck-1)/12))),:);
    if isempty(evalSupport), continue; end
    dh=localSample(h,evalSupport); csh=localSample(ch,evalSupport);
    % Missing native values are not exporter-side interpolated or discarded.
    status="captured_same_grid_estimates_reference_not_bound";
    if any(~isfinite(dh),'all') || any(~isfinite(csh),'all')
        status="unavailable_nonfinite_native_estimate_on_common_support";
    end
    entry=struct('ResourceID',double(resource.ResourceID),'ResourceOrdinal0',ordinal-1, ...
        'Status',status,'Support',evalSupport,'DMRSEstimate',dh,'CSIRSEstimate',csh, ...
        'CSIRSPilotIndices',ci,'CSIRSPilotSymbols',cs, ...
        'CSIRSPilotSupport',unique([ck-1,cl-1],'rows'), ...
        'CSIRSFullEstimateSHA256',string(sixgr.phy.waveform.WaveformHash.runtimeArray(ch)), ...
        'CSIRSEstimationInfo',info);
    if isempty(capture.Resources)
        capture.Resources=entry;
    else
        capture.Resources(end+1)=entry; %#ok<AGROW>
    end
end
if ~isempty(capture.Resources), capture.Status="captured_same_grid_estimates_reference_not_bound"; end
end

function values=localSample(h,support)
values=complex(zeros(size(h,3),size(h,4),size(support,1),'like',h));
for q=1:size(support,1)
    values(:,:,q)=reshape(h(support(q,1)+1,support(q,2)+1,:,:),size(h,3),size(h,4));
end
end
