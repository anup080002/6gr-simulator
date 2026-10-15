function ok=testRAReceiverRFObservation()
% Real RF processing with authored routing identities. This does not claim
% PRACH detection, decoded RAR, or end-to-end initial access qualification.
setup6GRSimToolkit('Verbose',false);
cfg=struct(); cfg.rf.rx.cfo_Hz=400;
cfg.rf.rx.iqImbalance=struct('enable',true,'gainImbalance_dB',.5,'phaseImbalance_deg',1);
cfg.rf.adc.enable=true; cfg.rf.adcBits=12; cfg.rf.adc.fullScale=1;
cfg.rf.frontend.dac=struct('enabled',true,'profile_id','ra_rf_binding_test', ...
    'version','1','bits',12,'full_scale',1,'convention','signed_midrise', ...
    'dither_enabled',false,'dither_rms',0,'aperture_jitter_seconds',0);
fs=122.88e6; first=3*61440+144; count=64;
ra=struct('RunId',"routing_fixture",'UEId',17,'AttemptId',2);
for direction=["DL","UL"]
    txID="gnb_1"; rxID="ue_1_rx"; stages=["Msg2","Msg4"];
    if direction=="UL", txID="ue_1"; rxID="gnb_1_rx"; stages=["Msg1","Msg3","RRCSetupComplete"]; end
    tx=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction,fs,2,first,1,false);
    rx=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx',direction,fs,2,first,1,false);
    x=complex(.2*ones(count,2),.1*ones(count,2));
    a=tx.apply(sixgr.phy.waveform.WaveformChunk(x,first),1);
    b=rx.apply(sixgr.phy.waveform.WaveformChunk(a.Waveform,first),1);
    e=struct('StartSample',first,'EndSampleExclusive',first+count, ...
        'TX',struct('ID',txID,'Replay',a.Replay), ...
        'RX',struct('ID',rxID,'Replay',b.Replay));
    segments={struct('Execution',e)};
    planes=[localPlane(a.Waveform,txID+":tx",first,fs,segments), ...
        localPlane(a.Waveform,rxID+":pre_rf",first,fs,segments), ...
        localPlane(b.Waveform,rxID+":post_rf",first,fs,segments)];
    for stage=stages
        item=struct('ID',"observation_"+stage,'Kind',"RA",'UE',1,'Planes',planes, ...
            'Context',struct('Prepared',struct('StageName',stage,'Direction',direction,'AbsoluteSlot',3)));
        [T,metadata]=sixgr.truth.buildRAReceiverRFObservation(item,ra,1,40,first+count);
        assert(T.UEId==17 && T.RuntimeUEIndex==1 && T.AttemptId==2);
        assert(T.TransmitterID==txID && T.ReceiverID==rxID && T.Direction==direction);
        assert(T.AbsoluteSlot0==3 && T.RuntimeSlot==4 && T.ConfiguredSNR_dB==40);
        assert(T.IQImbalanceApplied==1 && T.CFOApplied==1 && T.ADCBits==12 && T.DACBits==12);
        assert(T.DACFullScale==a.Replay.DACFullScale && T.DACClippingRatio==a.Replay.DACClippingRatio);
        assert(T.ObservationEndSampleExclusive==first+count && T.ResultAvailableAtSample==first+count);
        assert(~any(ismember({'CRCPass','Status','RACompleted'},T.Properties.VariableNames)));
        assert(~any(ismember({'UEId','StageName','AbsoluteSlot0','ObservationPresent'},metadata.Properties.VariableNames)));
        assert(contains(T.EvidenceScope,'not_decode_or_attachment_result'));
        bad=rmfield(item,'ID');
        localReject(@()sixgr.truth.buildRAReceiverRFObservation(bad,ra,1,40,first+count), ...
            'sixgr:truth:MissingRARFObservationIdentity');
        bad=item; bad.ID="";
        localReject(@()sixgr.truth.buildRAReceiverRFObservation(bad,ra,1,40,first+count), ...
            'sixgr:truth:MissingRARFObservationIdentity');
        bad=item; bad.UE=2;
        localReject(@()sixgr.truth.buildRAReceiverRFObservation(bad,ra,1,40,first+count), ...
            'sixgr:truth:RARFEndpointMismatch');
        localReject(@()sixgr.truth.buildRAReceiverRFObservation(item,ra,1,40,first+count-1), ...
            'sixgr:truth:RARFPublicationBeforeReception');
    end
    if direction=="DL"
        for kind=["RAR","Contention"]
            item.Kind=kind; item.Context=struct('AbsoluteSlot',3);
            T=sixgr.truth.buildRAReceiverRFObservation(item,ra,1,-10,first+count);
            assert(T.StageName==kind+"Monitoring" && T.ConfiguredSNR_dB==-10);
        end
        item.Kind="RARExpiry";
        localReject(@()sixgr.truth.buildRAReceiverRFObservation(item,ra,1,40,first+count), ...
            'sixgr:truth:NonphysicalRARFEvent');
    end
end
ok=true; fprintf('RA_RECEIVER_RF_OBSERVATION_PASS: 5 stages, 2 monitoring kinds; RF metadata only.\n');
end
function plane=localPlane(wave,id,first,fs,segments)
o=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(wave,1),fs,size(wave,2));
o.append(sixgr.phy.waveform.WaveformChunk(wave,first),fs);
plane=struct('ReceiverID',id,'Observation',o,'Segments',{segments});
end
function localReject(fn,id)
try, fn(); catch e, assert(strcmp(e.identifier,id),e.message); return; end
error('test:MissingError','Expected %s.',id);
end
