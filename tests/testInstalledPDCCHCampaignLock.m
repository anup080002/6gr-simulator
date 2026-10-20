function ok=testInstalledPDCCHCampaignLock()
% Failed initialization and concurrent writers must not spend a realization.
p='simulator/configs/validation/h4_100_installed_pdcch_campaign_development.yaml';
output=fullfile(pwd,'results','diagnostics','installed_pdcch_lock');
tag=string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
root=fullfile(output,tag); mkdir(fullfile(root,'meta'));
[message,warningID]=lastwarn;
restore=onCleanup(@()lastwarn(message,warningID)); %#ok<NASGU>
for attempt=1:2
    lastwarn(''); reject(p,output,tag,'Incomplete campaign initialization');
    assert(strlength(string(lastwarn))==0,'test:CampaignCleanupWarning');
end
file=java.io.RandomAccessFile(char(fullfile(root,'writer.lock')),'rw');
cleanup=onCleanup(@()file.close()); %#ok<NASGU>
lock=file.getChannel().tryLock(); assert(~isempty(lock));
lastwarn(''); reject(p,output,tag,'writer lock');
assert(lock.isValid()&&strlength(string(lastwarn))==0);
assert(~isfolder(fullfile(root,'episodes')));
ok=true;
end
function reject(p,output,tag,message)
caught=false;
try, sixgr.link.runInstalledPDCCHReceiverCampaign(p,output,tag);
catch err
    assert(strcmp(err.identifier,'sixgr:pdcch:InstalledCampaignIntegrity')&& ...
        contains(err.message,message),err.getReport()); caught=true;
end
assert(caught,'test:InvalidCampaignLockAccepted');
end
