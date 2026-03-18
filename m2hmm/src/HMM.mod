IMPLEMENTATION MODULE HMM;
(* Gaussian HMM with diagonal covariance — all in log-space.

   Log-sum-exp trick used for numerical stability:
   log(a + b) = log(a) + log(1 + exp(log(b) - log(a)))

   Gaussian log-emission:
   log N(x|mu,var) = -0.5 * (d*log(2pi) + sum(log(var_f) + (x_f-mu_f)^2/var_f))
*)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT ln, exp;

CONST
  LogZero = -1.0D30;   (* proxy for -infinity in log space *)
  MinVar  = 1.0D-6;    (* minimum variance to avoid log(0) *)
  Log2Pi  = 1.8378770664093453D0;  (* ln(2*pi) *)
  Eps     = 1.0D-10;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr  = POINTER TO INTEGER;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END ElemR;

PROCEDURE ElemI(base: ADDRESS; i: CARDINAL): IntPtr;
BEGIN
  RETURN IntPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(INTEGER)))
END ElemI;

(* ── Log-space helpers ──────────────────────────────── *)

PROCEDURE LogAdd(a, b: LONGREAL): LONGREAL;
(* log(exp(a) + exp(b)) with numerical stability *)
VAR diff: LONGREAL;
BEGIN
  IF a <= LogZero THEN RETURN b END;
  IF b <= LogZero THEN RETURN a END;
  IF a > b THEN
    diff := b - a;
    IF diff < -30.0 THEN RETURN a END;
    RETURN a + LFLOAT(ln(FLOAT(1.0 + LFLOAT(exp(FLOAT(diff))))))
  ELSE
    diff := a - b;
    IF diff < -30.0 THEN RETURN b END;
    RETURN b + LFLOAT(ln(FLOAT(1.0 + LFLOAT(exp(FLOAT(diff))))))
  END
END LogAdd;

PROCEDURE SafeLog(x: LONGREAL): LONGREAL;
BEGIN
  IF x < Eps THEN
    RETURN LFLOAT(ln(FLOAT(Eps)))
  ELSE
    RETURN LFLOAT(ln(FLOAT(x)))
  END
END SafeLog;

(* ── Log Gaussian emission probability ─────────────── *)

PROCEDURE LogEmission(VAR h: GaussHMM; state: CARDINAL;
                       obs: ADDRESS; frameIdx: CARDINAL): LONGREAL;
VAR
  f, nf, offset: CARDINAL;
  logP, diff, v: LONGREAL;
  p: RealPtr;
BEGIN
  nf := h.numFeatures;
  offset := frameIdx * nf;
  logP := -0.5 * LFLOAT(nf) * Log2Pi;

  FOR f := 0 TO nf - 1 DO
    p := ElemR(obs, offset + f);
    diff := p^ - h.means[state][f];
    v := h.vars[state][f];
    IF v < MinVar THEN v := MinVar END;
    logP := logP - 0.5 * (SafeLog(v) + diff * diff / v)
  END;

  RETURN logP
END LogEmission;

(* ── Public API ──────────────────────────────────────── *)

PROCEDURE Init(VAR h: GaussHMM; nStates, nFeatures: CARDINAL);
VAR s, f: CARDINAL; logUniform: LONGREAL;
BEGIN
  IF nStates > MaxStates THEN h.numStates := MaxStates
  ELSE h.numStates := nStates END;

  IF nFeatures > MaxFeatures THEN h.numFeatures := MaxFeatures
  ELSE h.numFeatures := nFeatures END;

  IF h.numStates = 0 THEN
    h.numFeatures := 0;
    h.trained := FALSE;
    RETURN
  END;

  logUniform := SafeLog(1.0 / LFLOAT(h.numStates));

  FOR s := 0 TO h.numStates - 1 DO
    h.logPi[s] := logUniform;
    FOR f := 0 TO h.numStates - 1 DO
      h.logA[s][f] := logUniform
    END;
    FOR f := 0 TO h.numFeatures - 1 DO
      h.means[s][f] := 0.0;
      h.vars[s][f] := 1.0
    END
  END;

  h.trained := FALSE
END Init;

PROCEDURE Free(VAR h: GaussHMM);
BEGIN
  h.trained := FALSE
END Free;

(* ── Supervised training ─────────────────────────────── *)

PROCEDURE TrainSupervised(VAR h: GaussHMM;
                          obs: ADDRESS; labels: ADDRESS;
                          numFrames: CARDINAL);
VAR
  t, s, s2, f, nf, ns: CARDINAL;
  count: ARRAY [0..MaxStates-1] OF CARDINAL;
  transCount: ARRAY [0..MaxStates-1] OF ARRAY [0..MaxStates-1] OF CARDINAL;
  transRowSum: CARDINAL;
  pLabel, pNextLabel: IntPtr;
  pObs: RealPtr;
  label, nextLabel: INTEGER;
  firstLabel: INTEGER;
  hasFirstLabel: BOOLEAN;
  diff: LONGREAL;
