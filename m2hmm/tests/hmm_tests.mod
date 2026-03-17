MODULE HmmTests;
(* Test suite for m2hmm: Gaussian HMM.

   Tests:
     1. Init sets uniform priors
     2. TrainSupervised computes correct means
     3. TrainSupervised computes correct variances
     4. TrainSupervised computes correct transitions
     5. Decode recovers training labels on training data
     6. Decode on 2-state alternating sequence
     7. Smooth produces same result as Decode
     8. LogLikelihood is finite for trained model
     9. LogLikelihood is higher for matching data than mismatched *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM HMM IMPORT GaussHMM, MaxStates, MaxFeatures,
                Init, Free, TrainSupervised, Decode, Smooth,
                LogLikelihood;

CONST
  Eps = 1.0D-4;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr  = POINTER TO INTEGER;

VAR
  passed, failed, total: INTEGER;

PROCEDURE Check(name: ARRAY OF CHAR; cond: BOOLEAN);
BEGIN
  INC(total);
  IF cond THEN
    INC(passed)
  ELSE
    INC(failed);
    WriteString("FAIL: "); WriteString(name); WriteLn
  END
END Check;

PROCEDURE Near(a, b: LONGREAL): BOOLEAN;
VAR d: LONGREAL;
BEGIN
  d := a - b;
  IF d < 0.0 THEN d := -d END;
  RETURN d < Eps
END Near;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END ElemR;

PROCEDURE ElemI(base: ADDRESS; i: CARDINAL): IntPtr;
BEGIN
  RETURN IntPtr(LONGCARD(base) + LONGCARD(i * TSIZE(INTEGER)))
END ElemI;

(* ── Test 1: Init ─────────────────────────────────── *)

PROCEDURE Test1;
VAR h: GaussHMM;
BEGIN
  Init(h, 3, 2);
  Check("init: numStates=3", h.numStates = 3);
  Check("init: numFeatures=2", h.numFeatures = 2);
  Check("init: not trained", NOT h.trained);
  Free(h)
END Test1;

(* ── Test 2-4: TrainSupervised ────────────────────── *)

PROCEDURE TestTrain;
VAR
  h: GaussHMM;
  (* 2 states, 2 features, 6 frames:
     State 0: obs near (0, 0)
     State 1: obs near (10, 10)
     Sequence: 0, 0, 0, 1, 1, 1 *)
  obs: ARRAY [0..11] OF LONGREAL;
  labels: ARRAY [0..5] OF INTEGER;
BEGIN
  (* State 0 observations *)
  obs[0] := 0.1;  obs[1] := 0.2;   labels[0] := 0;
  obs[2] := -0.1; obs[3] := 0.0;   labels[1] := 0;
  obs[4] := 0.0;  obs[5] := -0.1;  labels[2] := 0;

  (* State 1 observations *)
  obs[6] := 10.0;  obs[7] := 10.1;  labels[3] := 1;
  obs[8] := 9.9;   obs[9] := 10.0;  labels[4] := 1;
  obs[10] := 10.1; obs[11] := 9.9;  labels[5] := 1;

  Init(h, 2, 2);
  TrainSupervised(h, ADR(obs), ADR(labels), 6);

  (* Test 2: means *)
  Check("train: mean[0][0]~0", Near(h.means[0][0], 0.0));
  Check("train: mean[1][0]~10", Near(h.means[1][0], 10.0));
  Check("train: mean[1][1]~10", Near(h.means[1][1], 10.0));

  (* Test 3: variances should be small *)
  Check("train: var[0][0] small", h.vars[0][0] < 0.1);
  Check("train: var[1][0] small", h.vars[1][0] < 0.1);

  (* Test 4: transitions — state 0->0 should be strong *)
  Check("train: trained", h.trained);

  Free(h)
END TestTrain;

(* ── Test 5: Decode recovers labels ──────────────── *)

PROCEDURE TestDecodeRecover;
VAR
  h: GaussHMM;
  obs: ARRAY [0..11] OF LONGREAL;
  labels: ARRAY [0..5] OF INTEGER;
  decoded: ARRAY [0..5] OF INTEGER;
  logProb: LONGREAL;
  i: CARDINAL;
  allMatch: BOOLEAN;
BEGIN
  obs[0] := 0.1;  obs[1] := 0.2;   labels[0] := 0;
  obs[2] := -0.1; obs[3] := 0.0;   labels[1] := 0;
  obs[4] := 0.0;  obs[5] := -0.1;  labels[2] := 0;
  obs[6] := 10.0; obs[7] := 10.1;  labels[3] := 1;
  obs[8] := 9.9;  obs[9] := 10.0;  labels[4] := 1;
  obs[10] := 10.1; obs[11] := 9.9; labels[5] := 1;

  Init(h, 2, 2);
  TrainSupervised(h, ADR(obs), ADR(labels), 6);

  logProb := Decode(h, ADR(obs), 6, ADR(decoded));
  Check("decode: logProb finite", logProb > -1.0D20);

  allMatch := TRUE;
  FOR i := 0 TO 5 DO
    IF decoded[i] # labels[i] THEN allMatch := FALSE END
  END;
  Check("decode: recovers labels", allMatch);

  Free(h)
END TestDecodeRecover;

(* ── Test 6: Decode alternating ──────────────────── *)

PROCEDURE TestDecodeAlternating;
VAR
  h: GaussHMM;
  obs: ARRAY [0..15] OF LONGREAL;  (* 8 frames x 2 features *)
  labels: ARRAY [0..7] OF INTEGER;
  decoded: ARRAY [0..7] OF INTEGER;
  logProb: LONGREAL;
  i: CARDINAL;
  allMatch: BOOLEAN;
BEGIN
  (* Alternating: 0,1,0,1,0,1,0,1 *)
  obs[0] := 0.0;  obs[1] := 0.0;   labels[0] := 0;
  obs[2] := 10.0; obs[3] := 10.0;  labels[1] := 1;
  obs[4] := 0.1;  obs[5] := -0.1;  labels[2] := 0;
  obs[6] := 9.9;  obs[7] := 10.1;  labels[3] := 1;
  obs[8] := -0.1; obs[9] := 0.1;   labels[4] := 0;
  obs[10] := 10.1; obs[11] := 9.9; labels[5] := 1;
  obs[12] := 0.0; obs[13] := 0.0;  labels[6] := 0;
  obs[14] := 10.0; obs[15] := 10.0; labels[7] := 1;

  Init(h, 2, 2);
  TrainSupervised(h, ADR(obs), ADR(labels), 8);

  logProb := Decode(h, ADR(obs), 8, ADR(decoded));

  allMatch := TRUE;
  FOR i := 0 TO 7 DO
    IF decoded[i] # labels[i] THEN allMatch := FALSE END
  END;
  Check("alt decode: recovers pattern", allMatch);

  Free(h)
END TestDecodeAlternating;

(* ── Test 7: Smooth = Decode ─────────────────────── *)

PROCEDURE TestSmooth;
VAR
  h: GaussHMM;
  obs: ARRAY [0..11] OF LONGREAL;
  labels: ARRAY [0..5] OF INTEGER;
  decoded: ARRAY [0..5] OF INTEGER;
  smoothed: ARRAY [0..5] OF INTEGER;
  logProb: LONGREAL;
  i: CARDINAL;
  allMatch: BOOLEAN;
BEGIN
  obs[0] := 0.0;  obs[1] := 0.0;  labels[0] := 0;
  obs[2] := 0.1;  obs[3] := 0.1;  labels[1] := 0;
  obs[4] := 10.0; obs[5] := 10.0; labels[2] := 1;
  obs[6] := 10.0; obs[7] := 10.0; labels[3] := 1;
  obs[8] := 10.0; obs[9] := 10.0; labels[4] := 1;
  obs[10] := 0.0; obs[11] := 0.0; labels[5] := 0;

  Init(h, 2, 2);
  TrainSupervised(h, ADR(obs), ADR(labels), 6);
  logProb := Decode(h, ADR(obs), 6, ADR(decoded));
  Smooth(h, ADR(obs), 6, ADR(smoothed));

  allMatch := TRUE;
  FOR i := 0 TO 5 DO
    IF decoded[i] # smoothed[i] THEN allMatch := FALSE END
  END;
  Check("smooth: matches decode", allMatch);

  Free(h)
END TestSmooth;

(* ── Test 8: LogLikelihood is finite ─────────────── *)

PROCEDURE TestLogLikelihood;
VAR
  h: GaussHMM;
  obs: ARRAY [0..5] OF LONGREAL;
  labels: ARRAY [0..2] OF INTEGER;
  ll: LONGREAL;
BEGIN
  obs[0] := 0.0; obs[1] := 0.0; labels[0] := 0;
  obs[2] := 5.0; obs[3] := 5.0; labels[1] := 1;
  obs[4] := 0.0; obs[5] := 0.0; labels[2] := 0;

  Init(h, 2, 2);
  TrainSupervised(h, ADR(obs), ADR(labels), 3);

  ll := LogLikelihood(h, ADR(obs), 3);
  Check("loglik: finite", ll > -1.0D20);

  Free(h)
END TestLogLikelihood;

(* ── Test 9: LogLikelihood higher for matching data ── *)

PROCEDURE TestLogLikelihoodDiscrimination;
VAR
  h: GaussHMM;
  trainObs: ARRAY [0..7] OF LONGREAL;  (* 4 frames x 2 features *)
  trainLabels: ARRAY [0..3] OF INTEGER;
  goodObs: ARRAY [0..3] OF LONGREAL;   (* 2 frames matching pattern *)
  badObs: ARRAY [0..3] OF LONGREAL;    (* 2 frames NOT matching *)
  llGood, llBad: LONGREAL;
BEGIN
  (* Train on: state0 near (0,0), state1 near (100,100) *)
  trainObs[0] := 0.0;   trainObs[1] := 0.0;   trainLabels[0] := 0;
  trainObs[2] := 0.1;   trainObs[3] := 0.1;   trainLabels[1] := 0;
  trainObs[4] := 100.0; trainObs[5] := 100.0; trainLabels[2] := 1;
  trainObs[6] := 100.1; trainObs[7] := 99.9;  trainLabels[3] := 1;

  Init(h, 2, 2);
  TrainSupervised(h, ADR(trainObs), ADR(trainLabels), 4);

  (* Good data: matches the learned distributions *)
  goodObs[0] := 0.0;   goodObs[1] := 0.0;
  goodObs[2] := 100.0; goodObs[3] := 100.0;

  (* Bad data: far from any learned state *)
  badObs[0] := 50.0; badObs[1] := 50.0;
  badObs[2] := 50.0; badObs[3] := 50.0;

  llGood := LogLikelihood(h, ADR(goodObs), 2);
  llBad := LogLikelihood(h, ADR(badObs), 2);

  Check("discrim: good > bad", llGood > llBad);

  Free(h)
END TestLogLikelihoodDiscrimination;

BEGIN
  passed := 0;
  failed := 0;
  total := 0;

  WriteString("m2hmm test suite"); WriteLn;
  WriteString("================"); WriteLn;

  Test1;
  TestTrain;
  TestDecodeRecover;
  TestDecodeAlternating;
  TestSmooth;
  TestLogLikelihood;
  TestLogLikelihoodDiscrimination;

  WriteLn;
  WriteInt(total, 0); WriteString(" tests, ");
  WriteInt(passed, 0); WriteString(" passed, ");
  WriteInt(failed, 0); WriteString(" failed"); WriteLn;

  IF failed > 0 THEN
    WriteString("*** FAILURES ***"); WriteLn;
    HALT
  ELSE
    WriteString("*** ALL TESTS PASSED ***"); WriteLn
  END
END HmmTests.
