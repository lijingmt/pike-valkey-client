# Engineering Philosophy: The Infinite-Loop Engineer and the Monitoring Engineer

> This document is the engineering constitution of pike-valkey-client.
> It covers no API — only the spirit we use to polish this project,
> and where human engineers and AI each stand.

## 1. The Infinite-Loop Engineer

The infinite-loop engineer is not someone who writes `while(1)`.
They are someone **who dares to enter the loop — and takes responsibility
for it**.

Their method is one sentence: **hypothesize → falsify → narrow the circle
until only the truth remains**.

- Every "I think it's here" must come with an experiment that can kill it.
  A hypothesis that cannot be killed does not earn the next round.
- Debugging is not guessing; it is bisection: one experiment eliminates
  half the suspects — from "did the server get it? did the client read it?
  is the protocol wrong? is the environment broken?" down to a single line.
- Every loop must have an exit. The exit is never "I feel close enough" —
  it is **reproducible evidence**: a packet capture, a queue snapshot,
  a stack sample, a passing test.
- When reasoning stalls, return to first principles: read the source
  (we really did read Pike's `file.cmod` and `do_read`), instead of
  stacking assumptions in your head.

AI is best at generating hypotheses and worst at killing them. So in this
project, **AI proposes the loops; humans set their termination conditions**.

## 2. The Monitoring Engineer

The monitoring engineer's creed: **what cannot be observed cannot be fixed**.

- When output is swallowed by buffering, don't wait — take a path that
  isn't buffered. When our smoke test hung in silence, it was the server-side
  `MONITOR`, connection queue snapshots, and process stack samples that
  located it.
- Every layer deserves its own eyes: client logs, server `MONITOR`,
  kernel queues (`netstat` Send-Q/Recv-Q), process state (`sample`).
  Only facts confirmed by several eyes count as evidence; a lone witness
  is merely a lead.
- Tests are monitoring: `tests/smoke.pike` is not a throwaway script,
  it is this library's permanent health probe. The release gate is simple:
  it must be green.

AI can run commands for you, but **designing the observation points** —
where to instrument, what to measure, what counts as normal — is forever
the engineer's job.

## 3. The Engineer's Role, and AI's Infinite Loop

```
AI's infinite loop:   hypothesis → hypothesis → hypothesis … (diverges)
The engineer's loop:  hypothesis → experiment → falsify → converges (has exits)
```

- AI is the tireless doubter and executor: it doesn't fear trying the tenth
  possibility, nor reading three thousand lines of C source.
- The engineer is the gatekeeper of the loop: deciding what is worth trying,
  what counts as evidence, and when to stop and admit "this path is dead,
  take another".
- Good collaboration means **AI's speed of looping paired with human
  decisiveness in setting exits**. The worst case is the reverse — humans
  jogging behind AI's hypotheses while the loop spins ever deeper.

## 4. The Spirit of Polishing a Project

1. **Evidence before synthesis**: reproducible observation first, conclusions
   second. Guessing right doesn't count; measuring right does.
2. **Small steps, fast proof**: change one variable at a time (read logic vs.
   constructor visibility were verified separately), run immediately after
   each change, roll back the hypothesis as soon as it turns red.
3. **Honor the counterexample**: when MONITOR proved "the server received it
   and the client just can't read it", all prior reasoning was voided and we
   restarted from evidence. No defensiveness, no sunk cost.
4. **Write the lesson into the repo**: every late-night debugging conclusion
   becomes a test case, a doc, or a comment — never left behind in chat logs.
5. **Enough is beautiful**: this library is only a few hundred lines, but
   every line has been verified on a live server. Few lines is not shabby —
   it means every line stands guard with evidence behind it.

---

*This philosophy was written while debugging the RESP bulk-read path.
It applies to this repo — and to any open-source project you care to
polish seriously.*
