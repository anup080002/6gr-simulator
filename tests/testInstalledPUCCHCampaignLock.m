function ok=testInstalledPUCCHCampaignLock()
% Exercise cleanup/reentry without spending or replacing a PHY realization.
p='simulator/configs/validation/h4_100_installed_pucch_development.yaml';
output=fullfile(pwd,'results','diagnostics','installed_pucch_lock');
tag=string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
root=fullfile(output,tag); mkdir(fullfile(root,'meta'));
[message,warningID]=lastwarn;
restore=onCleanup(@()lastwarn(message,warningID)); %#ok<NASGU>
for attempt=1:2
    lastwarn('');
    reject(p,output,tag,'Incomplete campaign initialization');
    assert(strlength(string(lastwarn))==0,'test:CampaignCleanupWarning');
end
% A concurrent writer must be rejected and must not affect the first lock.
file=java.io.RandomAccessFile(char(fullfile(root,'writer.lock')),'rw');
cleanup=onCleanup(@()file.close()); %#ok<NASGU>
lock=file.getChannel().tryLock(); assert(~isempty(lock));
lastwarn('');
reject(p,output,tag,'writer lock');
assert(lock.isValid() && strlength(string(lastwarn))==0);
assert(~isfolder(fullfile(root,'episodes')),'test:PhysicalEpisodeExecutedUnderInvalidMetadata');
ok=true;
end
function reject(p,output,tag,message)
caught=false;
try, sixgr.link.runInstalledPUCCHReceiverCampaign(p,output,tag);
catch err
    assert(strcmp(err.identifier,'sixgr:pucch:InstalledCampaignIntegrity') && ...
        contains(err.message,message),err.getReport());
    caught=true;
end
assert(caught,'test:InvalidCampaignLockAccepted');
end
