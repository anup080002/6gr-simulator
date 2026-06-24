# Phase 5 Scheduling Request

Status: pending connected SR runtime.

Phase 5 UL scheduling may not be triggered by direct inspection of the UE queue.
The UE must transmit SR over PUCCH, the gNB must decode SR, and only then may
the scheduler use that decoded control state to issue an UL grant unless another
standards-valid trigger applies.

Required evidence:

- SR trigger state at UE.
- PUCCH SR waveform and resource.
- gNB SR detection, DTX and false-alarm status.
- SR prohibit timer behavior.
- Scheduler state update sourced from decoded SR.
