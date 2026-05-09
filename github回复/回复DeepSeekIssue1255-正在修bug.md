Quick housekeeping note on the experiment data I posted earlier.

I found a bug in Experiment Console (the tool I built to run these tests) that affects the `thinking: disabled` mode. Specifically, when thinking mode is disabled, the tool wasn't handling the API response correctly in some edge cases, which may have affected the comparison data between thinking:enabled and thinking:disabled modes.

I'm actively fixing it. The 320-run data (all with thinking:enabled) is still valid — that mode was working correctly. But any claims about thinking:disabled behavior should be considered preliminary until the fix is verified.

Will update when the fix is deployed and re-runs confirm clean data.
