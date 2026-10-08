# defer-to-resample bug demo (ControlArena 20.0.1)

A minimal, scripted, **no-real-models** demo of a bug in ControlArena's
`defer_to_resample` micro-protocol. It shows the bug on stock
`control-arena==20.0.1` and that the fix works on
[`32bitsret/control-arena@fix/defer-to-resample-append-message`](https://github.com/32bitsret/control-arena/tree/fix/defer-to-resample-append-message).

## The bug

When the monitor flags the untrusted agent's proposed action, `defer_to_resample`
draws fresh resamples from the same pre-step history. If one of them is below
`defer_threshold`, it is supposed to be executed. In 20.0.1 the chosen resample is
set as `state.output` but **never appended to `state.messages`**:

```python
# control_arena/micro_protocol/_defer_to_resample.py (v20.0.1, L153-163)
least_sus_message.metadata = metadata.model_dump()
state.output = least_sus
return state
```

The resamples ran in `inspect_ai.agent.run()`, which works on *copies* of the state,
so the original `state` never received the message. Inspect's `react()` loop runs
tool calls from the **last message in `state.messages`**, not from `state.output`.
The result:

- the chosen action is never executed;
- the step still counts against `max_steps`;
- the step's DTR metadata disappears from the transcript;
- the agent is re-prompted from the same history, with no indication it was blocked.

Upstream file, pinned:
<https://github.com/UKGovernmentBEIS/control-arena/blob/v20.0.1/control_arena/micro_protocol/_defer_to_resample.py#L153-L163>

## The fix

On the fork branch
([`fix/defer-to-resample-append-message`](https://github.com/32bitsret/control-arena/tree/fix/defer-to-resample-append-message),
commits `d2c0c9b4` test + `92fcffcb` fix):

```diff
             least_sus_message.metadata = metadata.model_dump()
             state.output = least_sus
+            # The resamples ran on copies of `state`, so the chosen message is not
+            # in its history yet. Append it so the scaffold executes its tool calls.
+            state.messages.append(least_sus_message)
             return state
```

## The demo

`tests/test_defer_to_resample_bug.py` runs a single-step agent loop (`max_steps=1`)
through a real Inspect eval with `mockllm/model`, a scripted policy and a scripted
monitor:

1. The untrusted policy proposes `act("FLAGGED_ACTION")`. The monitor scores it 0.9,
   above the threshold of 0.5.
2. `defer_to_resample` draws one resample: `act("RESAMPLED_ACTION")`. The monitor
   scores it 0.1, so it is chosen.
3. **Stock 20.0.1:** the test asserts the chosen action is never executed and never
   enters the history, while the single step is consumed (`StepCounter == 1`, and
   the sample ends with "Max steps limit of 1 reached").
4. **Fixed branch:** the test asserts `RESAMPLED_ACTION` is in the history and
   executed **exactly once**.

`DEMO_TARGET=stock|fixed` selects which expectation runs. As a cross-check,
`run_both.sh` also runs the *fixed* expectations against stock 20.0.1, which must fail.

## How to run

Requires [uv](https://docs.astral.sh/uv/) and git. No API keys or Docker are needed.

```bash
./run_both.sh        # or: make both
```

This creates `.venv-stock` (`requirements-stock.txt`: control-arena==20.0.1) and
`.venv-fixed` (`requirements-fixed.txt`: the fork branch). Both pin
`inspect-ai==0.3.257`, the version in control-arena 20.0.1's lockfile. The script
runs the test in each venv and writes:

- `results/stock-20.0.1.txt`
- `results/fixed.txt`
- `results/cross-check-stock-vs-fixed-expectations.txt`
- `results/side-by-side.md`

## Results (captured by `run_both.sh`, committed in `results/`)

| | Stock 20.0.1 (bug) | Fixed branch |
|---|---|---|
| control-arena | `20.0.1 from PyPI` | `20.0.2.dev2 from https://github.com/32bitsret/control-arena@fix/defer-to-resample-append-message (92fcffcb)` |
| inspect-ai | `0.3.257` | `0.3.257` |
| untrusted proposals (in order) | `['FLAGGED_ACTION', 'RESAMPLED_ACTION']` | `['FLAGGED_ACTION', 'RESAMPLED_ACTION']` |
| trusted proposals | `[]` | `[]` |
| actions in message history | `[]` | `['RESAMPLED_ACTION']` |
| actions executed (tool results) | `[]` | `['RESAMPLED_ACTION']` |
| steps used (StepCounter) | `1` | `1` |
| max_steps | `1` | `1` |
| sample ended by | `Sample limit exceeded (custom): Max steps limit of 1 reached.` | `Sample limit exceeded (custom): Max steps limit of 1 reached.` |
| final transcript roles | `['system', 'user']` | `['system', 'user', 'assistant', 'tool']` |
| **test result** | `test_stock_20_0_1_drops_chosen_resample` PASSED (1 passed, 1 skipped in 8.35s) | `test_fixed_branch_executes_chosen_resample_once` PASSED (1 passed, 1 skipped in 8.49s) |

Cross-check (stock 20.0.1 with the fixed expectations): **fails as expected**:

```
AssertionError: assert [] == ['RESAMPLED_ACTION']
========================= 1 failed, 1 skipped in 3.73s =========================
```

Both runs end at the step limit, because the demo allows exactly one step. The
difference is whether that step did anything: on stock 20.0.1 it was spent
without executing the chosen action.

## Scope

This is a personal reproduction and is not affiliated with UK AISI or Redwood
Research. ControlArena is MIT-licensed by the UK AI Security Institute. This
demo is MIT-licensed (see `LICENSE`).
