# RAN1 10.5.3.1 DL-CSI repository inventory

The contribution suite extends the existing SixGR architecture. It does not
replace the production link simulator.

Reused production owners include:

- `sixgr.link.runDLPDSCHThroughput`, `sixgr.lls.runPDSCHTransportBlock`,
  `sixgr.phy.dl.PDSCH_Tx` and `PDSCH_Rx` for coded waveform truth;
- `sixgr.channel.ChannelFactory` and `TR38901Plus` for channel construction;
- `sixgr.phy.rsla.CSIRSResourceEngine`, `SharedDMRSEngine`, `OLLAState`, and
  CSI report serialization for Release-18 reference-signal/link-adaptation
  behavior;
- `sixgr.mimo.buildCSIFeedback`, `selectPMI`, and the classes under
  `sixgr.phy.mimo` for rank, PMI, immutable measurement state, covariance,
  codebook and report contracts;
- `sixgr.phy.beam.BeamManagementStateMachine` for measured beam lifecycle;
- existing atomic CSV, SHA-256, raster export and artifact-store utilities.

The new `sixgr.csi` package is deliberately a TDoc orchestration/evidence
layer. The streamed 128/256/512 logical-port CSI-RS mapper/despreader and its
normalized Walsh/DFT OCC factory extend the existing `sixgr.phy.refsig`
owner. They never reduce the requested port count.

There is exactly one public execution entry point:
`sixgr.csi.runTDocSuite`. Its `plan`, `unit`, `smoke`, `controlled`,
`common_evm`, `figure_replay`, and `audit` modes all use the same owner
bindings. There is no repository-root wrapper and no second CSI PHY path.
Every run writes `manifests/execution_flow_contract.csv`; startup fails if
an authoritative owner is missing, shadowed on the MATLAB path, or copied
into `+sixgr/+csi`.

The generated run-specific inventory, flow contract, and gap analysis are
authoritative because they bind paths and status to the source commit used
for that run.
