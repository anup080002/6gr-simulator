function ok = testRuntimeMessageTracker()
%TESTRUNTIMEMESSAGETRACKER Verify generic message lifecycle evidence.

setup6GRSimToolkit("Verbose", false);

runFolder = tempname;
mkdir(runFolder);
cleanupObj = onCleanup(@() rmdir(runFolder, "s")); %#ok<NASGU>

bus = sixgr.runtime.RuntimeEvidenceBus(runFolder, "RunId", "unit_message_tracker");
tracker = sixgr.runtime.RuntimeMessageTracker(bus);
messageId = tracker.createMessage("unit_mac_pdu", "BlockId", "unit_producer");
tracker.sendMessage(messageId, "unit_mac_pdu", "BlockId", "unit_producer");
tracker.receiveMessage(messageId, "unit_mac_pdu", "BlockId", "unit_consumer");
tracker.consumeMessage(messageId, "unit_mac_pdu", "BlockId", "unit_consumer");
tracker.transitionState("unit_state", "created", "consumed", "BlockId", "unit_consumer");
bus.close();

messageJournal = fullfile(runFolder, "runtime", "journal", "message_events.jsonl");
messageCsv = fullfile(runFolder, "runtime", "csv", "message_flow.csv");
assert(exist(messageJournal, "file") == 2, "Message journal must exist.");
assert(exist(messageCsv, "file") == 2, "Message flow CSV must exist.");
T = readtable(messageCsv, "VariableNamingRule", "preserve");
eventTypes = string(T.event_type);
assert(all(ismember(["MESSAGE_CREATE","MESSAGE_SEND","MESSAGE_RECEIVE","MESSAGE_CONSUME","STATE_TRANSITION"], eventTypes)), ...
    "Message tracker must record create/send/receive/consume/state-transition events.");

ok = true;
end
