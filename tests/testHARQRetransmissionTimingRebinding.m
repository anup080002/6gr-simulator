function ok = testHARQRetransmissionTimingRebinding()
%TESTHARQRETRANSMISSIONTIMINGREBINDING Guard TDD K1 replay semantics.

setup6GRSimToolkit("Verbose", false);
repoRoot = pwd;
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(repoRoot, ...
    "simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_full.yaml"));
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scenario, tmp);

controlSymbols = reshape(double(sixgr.util.structGet( ...
    cfg, "phy.pdcch.symbolAllocation", [])), 1, []);
dataSymbols = reshape(double(sixgr.util.structGet( ...
    cfg, "phy.pdsch.symbolAllocation", [])), 1, []);

found = false;
for originalSlot = 0:38
    original = localProbe(originalSlot, controlSymbols, dataSymbols);
    originalDecision = sixgr.phy.frame.TimingRelationEngine. ...
        resolveProductionGrant(cfg, original);
    if ~logical(originalDecision.Valid)
        continue;
    end

    % A pending process can be replayed several slots later.  The failed
    % production run reproduced the defect five slots after its original
    % attempt, across the next D,D,D,F,U TDD period.
    for replayDelta = 1:10
        if originalSlot + replayDelta <= ...
                double(originalDecision.FeedbackAbsoluteSlot)
            % A retransmission cannot precede the ACK/NACK occasion that
            % made the HARQ process eligible for replay.
            continue;
        end
        stale = localProbe(originalSlot + replayDelta, controlSymbols, dataSymbols);
        stale.K0 = double(originalDecision.K0);
        stale.K1 = double(originalDecision.K1);
        stale.HARQ = struct("HarqID", 0, "NDI", 0, "RV", 2, ...
            "IsRetransmission", true);
        stale.GrantReason = "harq_retx";
        stale.TimingDecision = originalDecision;
        stale.ScheduledAbsoluteSlot = double(originalDecision.DataAbsoluteSlot);
        stale.HARQFeedbackAbsoluteSlot = ...
            double(originalDecision.FeedbackAbsoluteSlot);

        staleDecision = sixgr.phy.frame.TimingRelationEngine. ...
            resolveProductionGrant(cfg, stale);
        rebound = sixgr.l2.mac.rebindHARQRetransmissionTiming(stale);
        reboundDecision = sixgr.phy.frame.TimingRelationEngine. ...
            resolveProductionGrant(cfg, rebound);
        if ~logical(staleDecision.Valid) && ...
                sixgr.truth.isDeferrableCoupledHARQACKTimingDecision(staleDecision) && ...
                logical(reboundDecision.Valid)
            found = true;
            assert(isnan(double(rebound.K0)) && isnan(double(rebound.K1)) && ...
                isnan(double(rebound.K2)), ...
                "Retransmission timing rebinding must remove stale explicit K values.");
            assert(double(reboundDecision.ControlAbsoluteSlot) == ...
                originalSlot + replayDelta, ...
                "The rebound decision must use the new control occasion.");
            assert(double(reboundDecision.FeedbackAbsoluteSlot) ~= ...
                double(originalDecision.FeedbackAbsoluteSlot), ...
                "The rebound retransmission must not reuse the previous feedback occasion.");
            break;
        end
    end
    if found
        break;
    end
end

assert(found, ...
    "The target TDD catalog must expose an adjacent-slot stale-K1 regression point.");

newData = localProbe(0, controlSymbols, dataSymbols);
newData.K0 = 0;
newData.K1 = 4;
newData.GrantReason = "new_data_pf";
unchanged = sixgr.l2.mac.rebindHARQRetransmissionTiming(newData);
assert(double(unchanged.K0) == 0 && double(unchanged.K1) == 4, ...
    "New-data timing authority must not be changed by the retransmission adapter.");

ok = true;
end

function probe = localProbe(slot, controlSymbols, dataSymbols)
probe = struct( ...
    "Direction", "DL", ...
    "ControlAbsoluteSlot", double(slot), ...
    "ControlSymbolAllocation", controlSymbols, ...
    "SymbolAllocation", dataSymbols, ...
    "HARQProcess", 0);
end
