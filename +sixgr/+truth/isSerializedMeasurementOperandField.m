function tf=isSerializedMeasurementOperandField(name)
% Numeric vectors retain producer-owned emptiness, not display categories.
name=string(name);
tf=endsWith(name,"JSON","IgnoreCase",true) || ...
    (~isempty(regexp(char(name),'(PerReceiveAntenna|PerAntenna|PerResource).*(_dBm|_dB|_W|_UnitOccupiedRE_Es)$','once')));
end
