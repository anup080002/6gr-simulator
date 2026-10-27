function [dl,ul]=resolveSIB1FrequencyInfo(cfg,band,scs,nrb,fc)
% Original configured carrier/SSB geometry, or exact decoded wire fields.
% TS 38.331 V18.8.0 FrequencyInfoDL/UL-SIB; TS 38.211 4.4.4.2.
received=sixgr.util.structGet(cfg,'rrc.sib1.decoded_frequency_info',struct());
if ~isempty(fieldnames(received))
    assert(all(isfield(received,{'DL','UL'})), ...
        'sixgr:rrc:asn1:MissingFrequencyAuthority','Retain both original decoded frequency IEs.');
    dl=received.DL;ul=received.UL;
    return;
end
start=double(sixgr.util.structGet(cfg,'phy.carrier.NStartGrid',0));
validateattributes(start,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
carrier=struct('offsetToCarrier',start,'subcarrierSpacing',"kHz"+string(scs), ...
    'carrierBandwidth',nrb);
offset=sixgr.util.structGet(cfg,'rrc.sib1.offset_to_point_a',[]);
ncrb=sixgr.util.structGet(cfg,'phy.ssb.NCRBSSB',[]);
if isempty(ncrb)
    % Same centered-grid relationship used by SSBTimingResolver, expressed
    % in the FR1 15-kHz reference RBs. No RF execution or candidate choice.
    ssbscs=double(sixgr.util.structGet(cfg,'phy.ssb.scs_kHz',scs));
    assert(any(ssbscs==[15 30]),'sixgr:rrc:asn1:UnsupportedFrequency', ...
        'This SIB1 profile supports only FR1 SSB frequency geometry.');
    units=((start+nrb/2)*12*scs-120*ssbscs)/15;
    assert(units>=0 && abs(units-round(units))<1e-9, ...
        'sixgr:rrc:asn1:InvalidSSBPointA','The configured centered SSB must fit an integer Point-A reference subcarrier.');
    ncrb=floor(round(units)/12);
end
if isempty(offset),offset=ncrb;end
validateattributes(offset,{'numeric'},{'scalar','real','finite','integer','>=',0,'<=',2199});
assert(offset==ncrb,'sixgr:rrc:asn1:SSBPointAMismatch', ...
    'SIB1 offsetToPointA must retain the original emitted SSB NCRBSSB.');
dl=struct('frequencyBandList',struct('freqBandIndicatorNR',band), ...
    'offsetToPointA',offset,'scs_SpecificCarrierList',carrier);
ul=struct('scs_SpecificCarrierList',carrier);
duplex=string(sixgr.util.structGet(cfg,'phy.duplex.mode',"TDD"));
if duplex=="FDD"
    ulfc=double(sixgr.util.structGet(cfg,'phy.duplex.fdd.ulCenterFrequencyHz',fc));
    point=ulfc-(start+nrb/2)*12*scs*1e3;
    ul.frequencyBandList=struct('freqBandIndicatorNR',band);
    ul.absoluteFrequencyPointA=localARFCN(point);
else
    assert(duplex=="TDD",'sixgr:rrc:asn1:UnsupportedFrequency','Require explicit paired or unpaired duplex context.');
    % Cond FDD-OrSUL: both fields are absent for the unpaired UL.
end
end

function value=localARFCN(hz)
if hz<3e9,step=5e3;base=0;offset=0;
elseif hz<24.25008e9,step=15e3;base=3e9;offset=600000;
else,step=60e3;base=24.25008e9;offset=2016667;end
raw=(hz-base)/step+offset;value=round(raw);
assert(isfinite(raw)&&value>=0&&value<=3279165&&abs(raw-value)<1e-7, ...
    'sixgr:rrc:asn1:UnsupportedFrequency','Original UL Point A must lie on the NR-ARFCN raster; never round its physical frequency.');
end
