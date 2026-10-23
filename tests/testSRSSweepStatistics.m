function ok=testSRSSweepStatistics()
% Same primary calculation for runtime populations and actual singleton
% receiver outputs; no arithmetic dB mean or one-observation confidence band.
T=table([-20;-10;60],[true;true;false], ...
    'VariableNames',{'NMSE_dB','ChannelNMSEReferenceAvailable'});
initial=struct('SNR_dB',12,'SRS_NMSE_dB',123,'SRS_TrialCount',123, ...
    'SRS_NMSE_CI_Low',123,'SRS_NMSE_CI_High',123);
row=sixgr.truth.applySRSSweepStatistics(initial,T);
assert(abs(row.SRS_NMSE_dB-10*log10(.055))<1e-12&&row.SRS_TrialCount==2);
assert(isnan(row.SRS_NMSE_CI_Low)&&isnan(row.SRS_NMSE_CI_High)&&row.SNR_dB==12);
old=removevars(T,'ChannelNMSEReferenceAvailable');
row=sixgr.truth.applySRSSweepStatistics(initial,old);
assert(isnan(row.SRS_NMSE_dB)&&row.SRS_TrialCount==0);
T.NMSE_dB=[-Inf;-10;60];
row=sixgr.truth.applySRSSweepStatistics(initial,T);
assert(abs(row.SRS_NMSE_dB-10*log10(.05))<1e-12&&row.SRS_TrialCount==2);
actual=struct('NMSE_dB',-Inf,'ChannelNMSEReferenceAvailable',true);
row=sixgr.truth.applySRSSweepStatistics(initial,actual);
assert(row.SRS_NMSE_dB==-Inf&&row.SRS_TrialCount==1&&isnan(row.SRS_NMSE_CI_Low));
actual.ChannelNMSEReferenceAvailable=false;
row=sixgr.truth.applySRSSweepStatistics(initial,actual);
assert(isnan(row.SRS_NMSE_dB)&&row.SRS_TrialCount==0);
row=sixgr.truth.applySRSSweepStatistics(initial,table());
assert(isnan(row.SRS_NMSE_dB)&&row.SRS_TrialCount==0);
fprintf('SRS_SWEEP_STATISTICS_PASS reference_gated=1 linear_mean=1 zero_error_retained=1 invented_CI=0\n');
ok=true;
end
