; examples/net_families_smoke.s — SPEC §13.0 canonical header smoke test.
; Assembled by `make verify-net-families`: the root net_families.inc must
; assemble standalone and carry exactly the four values the contract
; specifies. Bits are append-only (§8.0 discipline); a changed value here
; is a contract break, not a refresh.
.include "net_families.inc"
.assert NET_FAMILY_CORE = $0001, error, "NET_FAMILY_CORE must be $0001 (SPEC 13.0)"
.assert NET_FAMILY_TCP  = $0002, error, "NET_FAMILY_TCP must be $0002 (SPEC 13.0)"
.assert NET_FAMILY_UDP  = $0004, error, "NET_FAMILY_UDP must be $0004 (SPEC 13.0)"
.assert NET_FAMILY_DNS  = $0008, error, "NET_FAMILY_DNS must be $0008 (SPEC 13.0)"
; include guard: a second include must be inert
.include "net_families.inc"
.assert (NET_FAMILY_CORE | NET_FAMILY_TCP | NET_FAMILY_UDP | NET_FAMILY_DNS) = $000F, error, "family bits must be disjoint"
