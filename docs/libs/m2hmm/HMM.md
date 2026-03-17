# HMM

The `HMM` module implements a Gaussian Hidden Markov Model with diagonal covariance in pure Modula-2. It supports supervised training from labeled observation sequences, Viterbi decoding to find the most likely state sequence, sequence smoothing (re-labeling via Viterbi), and forward-algorithm log-likelihood computation. All arithmetic is performed in log-space to avoid the numerical underflow that plagues naive HMM implementations.

## Why HMM?

Audio signals are inherently sequential: the class of a given frame depends not just on its acoustic content but also on the classes of neighboring frames. A frame-by-frame classifier like k-NN can produce noisy, rapidly oscillating labels because it treats each frame independently. An HMM adds temporal structure by modeling state transitions explicitly -- it learns which state sequences are probable and which are not. When layered on top of a frame-level classifier (as in the `Segment` module), the HMM acts as a temporal smoother, eliminating isolated misclassifications and producing coherent segment boundaries. This module provides a self-contained implementation with no external dependencies beyond the standard math library, keeping the entire sndys signal-processing stack in pure Modula-2.

## Log-Space Computation

### The Problem

HMM algorithms multiply many small probabilities together. For a sequence of T frames with N states, the forward algorithm accumulates products like `P(o1|s) * P(s'|s) * P(o2|s') * ...` across hundreds or thousands of time steps. These products rapidly underflow to zero in 64-bit floating point, even for modest sequence lengths (T > 50).

### The Solution

All probabilities are stored and manipulated as natural logarithms. Multiplication becomes addition (`log(a*b) = log(a) + log(b)`), and addition of probabilities uses the log-sum-exp identity:

```
log(a + b) = log(a) + log(1 + exp(log(b) - log(a)))
```

where `a >= b`. The implementation guards against overflow by checking the difference `log(b) - log(a)` and returning early when it is too negative to matter. A sentinel value `LogZero = -1.0E30` represents zero probability (i.e., negative infinity in log-space). The `SafeLog` helper clamps inputs to a small epsilon before taking the logarithm, preventing `log(0)` errors.

## Gaussian Emission Model

Each HMM state emits observations according to a multivariate Gaussian distribution with diagonal covariance. The diagonal assumption means each feature dimension has its own variance but features are treated as independent given the state. This is a standard simplification that dramatically reduces the number of parameters (from O(d^2) to O(d) per state) while remaining effective for audio feature vectors where dimensions such as MFCCs are already decorrelated.

The log-emission probability for observation vector **x** given state s is:

```
log N(x | mu_s, var_s) = -0.5 * (d*log(2*pi) + SUM_f [log(var_s[f]) + (x[f] - mu_s[f])^2 / var_s[f]])
```

where d is the feature dimensionality, mu_s is the mean vector for state s, and var_s is the diagonal variance vector. A minimum variance floor (`MinVar = 1.0E-6`) prevents division by zero and `log(0)` when a feature has near-constant value in a state.

## Viterbi Decoding Algorithm

The Viterbi algorithm finds the single most likely state sequence for a given observation sequence. It operates in three phases:

1. **Initialization (t=0):** For each state s, compute `delta[0][s] = logPi[s] + logEmission(s, obs[0])`, the log-probability of starting in state s and emitting the first observation.

