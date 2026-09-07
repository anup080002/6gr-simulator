function value=rarBackoffMilliseconds(index)
% Immutable TS 38.321 Table 7.2-1; absence of BI is separately 0 ms.
validateattributes(index,{'numeric'},{'real','scalar','finite','integer','>=',0,'<=',15});
values=[5 10 20 30 40 60 80 120 160 240 320 480 960 1920];
if index>=numel(values)
    error('sixgr:mac:ra:ReservedBackoffIndicator','Received BI index %d is reserved; do not invent its backoff.',index);
end
value=values(index+1);
end
