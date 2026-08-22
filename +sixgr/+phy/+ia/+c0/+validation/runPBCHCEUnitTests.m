function gates=runPBCHCEUnitTests(bundle,cfg)
%RUNPBCHCEUNITTESTS Execute CE-UT1 through CE-UT6 on production functions.
prefix=sum(double(bundle.OFDMInfo.SymbolLengths(1:bundle.CandidateStartSymbol)));
rows=cell(6,1);

flat=repmat(bundle.Waveform,1,double(cfg.mimo.num_rx_antennas));
[r1,m1]=localRecover(flat,flat,bundle,cfg,0,prefix);
rows{1}=localRow("CE-UT1",r1.PBCHOk&&m1.Available&&m1.NMSELinear<1e-20, ...
    m1.NMSELinear,"flat_H_1_no_noise");

h=reshape([0.7+0.2j,-0.3+0.9j,1.1-0.4j,0.2-0.6j],1,[]);
constant=bundle.Waveform.*h;
[r2,m2]=localRecover(constant,constant,bundle,cfg,0,prefix);
rows{2}=localRow("CE-UT2",r2.PBCHOk&&m2.Available&&m2.NMSELinear<1e-20, ...
    m2.NMSELinear,"constant_complex_H_no_noise");

c=sixgr.phy.ia.c0.channel.applyFading(bundle.Waveform,bundle,cfg,9520);
truthTiming=double(c.TimingOffsetSamples)+prefix;
[r3,m3]=localRecover(c.Waveform,c.Waveform,bundle,cfg,0,truthTiming);
rows{3}=localRow("CE-UT3",r3.PBCHOk&&m3.Available&&m3.NMSEDB<-20, ...
    m3.NMSEDB,"tdl_c_no_noise_interpolation_floor_db");

snrs=[10 20 30]; nmse=nan(size(snrs)); available=true;
signalPower=sixgr.phy.ia.c0.channel.measureActiveREPower( ...
    c.Waveform,bundle,c.TimingOffsetSamples);
for k=1:numel(snrs)
    [rx,~]=sixgr.phy.ia.c0.channel.addNoiseForTargetSNR( ...
        c.Waveform,bundle,signalPower,snrs(k),9530+k);
    [~,mk]=localRecover(rx,c.Waveform,bundle,cfg,0,truthTiming);
    available=available&&mk.Available; nmse(k)=mk.NMSELinear;
end
referenceIndex=find(snrs==double(cfg.statistics.high_snr_sanity_db),1);
if isempty(referenceIndex)
    error("sixgr:phy:ia:c0:validation:MissingCESanitySNR", ...
        "CE-UT4 SNR ladder must contain statistics.high_snr_sanity_db.");
end
rows{4}=localRow("CE-UT4",available&&nmse(end)<nmse(1)&&nmse(end)<0.02, ...
    nmse(referenceIndex),"tdl_c_awgn_configured_high_snr_linear_nmse");

dimensionPass=isequal(m3.HhatSize,[576 double(cfg.mimo.num_rx_antennas)])&& ...
    isequal(m3.HtrueEffSize,[576 double(cfg.mimo.num_rx_antennas)]);
rows{5}=localRow("CE-UT5",dimensionPass,m3.NMSELinear, ...
    "configured_tx_precoder_effective_4rx_dimensions");

trial=sixgr.phy.ia.c0.campaigns.runC0StudyTrial( ...
    bundle,cfg,double(cfg.statistics.high_snr_sanity_db),7,0);
rows{6}=localRow("CE-UT6",trial.ChannelEstimateMSEAvailable&& ...
    trial.ChannelEstimateNMSEDB<-15,trial.ChannelEstimateNMSEDB, ...
    "practical_timing_cfo_receiver_referenced_nmse_db");
gates=vertcat(rows{:});
end

function [receiver,meta]=localRecover(rx,clean,bundle,cfg,cfoHz,timing)
receiver=sixgr.phy.ia.c0.receiver.runCompleteSSBReceiver( ...
    rx,bundle,cfg,0,"TrueCFOHz",cfoHz,"TrueTimingSamples",timing);
[~,meta]=sixgr.phy.ia.c0.receiver.channelEstimateMSE(receiver,clean,bundle,cfg);
end

function row=localRow(id,pass,value,definition)
row=table(string(id),logical(pass),double(value),string(definition), ...
    'VariableNames',{'UnitTest','Pass','MeasuredValue','Definition'});
end
