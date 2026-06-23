# Phase 4 Decoded RACH Configuration

The Phase 4 anchor installs RACH/common-cell configuration from the decoded SIB1
tree returned by `recoverSIB1FromWaveform`.

## Decoded Fields Used By RA

- Initial UL BWP start RB
- Initial UL BWP size RB
- Initial UL BWP SCS
- Initial UL BWP cyclic prefix
- PRACH configuration index
- Msg1 FDM
- Msg1 PRACH SCS
- Msg1 frequency start
- Root sequence index
- Restricted-set configuration
- Zero-correlation-zone configuration
- Total number of RA preambles
- Preamble received target power
- Power ramping step
- Preamble transmission maximum
- RA response window
- PRACH format
- PUSCH common Msg3 delta preamble
- PUCCH common resource

Each emitted row records:

- decoded ASN.1 path
- decoded value
- units
- standard/default status when known
- source call ID
- source message hash
- source bit range classification
- validation status

The committed artifacts deliberately keep unsupported or not-yet-modeled fields
out of successful Phase 4 claims instead of padding them with labels.
