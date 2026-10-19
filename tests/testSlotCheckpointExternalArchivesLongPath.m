function ok=testSlotCheckpointExternalArchivesLongPath()
% Exact same external restore contract beyond MAX_PATH; no PHY claim.
ok=testSlotCheckpointExternalArchives(true);
end
