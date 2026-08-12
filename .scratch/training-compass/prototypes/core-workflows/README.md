# Core workflows prototype

PROTOTYPE — throw this away after the interaction decision is captured.

Question: does one clear place for Today, the Cycle ahead, Progress, and Training Maxes expose the information the user needs—including running/cardio performance?

This is a single, dependency-free functional wireframe. It deliberately avoids choosing a visual design. It tests four first-class destinations: Today, Cycle, Progress, and TMs. Progress separates per-lift e1RM history from running/cardio performance.

## Run

```sh
open .scratch/training-compass/prototypes/core-workflows/index.html
```

The prototype keeps all state in memory and performs no HealthKit or file writes. Use the guided walkthrough buttons to read today's strength and running workouts, scan the full cycle ahead, change Training Maxes, inspect per-lift e1RM, and review running volume, pace, and recent sessions.