BEGIN
  ns := h.numStates;
  nf := h.numFeatures;

  IF (ns = 0) OR (ns > MaxStates) OR (numFrames = 0) THEN RETURN END;

  (* Zero accumulators *)
  FOR s := 0 TO ns - 1 DO
    count[s] := 0;
    h.logPi[s] := LogZero;
    FOR s2 := 0 TO ns - 1 DO
      transCount[s][s2] := 0
    END;
    FOR f := 0 TO nf - 1 DO
      h.means[s][f] := 0.0;
      h.vars[s][f] := 0.0
    END
  END;

  (* Scan forward for the first valid label to use as initial state.
     If no valid label exists in the sequence, fall back to uniform logPi. *)
  firstLabel := -1;
  hasFirstLabel := FALSE;
  FOR t := 0 TO numFrames - 1 DO
    IF NOT hasFirstLabel THEN
      pLabel := ElemI(labels, t);
      label := pLabel^;
      IF (label >= 0) AND (CARDINAL(label) < ns) THEN
        firstLabel := label;
        hasFirstLabel := TRUE
      END
    END
  END;

  (* Accumulate means and transition counts *)
  FOR t := 0 TO numFrames - 1 DO
    pLabel := ElemI(labels, t);
    label := pLabel^;
    IF (label >= 0) AND (CARDINAL(label) < ns) THEN
      s := CARDINAL(label);
      INC(count[s]);

      (* Sum observation values for mean computation *)
      FOR f := 0 TO nf - 1 DO
        pObs := ElemR(obs, t * nf + f);
        h.means[s][f] := h.means[s][f] + pObs^
      END;

      (* Transition count *)
      IF t < numFrames - 1 THEN
        pNextLabel := ElemI(labels, t + 1);
        nextLabel := pNextLabel^;
        IF (nextLabel >= 0) AND (CARDINAL(nextLabel) < ns) THEN
          INC(transCount[s][nextLabel])
        END
      END
    END
  END;

  (* Compute means *)
  FOR s := 0 TO ns - 1 DO
    IF count[s] > 0 THEN
      FOR f := 0 TO nf - 1 DO
        h.means[s][f] := h.means[s][f] / LFLOAT(count[s])
      END
    END
  END;

  (* Compute variances (second pass) *)
  FOR t := 0 TO numFrames - 1 DO
    pLabel := ElemI(labels, t);
    label := pLabel^;
    IF (label >= 0) AND (CARDINAL(label) < ns) THEN
      s := CARDINAL(label);
      FOR f := 0 TO nf - 1 DO
        pObs := ElemR(obs, t * nf + f);
        diff := pObs^ - h.means[s][f];
        h.vars[s][f] := h.vars[s][f] + diff * diff
      END
    END
  END;

  FOR s := 0 TO ns - 1 DO
    IF count[s] > 1 THEN
      FOR f := 0 TO nf - 1 DO
        h.vars[s][f] := h.vars[s][f] / LFLOAT(count[s]);
        IF h.vars[s][f] < MinVar THEN
          h.vars[s][f] := MinVar
        END
      END
    ELSE
      FOR f := 0 TO nf - 1 DO
        h.vars[s][f] := MinVar
      END
    END
  END;

  (* Compute log transition probabilities *)
  FOR s := 0 TO ns - 1 DO
    transRowSum := 0;
    FOR s2 := 0 TO ns - 1 DO
      transRowSum := transRowSum + transCount[s][s2]
    END;
    IF transRowSum > 0 THEN
      FOR s2 := 0 TO ns - 1 DO
        IF transCount[s][s2] > 0 THEN
          h.logA[s][s2] := SafeLog(LFLOAT(transCount[s][s2])
                                   / LFLOAT(transRowSum))
        ELSE
          h.logA[s][s2] := LogZero
        END
      END
    ELSE
      (* No transitions from this state — uniform *)
      FOR s2 := 0 TO ns - 1 DO
        h.logA[s][s2] := SafeLog(1.0 / LFLOAT(ns))
      END
    END
  END;

  (* Compute log initial probabilities.
     Use the first valid label in the sequence as the initial state.
     If no valid label was found, fall back to uniform prior. *)
  IF hasFirstLabel THEN
    h.logPi[firstLabel] := SafeLog(1.0);
    FOR s := 0 TO ns - 1 DO
      IF INTEGER(s) # firstLabel THEN
        h.logPi[s] := SafeLog(Eps)
      END
    END
  ELSE
    FOR s := 0 TO ns - 1 DO
      h.logPi[s] := SafeLog(1.0 / LFLOAT(ns))
    END
  END;

  h.trained := TRUE
END TrainSupervised;

(* ── Viterbi decoding ────────────────────────────────── *)

PROCEDURE Decode(VAR h: GaussHMM;
                 obs: ADDRESS; numFrames: CARDINAL;
                 path: ADDRESS): LONGREAL;
