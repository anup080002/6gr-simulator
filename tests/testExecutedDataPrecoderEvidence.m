function ok=testExecutedDataPrecoderEvidence(outputRoot,direction)
% Actual shared-clock TX fixture, not full scheduler or access qualification.
if nargin<1, outputRoot=tempname; end
if nargin<2, direction="DL"; end
assert(any(string(direction)==["DL","UL"]));
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve prior evidence; use a new folder.');
if string(direction)=="DL"
    [passed,state]=testSharedDataPhysicalQueue('TDD'); signal="PDSCH";
else
    [passed,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,false,true,true); signal="PUSCH";
end
assert(passed);
w=state.AppliedDataPrecoderWeights; p=state.AppliedDataPrecoderPatterns;
assert(~isempty(w) && ~isempty(p));
assert(numel(unique(w.TransmissionID))==numel(state.SharedDataTXLedger));
assert(isequal(unique(w.TransmissionID),unique(p.TransmissionID)));
assert(all(w.Signal==signal) && all(p.SelectedBeamApplied) && ~any(p.OverTheAirMeasurement));
assert(all(p.PatternKind=="data_precoder_directivity_before_node_rf"));
keys=unique(w(:,{'TransmissionID','PRGIndex0','SymbolGroupIndex0'}),'rows');
for k=1:height(keys)
    r=w(w.TransmissionID==keys.TransmissionID(k) & ...
        w.PRGIndex0==keys.PRGIndex0(k) & w.SymbolGroupIndex0==keys.SymbolGroupIndex0(k),:);
    ports=max(r.ElementIndex0)+1; layers=max(r.LayerIndex0)+1;
    assert(height(r)==ports*layers);
    values=complex(zeros(ports,layers));
    for j=1:height(r), values(r.ElementIndex0(j)+1,r.LayerIndex0(j)+1)=complex(str2double(r.WeightReal(j)),str2double(r.WeightImag(j))); end
    assert(all(r.MatrixSHA256==sixgr.phy.mimo.MatrixContract.digest(values)));
    hit=find(arrayfun(@(x)x.Identity.TransmissionID==keys.TransmissionID(k), ...
        state.SharedWaveformStream.DataTransmissions));
    assert(isscalar(hit));
end
mkdir(outputRoot);
sixgr.util.csvWriteTable(fullfile(outputRoot,'applied_data_precoder_weights.csv'),w,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(outputRoot,'applied_data_precoder_patterns.csv'),p,'PreserveSchema',true);
fprintf('EXECUTED_DATA_PRECODER_EVIDENCE_PASS transmissions=%d weights=%d patterns=%d folder=%s\n', ...
    height(keys),height(w),height(p),outputRoot);
ok=true;
end
