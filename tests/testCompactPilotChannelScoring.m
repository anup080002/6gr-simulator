function ok=testCompactPilotChannelScoring()
% Algebra/storage equivalence only, not a physical BLER or channel result.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'results','lls','compact_pilot_channel_scoring', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
cases=[72 14 1 1;72 14 4 2;72 14 2 4;3276 14 64 4];
evidence=cell(size(cases,1),1);
for c=1:size(cases,1)
    shape=cases(c,:); K=shape(1); R=shape(3); P=shape(4);
    [k,l,p]=ndgrid(1:2:K,[4 11],1:P);
    indices=sub2ind(shape([1 2 4]),k(:),l(:),p(:));
    reference=complex(ones(shape),zeros(shape));
    estimate=reference;
    sampled=complex(zeros(numel(indices),R));
    for r=1:R
        at=sub2ind(shape,k(:),l(:),repmat(r,numel(k),1),p(:));
        h=(1+.01*r+.03*p(:)).*exp(1i*(.001*k(:)+.02*l(:)));
        reference(at)=h;
        sampled(:,r)=h.*(1+.01*p(:))+.001i*r;
        estimate(at)=sampled(:,r);
    end
    expected=sixgr.phy.srs.pilotChannelNMSE(estimate,reference,indices);
    snapshot=struct('Contract',"PUSCH_pilot_channel_capture/v1", ...
        'GridShape',shape,'PilotIndices',indices,'PilotChannelValues',sampled);
    before=snapshot;
    actual=sixgr.phy.srs.pilotChannelNMSE(snapshot,reference,indices);
    [sameScore,h,t]=sixgr.phy.srs.pilotChannelNMSE(snapshot,reference,indices);
    assert(isequaln(actual,sameScore));
    assert(isequaln(actual,expected) && isequaln(h,sampled) && isequaln(snapshot,before), ...
        'Compact scoring must preserve all operands and never change receiver evidence.');
    assert(isequal(size(h),[numel(indices) R]) && isequal(size(t),size(h)));
    context=struct('Channel',"PUSCH",'Slot',45,'UEIndex',1,'ConfiguredSNR_dB',40, ...
        'ChannelEstimateSource',"explicit_algebra_fixture_not_PHY", ...
        'ChannelReferenceSource',"explicit_independent_algebra_reference", ...
        'ChannelReferencePlane',"unit_test_reference_not_performance_evidence");
    [rows,tableScore]=sixgr.report.buildReceiverChannelEstimateTable(snapshot,reference,indices,context);
    assert(isequaln(tableScore,expected) && height(rows)==numel(sampled) && ...
        isequaln(complex(rows.HReal,rows.HImag),sampled(:)) && ...
        isequaln(complex(rows.ReferenceHReal,rows.ReferenceHImag),t(:)));
    if c<size(cases,1)
        legacy=sixgr.report.buildReceiverChannelEstimateTable(estimate,reference,indices,context);
        assert(isequaln(rows,legacy),'Full-grid and compact primary tables must be identical.');
        for direction=["PDSCH","PUSCH"]
            snapshot.Contract=direction+"_pilot_channel_capture/v1";
            context.Channel=direction;
            compact=sixgr.report.buildReceiverChannelEstimateTable(snapshot,reference,indices,context);
            full=sixgr.report.buildReceiverChannelEstimateTable(estimate,reference,indices,context);
            assert(isequaln(compact,full));
        end
        singleSnapshot=snapshot;
        singleSnapshot.PilotChannelValues=single(singleSnapshot.PilotChannelValues);
        converted=sixgr.phy.srs.pilotChannelNMSE(singleSnapshot,single(reference),indices);
        native=sixgr.phy.srs.pilotChannelNMSE(single(estimate),single(reference),indices);
        assert(isequaln(converted,native),'Single-precision captures keep the legacy double-precision accumulation.');
        localNegativeChecks(snapshot,reference,indices);
    end
    small=whos('snapshot'); large=whos('estimate');
    evidence{c}=struct('K',K,'L',shape(2),'ReceiveBranches',R,'Ports',P, ...
        'FullGridValues',prod(shape),'ComparedPilotValues',actual.ComparedComplexValueCount, ...
        'CompactCaptureBytes',small.bytes,'DenseEstimateBytes',large.bytes, ...
        'ErrorEnergy',actual.ErrorEnergy,'ReferenceEnergy',actual.ReferenceEnergy, ...
        'ExactScoreAndTableMatch',true,'Scope',"algebra_storage_not_PHY_or_peak_process_RSS");
    fprintf('COMPACT_PILOT_SCORING_CASE=%d grid_values=%d pilot_values=%d compact_bytes=%d dense_bytes=%d\n', ...
        c,prod(shape),numel(sampled),small.bytes,large.bytes);
    clear rows reference estimate sampled h t snapshot before legacy compact full;
end
sixgr.util.csvWriteTable(fullfile(root,'equivalence.csv'),struct2table(vertcat(evidence{:})),'PreserveSchema',true);
fprintf('COMPACT_PILOT_CHANNEL_SCORING_PASS folder=%s physical_qualification=0\n',root);
ok=true;
end

function localNegativeChecks(snapshot,reference,indices)
bad=snapshot; bad.PilotChannelValues(1)=NaN;
reject(@()sixgr.phy.srs.pilotChannelNMSE(bad,reference,indices), ...
    'sixgr:srs:IncompletePilotChannelReference');
bad=snapshot; bad.PilotIndices=flipud(indices);
reject(@()sixgr.phy.srs.pilotChannelNMSE(bad,reference,indices), ...
    'sixgr:srs:ChannelSnapshotMismatch');
bad=snapshot; bad.PilotChannelValues=bad.PilotChannelValues(1:end-1,:);
reject(@()sixgr.phy.srs.pilotChannelNMSE(bad,reference,indices), ...
    'sixgr:srs:ChannelSnapshotMismatch');
bad=snapshot; bad.GridShape(3)=bad.GridShape(3)+1;
reject(@()sixgr.phy.srs.pilotChannelNMSE(bad,reference,indices), ...
    'sixgr:srs:ChannelSnapshotMismatch');
bad=snapshot; bad.PilotIndices=[indices;indices(1)];
bad.PilotChannelValues=[bad.PilotChannelValues;bad.PilotChannelValues(1,:)];
reject(@()sixgr.phy.srs.pilotChannelNMSE(bad,reference,bad.PilotIndices), ...
    'sixgr:srs:DuplicatePilotReference');
bad=reference; bad(:)=0;
reject(@()sixgr.phy.srs.pilotChannelNMSE(snapshot,bad,indices), ...
    'sixgr:srs:InvalidPilotReferenceEnergy');
end

function reject(action,id)
try, action(); catch err, assert(string(err.identifier)==id,'%s',err.message); return; end
error('test:MissingExpectedFailure','Expected %s.',id);
end
