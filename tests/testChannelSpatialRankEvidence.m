function ok=testChannelSpatialRankEvidence()
% Declared mathematical examples, not physical channel/RI qualification.
H=complex(zeros(1,2,2));
H(:,:,1)=[1 1]; H(:,:,2)=[1 -1];
e=sixgr.mimo.channelSpatialRankEvidence(H);
assert(e.AggregateSpatialSpanRank==2 && ...
    e.SimultaneousRankDimensionLimit==1 && all(e.NumericalRankPerSnapshot==1));
assert(e.AggregateDomain=="transmit_snapshot_covariance" && ~e.NoiseQualifiedRank && ~e.DecodedRI);
% Two UE branches can observe a four-dimensional span over changing REs,
% but each individual 4-TX/2-RX matrix has at most two simultaneous modes.
H=zeros(2,4,2); H(:,:,1)=[eye(2) zeros(2)]; H(:,:,2)=[zeros(2) eye(2)];
e=sixgr.mimo.channelSpatialRankEvidence(H);
assert(e.AggregateSpatialSpanRank==4 && e.SimultaneousRankDimensionLimit==2 && ...
    all(e.NumericalRankPerSnapshot==2));
% Do not turn a varying physical rank into an invented constant rank.
H(:,:,2)=[1 0 0 0;2 0 0 0];
e=sixgr.mimo.channelSpatialRankEvidence(H);
assert(isequal(e.NumericalRankPerSnapshot,[2;1]) && ...
    e.MinimumSnapshotNumericalRank==1 && e.MaximumSnapshotNumericalRank==2);
for matrix={zeros(2,4),[.8 0 .6 0;0 .6 0 .8],[1 1], [1;1]}
    A=matrix{1}; e=sixgr.mimo.channelSpatialRankEvidence(A);
    assert(e.MaximumSnapshotNumericalRank==rank(A) && ...
        e.NumReceiveBranches==size(A,1) && e.NumTransmitPorts==size(A,2) && ...
        e.AggregateDomain=="single_channel_matrix");
end
for bad={NaN,Inf,[],zeros(2,2,2,2)}
    caught=false;
    try, sixgr.mimo.channelSpatialRankEvidence(bad{1});
    catch ex, caught=strcmp(ex.identifier,'sixgr:mimo:InvalidSpatialRankInput'); end
    assert(caught,'Invalid estimates must not manufacture a rank.');
end
fprintf('CHANNEL_SPATIAL_RANK_EVIDENCE_PASS covariance_span_not_simultaneous_rank=1 numerical_not_decoded_RI=1\n');
ok=true;
end
