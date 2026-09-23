function ok=testBERPairedEvidence()
% Declared measurement fixtures, not RF performance qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
errorCases={[0;10;NaN],[NaN;NaN;NaN],[0;10;5],[0;10;2],[0;10;.5],[0;10;0],[0;10;30]};
bitCases={[100;100;100],[100;100;100],[100;100;NaN],[100;100;1],[100;100;100],[100;100;0],[100;100;300]};
expected=[.05 NaN .05 .05 .05 .05 .08];
for k=1:numel(errorCases)
    for bandwidth=[5e6 400e6]
        root=tempname; mkdir(root); cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
        raw=struct(); trials=struct();
        for direction=["DL","UL"]
            n=3;
            T=table(repmat(direction,n,1),(1:n).',ones(n,1),true(n,1), ...
                errorCases{k},bitCases{k},1000*ones(n,1),1000*ones(n,1), ...
                1000*ones(n,1),ones(n,1),repmat(20,n,1),repmat("OK",n,1), ...
                true(n,1),false(n,1),false(n,1),direction+"_ber_"+string((1:n).'), ...
                'VariableNames',{'Direction','Slot','Goodput_Mbps','CRCPass', ...
                'BitErrors','BitsCompared','TBSize_bits','GoodBits','OfferedBits', ...
                'AirInterfaceTTI_ms','PostEqSINR_dB','PostEqSINRValueStatus', ...
                'FinalizedFlag','IsWarmupFrame','FallbackFlag','TransportBlockId'});
            raw.(direction)=T; trials.(lower(direction))=T;
        end
        out=sixgr.analytics.generateMeasuredSINRCurves(root,'paired_ber', ...
            'TrialData',trials,'ScenarioConfig',struct('global_radio_scope', ...
            struct('channel_bandwidth_hz',bandwidth)), ...
            'WriteKPISummary',true,'UpdateAnchorKPIs',false);
        S=out.Tables.Summary; K=out.Tables.KPISummary;
        assert(all(abs(S.BER_overall-expected(k))<1e-12 | ...
            (isnan(S.BER_overall)&isnan(expected(k)))), ...
            'test:UnpairedBERPopulation','BER numerator and denominator must use the same observed rows.');
        assert(isequaln(S.BER_overall,K.BER_overall));
        persisted=readtable(out.Paths.Summary,'VariableNamingRule','preserve');
        assert(isequaln(persisted.BER_overall,S.BER_overall));
        for direction=["DL","UL"]
            B=out.Tables.(direction+"BlerCurve");
            assert(isequaln(B.BER,expected(k)));
        end
        known=2; if k==2, known=0; elseif k==7, known=3; end
        assert(all(S.BERObservedTrialCount==known & S.BERUnavailableTrialCount==3-known));
        if known<3
            assert(~any(K.StrictOk) && ~out.Tables.BlerBerReconciliation.BlerBerReconciliationOk);
        end
        canonical=sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw,'MeasurementWindowSec',.003);
        R=canonical.ReconstructionSummary;
        for direction=["DL","UL"]
            row=R(string(R.KPIName)==direction+"_BER",:);
            assert(height(row)==1);
            assert(isequaln(row.ReconstructionValue,expected(k)));
            expectedBits=200; expectedErrors=10;
            if k==2, expectedBits=0; expectedErrors=0;
            elseif k==7, expectedBits=500; expectedErrors=40; end
            assert(row.NumeratorValue==expectedErrors && row.DenominatorValue==expectedBits);
            if known<3, assert(~row.StrictOk); end
        end
        fprintf('BER_PAIRED_EVIDENCE_PASS case=%d bandwidth=%g known=%d\n',k,bandwidth,known);
        clear cleanup;
    end
end
ok=true;
end
