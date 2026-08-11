function out = bistaticGeometry(txPosition,rxPosition,targetPosition,targetVelocity,carrierFrequencyHz,mode)
%BISTATICGEOMETRY Exact geometry delay/Doppler reference for ISAC trials.

arguments
    txPosition (3,1) double
    rxPosition (3,1) double
    targetPosition (3,1) double
    targetVelocity (3,1) double
    carrierFrequencyHz (1,1) double {mustBePositive}
    mode (1,1) string
end
c = physconst("LightSpeed");
lambda = c/carrierFrequencyHz;
txLeg = targetPosition-txPosition;
rxLeg = targetPosition-rxPosition;
dTx = norm(txLeg);
dRx = norm(rxLeg);
if dTx <= 0 || dRx <= 0
    error("sixgr:isac:DegenerateGeometry", ...
        "Sensing target must not coincide with transmitter or receiver.");
end
uTx = txLeg/dTx;
uRx = rxLeg/dRx;
pathLength = dTx+dRx;
directPath = norm(rxPosition-txPosition);
if lower(mode) == "trp_monostatic"
    directPath = 0;
end
dopplerHz = dot(targetVelocity,uTx+uRx)/lambda;
bistaticAngleDeg = acosd(max(-1,min(1,dot(-uTx,uRx))));
out = struct( ...
    "TxLegM",dTx,"RxLegM",dRx,"TargetPathM",pathLength, ...
    "DirectPathM",directPath,"TotalDelayS",pathLength/c, ...
    "ExcessDelayS",(pathLength-directPath)/c, ...
    "BistaticAngleDeg",bistaticAngleDeg,"DopplerHz",dopplerHz, ...
    "WavelengthM",lambda,"TxUnitVector",uTx,"RxUnitVector",uRx);
end
