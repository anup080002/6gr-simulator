classdef TestTopology < matlab.unittest.TestCase
    methods(Test)
        function sameStateDrivesRangeLatencyDoppler(tc)
            s=sixgr.ntn.resilientsync.buildScenario( ...
                "configs/ntn_resilient_sync/quick.yaml");
            t=sixgr.ntn.resilientsync.topology.buildTopology(s);
            c=double(s.geometry.speed_of_light_m_s);
            fc=double(s.ntn_topology.link_budget.carrier_frequency_hz);
            tc.verifyEqual(t.StateTable.OneWayLatency_s, ...
                t.StateTable.SlantRange_m/c,'RelTol',1e-13);
            tc.verifyEqual(t.StateTable.DopplerShiftHz, ...
                -t.StateTable.RangeRate_m_s*fc/c,'RelTol',1e-13);
            tc.verifyTrue(any(t.StateTable.Access));
            tc.verifyTrue(any(t.StateTable.GatewayAccess));
            tc.verifyEqual(sort(unique(t.AccessIntervals.EndpointId)), ...
                sort([string(s.ntn_topology.gateway.id); ...
                string(s.ntn_topology.service_ue.id)]));
            tc.verifyGreaterThan(height(t.AccessIntervals),1);
            [~,closest]=min(abs(t.StateTable.Time_s- ...
                double(s.ntn_topology.closest_approach_time_s)));
            tc.verifyLessThan(abs(t.StateTable.RangeRate_m_s(closest)),1e-6);
        end
        function physicalArrayLinkBudgetCloses(tc)
            s=sixgr.ntn.resilientsync.buildScenario( ...
                "configs/ntn_resilient_sync/quick.yaml");
            [cfg,~]=sixgr.lls.loadConfig( ...
                string(s.physical_layer.topology_proof_pdsch_config));
            t=sixgr.ntn.resilientsync.topology.buildTopology(s);
            b=sixgr.ntn.resilientsync.topology.computeLinkBudget(s,cfg,t);
            tc.verifyTrue(all(isfinite(b.DownlinkOccupiedRE_EsN0_dB)));
            tc.verifyGreaterThan(max(b.DownlinkOccupiedRE_EsN0_dB), ...
                double(cfg.simulation.snrDb(1)));
            tc.verifyEqual(unique(b.AntennaPatternSource), ...
                "phased.NRRectangularPanelArray_with_phased.NRAntennaElement");
        end
    end
end
