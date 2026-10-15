function ok=testControlTransmitterEVMPairs()
% Fixed-clock paired TX measurements: no receiver/pilot-fit substitution.
setup6GRSimToolkit('Verbose',false);
root=tempname; mkdir(root);
for nrb=[25 273]
    scs=15; if nrb==273, scs=30; end
    c=nrCarrierConfig('NSizeGrid',nrb,'SubcarrierSpacing',scs);
    p=nrPRACHConfig('DuplexMode','TDD','ConfigurationIndex',157, ...
        'SubcarrierSpacing',30,'NPRACHSlot',29,'ActivePRACHSlot',1);
    grid=nrPRACHGrid(c,p); grid(nrPRACHIndices(c,p))=nrPRACH(c,p);
    [wave,info]=nrPRACHOFDMModulate(c,p,grid,'Windowing',0);
    assert(any(wave~=0),'This fixture must execute a real PRACH occasion.');
    physical=wave*[1 1i -1 -1i]/2;
    mapped=reshape(grid(:)*[1 1i -1 -1i]/2,size(grid,1),size(grid,2),4);
    tx=struct('Carrier',c,'PRACH',p);
    prepared=struct('SampleRate_Hz',info.SampleRate,'StartTime_s',0, ...
        'TransmitPortResourceGrid',mapped,'PhysicalWaveform',physical);
    for gain=[1 1.1 exp(.2i)]
        observation=localObservation(gain*physical,info.SampleRate);
        paired=sixgr.phy.prach.pairPRACHTransmitterSymbols(tx,prepared,observation);
        assert(numel(paired)==4);
        for port=1:4
            r=complex(paired(port).ReferenceReal,paired(port).ReferenceImag);
            m=complex(paired(port).MeasuredReal,paired(port).MeasuredImag);
            expected=mapped(:,:,port); expected=expected(expected~=0);
            assert(norm(r-expected)/norm(expected)<1e-10, ...
                'The fixed public-modulator transform must recover the actual native PRACH grid.');
            assert(abs(sqrt(sum(abs(m-r).^2)/sum(abs(r).^2))-abs(gain-1))<1e-10);
        end
        localExport(root,'prach_trials.csv','UL',paired,nnz(mapped));
    end
end
for yaml=["lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml", ...
        "h4_100_cdlc100_connected_impaired_40db_gate.yaml"]
    scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator/configs/scenarios',yaml));
    cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
    slot=cfg.phy.csirs.offset_slots+1;
    prepared=sixgr.link.prepareCSIRSTransmission(cfg,40,'RuntimeSlot',slot);
    prepared.TransmitStartSample=0;
    for gain=[1 1.1 exp(.2i)]
        paired=sixgr.phy.refsig.pairCSIRSTransmitterSymbols(prepared, ...
            localObservation(gain*prepared.TransmitSamples,prepared.SampleRateHz));
        for e=paired
            r=complex(e.ReferenceReal,e.ReferenceImag); m=complex(e.MeasuredReal,e.MeasuredImag);
            assert(abs(sqrt(sum(abs(m-r).^2)/sum(abs(r).^2))-abs(gain-1))<1e-10);
            assert(e.MeasurementDomain=="transmitter_resource_elements" && ~e.GainOrPhaseFitted);
        end
        localExport(root,'csi_rs_trials.csv','DL',paired,nnz(prepared.Tx.Grid));
    end
end
fprintf('CONTROL_TX_EVM_PAIRS_PASS retained_csv=%s\n',root);
ok=true;
end
function out=localObservation(wave,fs)
out=sixgr.phy.waveform.WaveformObservationBuffer(0,size(wave,1),fs,size(wave,2));
out.append(sixgr.phy.waveform.WaveformChunk(wave,0),fs);
end
function localExport(folder,file,direction,paired,count)
T=table(string(direction),1,1,1,1,40,string(jsonencode(paired)), ...
    'VariableNames',{'Direction','UEIndex','CellID','Slot','SweepPointIndex','ConfiguredSNR_dB','ControlEVMSamplesJSON'});
path=sixgr.report.exportControlEVMSamples(fullfile(folder,file),T);
saved=readtable(path,'TextType','string');
assert(height(saved)==count && all(saved.MeasurementDomain=="transmitter_resource_elements") && ...
    all(saved.SweepPointIndex==1) && all(saved.ConfiguredSNR_dB==40));
end
