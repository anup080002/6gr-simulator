function ok=testLargeSharedChannelArchive()
% Actual shared channel execution crosses the production v2 storage boundary.
% No storage-threshold override and no new scenario/throughput claim.
[passed,root,row,verified]=testSharedIdentityAWGNRuntime(524289);
assert(passed && verified.Manifest.Contract=="actual_shared_channel_observation/v2");
count=sum(cellfun(@(e)e.ElementCount,verified.PathGainReadEvidence));
peak=max(cellfun(@(e)e.MaxBlockElements,verified.PathGainReadEvidence));
assert(count==524289*16 && count>8388608 && peak<=1048576 && ...
    all(cellfun(@(e)~e.FullArrayLoaded && e.AllFinite,verified.PathGainReadEvidence)));
assert(row.ChannelObservationReceiverEstimatorInput==false);
ok=true;
fprintf('LARGE_SHARED_CHANNEL_ARCHIVE_PASS elements=%d peak_read_elements=%d production_writer_v2=1 root=%s\n',count,peak,root);
end
