# Phase-18 artifact-schema call chain

The immutable source run failed because two production components used different, implicit table schemas.

1. `FullStackQualificationRunner.run` calls `ArtifactCompletenessEngine.run` and retains `artifactAudit.Combined`.
2. `ArtifactCompletenessEngine.localScan` constructs that table from `localCombinedRow`.
3. The emitted legacy schema contains `ArtifactID`, `FileName`, validation flags, `Status`, `FailureCode`, and `Details`. It does not contain `ArtifactType`.
4. `FullStackQualificationRunner.run` passes the unchanged legacy table to `QualificationFinalizationCoordinator.assess`.
5. `QualificationFinalizationCoordinator.assess` directly indexes `audit.ArtifactType`, producing `MATLAB:table:UnrecognizedVarName`.

At the reproducing revision the relevant source locations were:

- `+sixgr/+integration/+qualification/ArtifactCompletenessEngine.m:33`
- `+sixgr/+integration/+qualification/ArtifactCompletenessEngine.m:38`
- `+sixgr/+integration/+qualification/ArtifactCompletenessEngine.m:359`
- `+sixgr/+integration/+qualification/FullStackQualificationRunner.m:159`
- `+sixgr/+integration/+qualification/FullStackQualificationRunner.m:160`

Producer schema: `phase18-artifact-completeness-combined/v0` (implicit legacy schema).

Consumer expectation: an unversioned table with at least `ArtifactType`, `Present`, `HashValid`, `SHA256`, and requirement fields.

The fix is a versioned canonical schema and an explicit normalizer at the producer/consumer boundary. Legacy aliases and extension-derived types remain identifiable through `ArtifactTypeSource`; unknown or contradictory inputs fail closed with typed diagnostics.
