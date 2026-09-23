function ok=testKPICRCObservationAuthority()
% Declared arithmetic fixtures, not RF performance or decoder qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
for variant=1:5
    raw=struct();
    for direction=["DL","UL"]
        n=6;
        T=table(repmat(direction,n,1),(1:n).',ones(n,1), ...
            [1;0;NaN;Inf;-1;2],zeros(n,1),1000*ones(n,1), ...
            1000*ones(n,1),1000*ones(n,1),ones(n,1), ...
            direction+"_crc_"+string((1:n).'), ...
            'VariableNames',{'Direction','Slot','Goodput_Mbps','CRCPass', ...
            'BitErrors','BitsCompared','TBSize_bits','GoodBits', ...
            'AirInterfaceTTI_ms','TransportBlockId'});
        expected=[1;0;NaN;NaN;NaN;NaN];
        if variant==2
            T.CRCPass=["true";"failed";"not_decoded";"NaN";"";"2"];
        elseif variant==3
            T.TBCrcPass=ones(n,1); % Alias cannot rescue missing authoritative CRC.
        elseif variant==4
            T.TBCrcPass=T.CRCPass; T=removevars(T,'CRCPass');
        elseif variant==5
            T.CRCPass(:)=NaN; expected(:)=NaN;
        end
        raw.(direction)=T;
    end
    out=sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw,'StrictMode',true, ...
        'MeasurementWindowSec',.006,'EffectiveBandwidthHz',5e6);
    for direction=["DL","UL"]
        trace=out.("HARQDeliveryTrace"+direction);
        assert(isequaln(double(trace.TBCrcPass),expected), ...
            'test:UnknownCRCCountedAsPass','Canonical ledger changed unknown CRC into success/failure.');
        unknown=isnan(expected);
        assert(all(~trace.DeliveredThisAttempt(unknown)) && ...
            all(isnan(trace.CountedGoodputBits(unknown))));
        R=out.ReconstructionSummary;
        b=R(R.KPIName==direction+"_BLER",:);
        known=nnz(~unknown); failed=nnz(expected==0);
        want=NaN; if known>0, want=failed/known; end
        assert(isequaln(b.ReconstructionValue,want) && ...
            b.NumeratorValue==failed && b.DenominatorValue==known && ~b.StrictOk);
        g=R(R.KPIName==direction+"_TB_Delivery_Goodput_Mbps",:);
        assert(isnan(g.ReconstructionValue) && ~g.StrictOk);
        c=out.("RowContributions"+direction);
        assert(isequaln(double(c.TBCrcPass),expected) && all(isnan(c.GoodputBitsContribution(unknown))));
    end
    assert(~out.SummaryAliases.StrictOk && ~out.StrictOk);
    fprintf('KPI_CRC_OBSERVATION_AUTHORITY_PASS variant=%d\n',variant);
end
ok=true;
end
