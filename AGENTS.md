- Please No AI attribution spam in commits.
  No `Co-authored-by` / `Signed-off-by` / `Reviewed-by`
  or any AI-naming trailer; subject + body only. 
- Apple uses PascalCase.
- ASCII only in source, UTF-8 only where required.
- No Magic Codes - define everything.   
- Commit often when compiles and lint is clean.
- Push when feature is ready.
- Built-in NFC is a production iPhone feature. TestFlight and
  App Store builds must ship it. Never remove, disable, build-gate, or
  reclassify NFC as future work to fix a bug; preserve NFC and fix the
  trigger or path that is wrong.
- Verify from specifications, don't wild guess.
  `doc/references.md` indexes which one governs what.
  Cite what a source proves, and say what it does not.
  Where observation contradicts Apple's docs, the recorded
  exchange wins and is cited as observation, not spec.
- Less is more. Terse is better.
- Do not leak personal or private information in commits.
- When stuck, research with fellow AI available.
- If something is not working, it is by default a bug in OUR code (or
  test harness), not a feature of the platform. "Impossible/blocked"
  claims require exchange-level evidence from a clean-slate repro.
