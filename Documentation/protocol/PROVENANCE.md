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