2. **Recursion (t=1..T-1):** For each state s at time t, find the predecessor state s' that maximizes `delta[t-1][s'] + logA[s'][s]`, then add the emission log-probability: `delta[t][s] = max_s'(delta[t-1][s'] + logA[s'][s]) + logEmission(s, obs[t])`. A backpointer array records the best predecessor at each step.

3. **Termination and backtrace:** The best final state is `argmax_s delta[T-1][s]`. The algorithm follows backpointers from `T-1` back to `0` to reconstruct the optimal path.

The trellis and backpointer arrays are heap-allocated (one LONGREAL per state per frame) and freed after decoding. Time complexity is O(T * N^2) where N is the number of states and T is the sequence length.

## Constants

### MaxStates

```modula2
CONST
  MaxStates = 32;
```

The maximum number of HMM states. State indices must be in the range `0..numStates-1`, and `numStates` must not exceed this value.

### MaxFeatures

```modula2
CONST
  MaxFeatures = 128;
```

The maximum observation dimensionality. Feature vectors must have at most this many elements.

## Types

### GaussHMM

```modula2
TYPE
  GaussHMM = RECORD
    numStates:   CARDINAL;
    numFeatures: CARDINAL;
    logPi: ARRAY [0..31] OF LONGREAL;
    logA:  ARRAY [0..31] OF ARRAY [0..31] OF LONGREAL;
    means: ARRAY [0..31] OF ARRAY [0..127] OF LONGREAL;
    vars:  ARRAY [0..31] OF ARRAY [0..127] OF LONGREAL;
    trained: BOOLEAN;
  END;
```

The complete state of a Gaussian HMM. `logPi` holds log initial state probabilities. `logA` holds the log transition matrix where `logA[from][to]` is the log-probability of transitioning from state `from` to state `to`. `means` and `vars` hold the per-state Gaussian parameters (mean and variance for each feature dimension). The `trained` flag is set to `TRUE` after `TrainSupervised` completes.

Note that observation data is not stored in the model -- the caller must keep observation arrays alive during `Decode`, `Smooth`, and `LogLikelihood` calls.

## Procedures

### Init

```modula2
PROCEDURE Init(VAR h: GaussHMM; nStates, nFeatures: CARDINAL);
```

Initializes an HMM with the given number of states and features. Sets uniform initial state probabilities (`logPi[s] = log(1/nStates)` for all s) and uniform transition probabilities (`logA[i][j] = log(1/nStates)` for all i, j). Means are set to zero and variances to one. The `trained` flag is set to `FALSE`. If `nStates` exceeds `MaxStates` or `nFeatures` exceeds `MaxFeatures`, the values are clamped to the maximum. This must be called before `TrainSupervised`.

**Example:**

```modula2
VAR hmm: GaussHMM;
HMM.Init(hmm, 3, 34);
(* 3-state HMM for 34-dimensional feature vectors *)
```

---

### Free

```modula2
PROCEDURE Free(VAR h: GaussHMM);
```

Releases any internal resources associated with the model. In the current implementation the model is entirely stack-allocated, so this procedure simply resets the `trained` flag. It should still be called for forward compatibility.

**Example:**

```modula2
HMM.Free(hmm);
```

---

### TrainSupervised

```modula2
PROCEDURE TrainSupervised(VAR h: GaussHMM;
                          obs: ADDRESS; labels: ADDRESS;
                          numFrames: CARDINAL);
```

Estimates all HMM parameters from a labeled observation sequence using maximum likelihood. `obs` points to a row-major matrix of `numFrames` rows by `numFeatures` columns of `LONGREAL` values. `labels` points to `numFrames` `INTEGER` values containing 0-based state indices.

The procedure computes:

1. **Initial state probabilities** from the label of the first frame. The observed first-frame state receives `log(1.0)`; all other states receive a near-zero log-probability.
2. **Transition matrix** by counting consecutive label pairs and normalizing per row. States with no outgoing transitions receive uniform probabilities.
3. **Per-state means** by averaging all observation vectors assigned to each state.
4. **Per-state variances** in a second pass over the data, computing the mean squared deviation from the state mean. Variances are floored at `1.0E-6` to ensure numerical stability.

**Example:**

```modula2
VAR
  obs: ARRAY [0..339] OF LONGREAL;    (* 10 frames x 34 features *)
  labels: ARRAY [0..9] OF INTEGER;
(* ... fill obs and labels ... *)
HMM.TrainSupervised(hmm, ADR(obs), ADR(labels), 10);
```

---

### Decode

```modula2
PROCEDURE Decode(VAR h: GaussHMM;
                 obs: ADDRESS; numFrames: CARDINAL;
                 path: ADDRESS): LONGREAL;
```

Performs Viterbi decoding to find the most likely state sequence for the given observations. `obs` is a row-major matrix of `numFrames` x `numFeatures` LONGREALs. `path` points to an array of `numFrames` INTEGERs that will be filled with the predicted state index for each frame. Returns the log-likelihood of the best path.

The procedure allocates a Viterbi trellis and backpointer array on the heap (`numFrames * numStates` LONGREALs each), runs the forward pass, backtraces to recover the optimal path, and frees the heap memory before returning.

**Example:**

```modula2
VAR
  obs: ARRAY [0..3399] OF LONGREAL;  (* 100 frames x 34 features *)
  path: ARRAY [0..99] OF INTEGER;
  logProb: LONGREAL;
(* ... fill obs ... *)
logProb := HMM.Decode(hmm, ADR(obs), 100, ADR(path));
(* path[t] is the predicted state for frame t *)
(* logProb is the log-likelihood of this state sequence *)
```

---

### Smooth

```modula2
PROCEDURE Smooth(VAR h: GaussHMM;
                 obs: ADDRESS; numFrames: CARDINAL;
                 smoothed: ADDRESS);
```

Re-labels a sequence by running Viterbi decoding on the observations. This is functionally identical to `Decode` but discards the log-likelihood return value, making it a convenient one-call interface when you only need the smoothed labels. `smoothed` is filled with `numFrames` INTEGERs.

This is the procedure used by the `Segment` module to smooth noisy frame-by-frame k-NN predictions into temporally coherent segments.

**Example:**

```modula2
VAR
  obs: ARRAY [0..3399] OF LONGREAL;
  smoothed: ARRAY [0..99] OF INTEGER;
HMM.Smooth(hmm, ADR(obs), 100, ADR(smoothed));
(* smoothed[t] contains temporally-consistent state labels *)
```

---

### LogLikelihood

```modula2
PROCEDURE LogLikelihood(VAR h: GaussHMM;
                        obs: ADDRESS; numFrames: CARDINAL): LONGREAL;
```

Computes the total log-probability of the observation sequence under the model using the forward algorithm. Unlike Viterbi (which finds the single best path), the forward algorithm sums over all possible state sequences. This gives a true marginal likelihood that can be used for model comparison or goodness-of-fit evaluation.

The implementation uses a two-column rolling buffer (previous and current time step) rather than a full T x N matrix, keeping memory usage at O(N) regardless of sequence length.

**Example:**

```modula2
VAR logL: LONGREAL;
logL := HMM.LogLikelihood(hmm, ADR(obs), 100);
(* logL is the total log-probability of the sequence *)
```

## Example

A complete program that creates a simple 2-state HMM, trains it from labeled data, and uses Viterbi decoding to smooth a noisy label sequence.

```modula2
MODULE HMMDemo;

FROM SYSTEM IMPORT ADR;
FROM STextIO IMPORT WriteString, WriteLn;
FROM SWholeIO IMPORT WriteInt;
FROM SLongIO IMPORT WriteFixed;
IMPORT HMM;

CONST
  NFrames   = 12;
  NFeatures = 2;
  NStates   = 2;

VAR
  obs: ARRAY [0..NFrames * NFeatures - 1] OF LONGREAL;
  labels: ARRAY [0..NFrames - 1] OF INTEGER;
  path: ARRAY [0..NFrames - 1] OF INTEGER;
  hmm: HMM.GaussHMM;
  logProb: LONGREAL;
  t: CARDINAL;

BEGIN
  (* Observation data: state 0 clusters near (1, 1), state 1 near (5, 5) *)
  (* Frames 0-5: state 0 *)
  obs[0] := 0.9; obs[1] := 1.1;
  obs[2] := 1.0; obs[3] := 0.8;
  obs[4] := 1.2; obs[5] := 1.0;
  obs[6] := 0.8; obs[7] := 0.9;
  obs[8] := 1.1; obs[9] := 1.2;
  obs[10] := 1.0; obs[11] := 1.0;
  (* Frames 6-11: state 1 *)
  obs[12] := 5.0; obs[13] := 5.1;
  obs[14] := 4.8; obs[15] := 5.2;
  obs[16] := 5.1; obs[17] := 4.9;
  obs[18] := 5.0; obs[19] := 5.0;
  obs[20] := 4.9; obs[21] := 5.1;
  obs[22] := 5.2; obs[23] := 4.8;

  (* Noisy labels: mostly correct but with two errors *)
  labels[0] := 0; labels[1] := 0; labels[2] := 1;  (* error at frame 2 *)
  labels[3] := 0; labels[4] := 0; labels[5] := 0;
  labels[6] := 1; labels[7] := 1; labels[8] := 0;  (* error at frame 8 *)
  labels[9] := 1; labels[10] := 1; labels[11] := 1;

  (* Initialize and train *)
  HMM.Init(hmm, NStates, NFeatures);
  HMM.TrainSupervised(hmm, ADR(obs), ADR(labels), NFrames);

  (* Decode: Viterbi should correct the noisy labels *)
  logProb := HMM.Decode(hmm, ADR(obs), NFrames, ADR(path));

  WriteString("Frame  Noisy  Smoothed"); WriteLn;
  WriteString("-----  -----  --------"); WriteLn;
  FOR t := 0 TO NFrames - 1 DO
    WriteString("  ");
    WriteInt(INTEGER(t), 3);
    WriteString("    ");
    WriteInt(labels[t], 3);
    WriteString("     ");
    WriteInt(path[t], 3);
    WriteLn
  END;

  WriteLn;
  WriteString("Log-likelihood of best path: ");
  WriteFixed(logProb, 2, 10);
  WriteLn;

  WriteString("Log-likelihood of sequence:  ");
  WriteFixed(HMM.LogLikelihood(hmm, ADR(obs), NFrames), 2, 10);
  WriteLn;

  HMM.Free(hmm)
END HMMDemo.
```
