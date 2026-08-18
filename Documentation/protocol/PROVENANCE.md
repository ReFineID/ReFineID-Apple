# Vendored RAPP protocol documents

`rapp-v26.8.17.233.md` and `rapp-state-machine-v26.8.17.233.yaml` are copied
verbatim from the ReFineID project's canonical protocol tree, document version
26.8.17.233, wire version 26.8.

They are the specification this repository's Swift RAPP engine implements, and
the state model its transition tables are transcribed from. The conformance
corpus in `../rapp-conformance/` is generated from the same revision and is
replayed by the test suite, so a change here that the engine does not follow
fails the build rather than drifting silently.

Do not edit these files here. Change them at the canonical source, regenerate
the corpus, and re-vendor all three together.

`../rapp-conformance/rapp-transport-v26.8.17.233.json` records post-handshake
frames generated from the canonical Rust engine at wire version 26.8, using the
same fixed keys as the conformance corpus's handshake transcripts. The corpus
proves the handshake but stops there, so without these the framing that carries
every operation would have no golden vectors: sixteen frames per suite, both
directions, with counters running well past their first value.

`../rapp-conformance/rapp-flow-v26.8.17.233.json` and
`../rapp-conformance/rapp-operation-v26.8.17.233.json` record message bodies
generated from the canonical Rust engine at wire version 26.8, with every input
fixed and recorded beside the bytes so the Swift engine can build the same
values. The conformance corpus covers the envelope and the handshake but no
message body above them, so without these the pairing, session, and operation
bodies would be checked only for round-trip: an encoding both sides of one
implementation agree on can still be one no peer accepts.

