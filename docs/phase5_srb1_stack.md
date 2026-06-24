# Phase 5 SRB1 Stack

Status: partial helper coverage, pending Phase 5 ASN.1 payload and live UL grant.

Existing surfaces:

- `+sixgr/+l2/+pdcp/PDCP.m`
- `+sixgr/+l2/+rlc/RLC_AM.m`
- `+sixgr/+l2/+rlc/RLC_TM.m`
- `+sixgr/+l3/+rrc/RRC.m`
- `tests/testPDCP_RLC_PacketConservation.m`

Phase 5 requires SRB1 RRCSetupComplete bytes to traverse PDCP, RLC AM, MAC, and
PUSCH. Before security activation, do not claim ciphering or integrity
protection. Before standards-established DRB, user/test traffic must be labeled
`LLS_TEST_DATA_BEARER`.

Pending evidence:

- PDCP header and sequence-number trace for SRB1.
- RLC AM header and sequence-number trace for SRB1.
- MAC LCID mapping to a live PUSCH TB.
- gNB-side reverse path and ASN.1 decode.
