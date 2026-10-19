function [state,paths]=publishPacketDeliveryLedgers(state,runFolder)
% One snapshot owner for packet ranges, receiver attempts and delivery CSVs.
% Reconcile after feedback as well as after data RX; a final HARQ release
% must not leave the published packet rows at their earlier in-flight state.
paths=struct();
hasPackets=isfield(state,'PacketDeliveryLedgerTable') && istable(state.PacketDeliveryLedgerTable);
hasAttempts=isfield(state,'HARQTimelineTable') && istable(state.HARQTimelineTable);
if hasPackets
    state=sixgr.truth.refreshApplicationPacketDeliveries(state);
end
if ~sixgr.util.persistenceEnabled(), return; end
if ~hasPackets && ~hasAttempts, return; end
layout=sixgr.report.resultLayout(runFolder);
% Publish the actual receiver-attempt journal before its derived counters.
% Never reconstruct attempts from packet counts or transmitter ACK state.
% A control-only snapshot can retain attempts without application traffic.
if hasAttempts
    paths.HARQ=string(fullfile(layout.HARQCSVDir,'runtime_harq_process_timeline.csv'));
    sixgr.util.csvWriteTable(paths.HARQ,state.HARQTimelineTable,'PreserveSchema',true);
end
if ~hasPackets, return; end
paths.Application=string(fullfile(layout.PacketFlowCSVDir,'live_application_packet_delivery_ledger.csv'));
paths.SDU=string(fullfile(layout.PacketFlowCSVDir,'live_packet_sdu_delivery_ledger.csv'));
sixgr.util.csvWriteTable(paths.Application,state.PacketDeliveryLedgerTable,'PreserveSchema',true);
S=sixgr.util.structGet(state,'PacketSDULedgerTable',table());
sixgr.util.csvWriteTable(paths.SDU,S,'PreserveSchema',true);
if logical(sixgr.util.structGet(state,'ProtocolWaveformEnabled',false)) && ~isempty(S)
    paths.Protocol=string(fullfile(layout.PacketFlowCSVDir,'protocol_in_path_payload_delivery.csv'));
    sixgr.util.csvWriteTable(paths.Protocol,S,'PreserveSchema',true);
end
end
