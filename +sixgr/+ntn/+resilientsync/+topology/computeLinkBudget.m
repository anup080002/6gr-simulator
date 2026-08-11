function budget = computeLinkBudget(scenario,llsCfg,topology)
%COMPUTELINKBUDGET Compute bidirectional C/N and occupied-RE Es/N0.
%
% Antenna gains are evaluated from the exact phased.NRRectangularPanelArray
% descriptors used by the waveform channel.  This prevents the link budget
% and the LLS antenna evidence from silently describing different arrays.

arguments
    scenario (1,1) struct
    llsCfg (1,1) struct
    topology (1,1) struct
end

if ~logical(llsCfg.antenna.enabled)
    error("sixgr:ntn:resilientsync:AntennaNotEnabled", ...
        "The topology proof requires antenna.enabled=true in its PHY YAML.");
end
state = sixgr.lls.resolveAntennaState(llsCfg);
if state.TxRole ~= string(scenario.ntn_topology.waveform_binding.satellite_array_role) || ...
        state.RxRole ~= string(scenario.ntn_topology.waveform_binding.service_ue_array_role)
    error("sixgr:ntn:resilientsync:AntennaBindingMismatch", ...
        "Topology antenna roles do not match the resolved PDSCH transmitter/receiver roles.");
end
satGain = localBoresightGain(state.Tx);
ueGain = localBoresightGain(state.Rx);

cfg = scenario.ntn_topology;
lb = cfg.link_budget;
sat = cfg.satellite;
ue = cfg.service_ue;
k = double(lb.boltzmann_dbw_k_hz);
bandwidth = double(lb.bandwidth_hz);
loss = double(lb.atmospheric_loss_db)+double(lb.scintillation_loss_db)+ ...
    double(lb.polarization_loss_db)+double(lb.shadow_margin_db)+ ...
    double(lb.additional_loss_db)+double(lb.implementation_margin_db);
range = topology.StateTable.SlantRange_m;
frequency = double(lb.carrier_frequency_hz);
fspl = 20*log10(4*pi*range*frequency/double(scenario.geometry.speed_of_light_m_s));

satEirp = double(sat.transmit_power_dbw)-double(sat.transmit_cable_loss_db)+satGain;
ueEirp = (double(ue.transmit_power_dbm)-30)-double(ue.transmit_cable_loss_db)+ueGain;
satGT = localGT(satGain,double(sat.receive_noise_figure_db), ...
    double(sat.receive_antenna_temperature_k),double(sat.receive_ambient_temperature_k));
ueGT = localGT(ueGain,double(ue.receive_noise_figure_db), ...
    double(ue.receive_antenna_temperature_k),double(ue.receive_ambient_temperature_k));
noiseBandwidthDbHz = 10*log10(bandwidth);
downlinkCNR = satEirp+ueGT-k-fspl-loss-noiseBandwidthDbHz;
uplinkCNR = ueEirp+satGT-k-fspl-loss-noiseBandwidthDbHz;

scsHz = double(llsCfg.carrier.subcarrierSpacingKHz)*1e3;
mu = log2(scsHz/15e3);
if abs(mu-round(mu)) > 1e-9
    error("sixgr:ntn:resilientsync:UnsupportedSCS", ...
        "Topology proof requires NR SCS=15*2^mu kHz.");
end
symbolsPerSecond = 14*1000*2^round(mu);
occupiedRERate = double(llsCfg.allocation.numberPRB)*12*symbolsPerSecond;
cnrToEsN0 = 10*log10(bandwidth/occupiedRERate);

n=height(topology.StateTable);
budget = table;
budget.Time_s = topology.StateTable.Time_s;
budget.Access = topology.StateTable.Access;
budget.ElevationDeg = topology.StateTable.ElevationDeg;
budget.SlantRange_m = range;
budget.FSPL_dB = fspl;
budget.TotalAdditionalLoss_dB = repmat(loss,n,1);
budget.SatelliteTxGain_dBi = repmat(satGain,n,1);
budget.ServiceUETxRxGain_dBi = repmat(ueGain,n,1);
budget.DownlinkEIRP_dBW = repmat(satEirp,n,1);
budget.UplinkEIRP_dBW = repmat(ueEirp,n,1);
budget.ServiceUE_G_over_T_dB_K = repmat(ueGT,n,1);
budget.Satellite_G_over_T_dB_K = repmat(satGT,n,1);
budget.DownlinkCNR_dB = downlinkCNR;
budget.UplinkCNR_dB = uplinkCNR;
budget.CNRToOccupiedRE_EsN0_dB = repmat(cnrToEsN0,n,1);
budget.DownlinkOccupiedRE_EsN0_dB = downlinkCNR+cnrToEsN0;
budget.UplinkOccupiedRE_EsN0_dB = uplinkCNR+cnrToEsN0;
budget.AntennaPatternSource = repmat(state.Tx.PatternSource,n,1);
budget.EvidenceClass = repmat("ANALYTICAL",n,1);
end

function gain = localBoresightGain(role)
array = sixgr.lls.buildAntennaArray(role);
cleanup=onCleanup(@() release(array)); %#ok<NASGU>
array.Taper=role.PortToElementMatrix(:,1);
az=double(role.SteeringAzElDeg(1));
el=double(role.SteeringAzElDeg(2));
gain=double(pattern(array,role.FrequencyHz,az,el, ...
    "Type","directivity","CoordinateSystem","rectangular"));
if ~isscalar(gain) || ~isfinite(gain)
    error("sixgr:ntn:resilientsync:InvalidAntennaGain", ...
        "Resolved boresight directivity is not a finite scalar.");
end
end

function value = localGT(gain,nf,antennaTemperature,ambientTemperature)
systemTemperature = ambientTemperature + ...
    (antennaTemperature-ambientTemperature)*10^(-0.1*nf);
value = gain-nf-10*log10(systemTemperature);
end
