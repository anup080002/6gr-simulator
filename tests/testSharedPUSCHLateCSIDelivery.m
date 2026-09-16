function ok=testSharedPUSCHLateCSIDelivery()
% Actual CSI-RS measurement, HARQ/CSI-coded PUSCH, later scheduler delivery.
root=fileparts(fileparts(mfilename('fullpath')));
logsRoot=fullfile(root,'logs','tdd_shared_pusch_late_csi');
if ~isfolder(logsRoot), mkdir(logsRoot); end
outputRoot=tempname(logsRoot);
ok=testSharedPUSCHChannelArtifacts('TDD',true,true,true,false,false,false,outputRoot);
end