VAR
  t, s, s2, bestPrev: CARDINAL;
  ns: CARDINAL;
  logProb, bestLogProb, emLogProb: LONGREAL;
  pPath: IntPtr;

  (* Viterbi trellis — allocated on heap for large sequences *)
  viterbi: ADDRESS;    (* numFrames x numStates LONGREALs *)
  backptr: ADDRESS;    (* numFrames x numStates INTEGERs *)
  viterbiSize, backptrSize: CARDINAL;
  pV: RealPtr;
  pBI: IntPtr;
  bestState: CARDINAL;
  bestFinal: LONGREAL;
BEGIN
  ns := h.numStates;
  IF ns > MaxStates THEN ns := MaxStates END;

  IF (ns = 0) OR (numFrames = 0) THEN RETURN LogZero END;

  (* Allocate trellis *)
  viterbiSize := numFrames * ns * TSIZE(LONGREAL);
  backptrSize := numFrames * ns * TSIZE(INTEGER);
  ALLOCATE(viterbi, viterbiSize);
  ALLOCATE(backptr, backptrSize);

  (* Initialize: t=0 *)
  FOR s := 0 TO ns - 1 DO
    emLogProb := LogEmission(h, s, obs, 0);
    pV := ElemR(viterbi, s);
    pV^ := h.logPi[s] + emLogProb;
    pBI := ElemI(backptr, s);
    pBI^ := 0
  END;

  (* Recurse: t=1..numFrames-1 *)
  FOR t := 1 TO numFrames - 1 DO
    FOR s := 0 TO ns - 1 DO
      emLogProb := LogEmission(h, s, obs, t);
      bestLogProb := LogZero;
      bestPrev := 0;

      FOR s2 := 0 TO ns - 1 DO
        pV := ElemR(viterbi, (t - 1) * ns + s2);
        logProb := pV^ + h.logA[s2][s];
        IF logProb > bestLogProb THEN
          bestLogProb := logProb;
          bestPrev := s2
        END
      END;

      pV := ElemR(viterbi, t * ns + s);
      pV^ := bestLogProb + emLogProb;
      pBI := ElemI(backptr, t * ns + s);
      pBI^ := INTEGER(bestPrev)
    END
  END;

  (* Termination: find best final state *)
  bestFinal := LogZero;
  bestState := 0;
  FOR s := 0 TO ns - 1 DO
    pV := ElemR(viterbi, (numFrames - 1) * ns + s);
    IF pV^ > bestFinal THEN
      bestFinal := pV^;
      bestState := s
    END
  END;

  (* Backtrace *)
  pPath := ElemI(path, numFrames - 1);
  pPath^ := INTEGER(bestState);
  t := numFrames - 1;
  WHILE t > 0 DO
    pBI := ElemI(backptr, t * ns + bestState);
    bestState := CARDINAL(pBI^);
    DEC(t);
    pPath := ElemI(path, t);
    pPath^ := INTEGER(bestState)
  END;

  (* Cleanup *)
  DEALLOCATE(viterbi, viterbiSize);
  DEALLOCATE(backptr, backptrSize);

  RETURN bestFinal
END Decode;

PROCEDURE Smooth(VAR h: GaussHMM;
                 obs: ADDRESS; numFrames: CARDINAL;
                 smoothed: ADDRESS);
VAR dummy: LONGREAL;
BEGIN
  dummy := Decode(h, obs, numFrames, smoothed)
END Smooth;

(* ── Forward algorithm (log-likelihood) ──────────────── *)

PROCEDURE LogLikelihood(VAR h: GaussHMM;
                        obs: ADDRESS; numFrames: CARDINAL): LONGREAL;
VAR
  t, s, s2, ns: CARDINAL;
  emLogProb, logSum, total: LONGREAL;

  (* Two columns for forward pass — swap each step *)
  prev, curr: ARRAY [0..MaxStates-1] OF LONGREAL;
BEGIN
  ns := h.numStates;
  IF ns > MaxStates THEN ns := MaxStates END;

  IF (ns = 0) OR (numFrames = 0) THEN RETURN LogZero END;

  (* Initialize: t=0 *)
  FOR s := 0 TO ns - 1 DO
    emLogProb := LogEmission(h, s, obs, 0);
    prev[s] := h.logPi[s] + emLogProb
  END;

  (* Forward pass *)
  FOR t := 1 TO numFrames - 1 DO
    FOR s := 0 TO ns - 1 DO
      emLogProb := LogEmission(h, s, obs, t);
      logSum := LogZero;
      FOR s2 := 0 TO ns - 1 DO
        logSum := LogAdd(logSum, prev[s2] + h.logA[s2][s])
      END;
      curr[s] := logSum + emLogProb
    END;
    FOR s := 0 TO ns - 1 DO
      prev[s] := curr[s]
    END
  END;

  (* Sum over final states *)
  total := LogZero;
  FOR s := 0 TO ns - 1 DO
    total := LogAdd(total, prev[s])
  END;

  RETURN total
END LogLikelihood;

END HMM.
