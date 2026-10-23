function ok=testLinkTrialDecodeCoverage()
% Declared evidence-contract cases only; no waveform or statistical claim.
setup6GRSimToolkit('Verbose',false);
count=0;
for direction=["DL","UL"]
    base=struct('Direction',direction,'Status',"PASS",'CRCPass',1, ...
        'FinalizedFlag',true,'PartialRowFlag',false,'Crash',false, ...
        'IsWarmupFrame',false,'DecodeAttempted',true,'DecodeUsable',true, ...
        'DLSCHDecodeAttempted',direction=="DL",'DLSCHDecodeAvailable',direction=="DL", ...
        'ULSCHDecodeAttempted',direction=="UL",'ULSCHDecodeAvailable',direction=="UL", ...
        'CRCApplicable',true,'TBSize_bits',1024);
    T=struct2table(base,'AsArray',true); before=T; beforeRNG=rng;
    assert(sixgr.util.linkTrialDecodeCoverage(T));
    assert(isequaln(T,before) && isequal(rng,beforeRNG));
    T.Status="FAIL"; T.CRCPass=0;
    assert(sixgr.util.linkTrialDecodeCoverage(T), ...
        'Real CRC failure must remain a counted decode, not be discarded.');
    count=count+2;
    absent=["FinalizedFlag","DecodeAttempted","DecodeUsable","CRCApplicable"];
    if direction=="DL", absent=[absent,"DLSCHDecodeAttempted","DLSCHDecodeAvailable"];
    else, absent=[absent,"ULSCHDecodeAttempted","ULSCHDecodeAvailable"]; end
    for field=absent
        T=before; T.(field)=false; assert(~sixgr.util.linkTrialDecodeCoverage(T));
        T=removevars(before,field); assert(~sixgr.util.linkTrialDecodeCoverage(T));
        T=before; T.(field)=NaN; assert(~sixgr.util.linkTrialDecodeCoverage(T));
        count=count+3;
    end
    for field=["PartialRowFlag","Crash","IsWarmupFrame"]
        T=before; T.(field)=true; assert(~sixgr.util.linkTrialDecodeCoverage(T));
        T=before; T.(field)=NaN; assert(~sixgr.util.linkTrialDecodeCoverage(T));
        T=removevars(before,field); assert(~sixgr.util.linkTrialDecodeCoverage(T));
        count=count+3;
    end
    for crc=[NaN,-1,2]
        T=before; T.CRCPass=crc; assert(~sixgr.util.linkTrialDecodeCoverage(T)); count=count+1;
    end
    T=before; T.Status="NA"; assert(~sixgr.util.linkTrialDecodeCoverage(T)); count=count+1;
    T=before; T.Direction=""; assert(~sixgr.util.linkTrialDecodeCoverage(T)); count=count+1;
    assert(isempty(sixgr.util.linkTrialDecodeCoverage(before([],:)))); count=count+1;
end
fprintf('LINK_TRIAL_DECODE_COVERAGE_PASS cases=%d physical_qualification=0\n',count);
ok=true;
end
