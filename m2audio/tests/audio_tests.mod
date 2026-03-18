MODULE AudioTests;

FROM InOut IMPORT WriteString, WriteInt, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sin, cos;
FROM MathUtil IMPORT Pi, TwoPi;
FROM AudioIO IMPORT PreEmphasis;
FROM ShortFeats IMPORT NumFeatures, Extract, FreeFeatures, FeatureName;
IMPORT MidFeats;

CONST
  Eps = 1.0D-9;

TYPE
  RealPtr = POINTER TO LONGREAL;

VAR
  passed, failed, total: INTEGER;

PROCEDURE Abs(x: LONGREAL): LONGREAL;
BEGIN
  IF x < 0.0 THEN RETURN -x END;
  RETURN x
END Abs;

PROCEDURE Check(label: ARRAY OF CHAR; cond: BOOLEAN);
BEGIN
  INC(total);
  WriteString(label);
  IF cond THEN
    WriteString(" ... PASSED");
    INC(passed)
  ELSE
    WriteString(" ... FAILED");
    INC(failed)
  END;
  WriteLn
END Check;

PROCEDURE CheckApprox(label: ARRAY OF CHAR; got, expected: LONGREAL);
BEGIN
  Check(label, Abs(got - expected) < Eps)
END CheckApprox;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE Compare(VAR a, b: ARRAY OF CHAR): INTEGER;
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i <= HIGH(a)) AND (i <= HIGH(b)) AND (a[i] # 0C) AND (b[i] # 0C) DO
    IF a[i] < b[i] THEN RETURN -1
    ELSIF a[i] > b[i] THEN RETURN 1
    END;
    INC(i)
  END;
  IF (i <= HIGH(a)) AND (a[i] # 0C) THEN RETURN 1 END;
  IF (i <= HIGH(b)) AND (b[i] # 0C) THEN RETURN -1 END;
  RETURN 0
END Compare;

(* Test 1: PreEmphasis on known signal *)
PROCEDURE TestPreEmphasis;
VAR
  input: ARRAY [0..4] OF LONGREAL;
  output: ARRAY [0..4] OF LONGREAL;
BEGIN
  (* input = [1.0, 2.0, 3.0, 4.0, 5.0], coeff = 0.5 *)
  input[0] := 1.0; input[1] := 2.0; input[2] := 3.0;
  input[3] := 4.0; input[4] := 5.0;

  PreEmphasis(ADR(input), 5, 0.5, ADR(output));

  (* Expected: y[0]=1.0, y[1]=2.0-0.5*1.0=1.5,
     y[2]=3.0-0.5*2.0=2.0, y[3]=4.0-0.5*3.0=2.5,
     y[4]=5.0-0.5*4.0=3.0 *)
  CheckApprox("Test 1a: PreEmphasis y[0]", output[0], 1.0);
  CheckApprox("Test 1b: PreEmphasis y[1]", output[1], 1.5);
  CheckApprox("Test 1c: PreEmphasis y[2]", output[2], 2.0);
  CheckApprox("Test 1d: PreEmphasis y[3]", output[3], 2.5);
  CheckApprox("Test 1e: PreEmphasis y[4]", output[4], 3.0)
END TestPreEmphasis;

(* Test 2: ZCR of alternating signal [1,-1,1,-1,...] should be 1.0 *)
PROCEDURE TestZcrAlternating;
VAR
  signal: ARRAY [0..63] OF LONGREAL;
  feats: ADDRESS;
  numFrames: CARDINAL;
  ok: BOOLEAN;
  i: CARDINAL;
  p: RealPtr;
BEGIN
  FOR i := 0 TO 63 DO
    IF i MOD 2 = 0 THEN
      signal[i] := 1.0
    ELSE
      signal[i] := -1.0
    END
  END;

  (* Use a window that covers all 64 samples *)
  Extract(ADR(signal), 64, 8000,
          0.008, 0.008,
          feats, numFrames, ok);

  IF ok AND (numFrames >= 1) THEN
    p := Elem(feats, 0);
    CheckApprox("Test 2: ZCR of alternating signal = 1.0",
                p^, 1.0);
    FreeFeatures(feats, numFrames)
  ELSE
    Check("Test 2: ZCR alternating (extract failed)", FALSE)
  END
END TestZcrAlternating;

(* Test 3: ZCR of constant signal should be 0.0 *)
PROCEDURE TestZcrConstant;
VAR
  signal: ARRAY [0..63] OF LONGREAL;
  feats: ADDRESS;
  numFrames: CARDINAL;
  ok: BOOLEAN;
  i: CARDINAL;
  p: RealPtr;
BEGIN
  FOR i := 0 TO 63 DO
    signal[i] := 1.0
  END;

  Extract(ADR(signal), 64, 8000,
          0.008, 0.008,
          feats, numFrames, ok);

  IF ok AND (numFrames >= 1) THEN
    p := Elem(feats, 0);
    CheckApprox("Test 3: ZCR of constant signal = 0.0",
                p^, 0.0);
    FreeFeatures(feats, numFrames)
  ELSE
    Check("Test 3: ZCR constant (extract failed)", FALSE)
  END
END TestZcrConstant;

(* Test 4: Energy of known signal *)
PROCEDURE TestEnergy;
VAR
  signal: ARRAY [0..63] OF LONGREAL;
  feats: ADDRESS;
  numFrames: CARDINAL;
  ok: BOOLEAN;
  i: CARDINAL;
  p: RealPtr;
BEGIN
  (* All samples = 2.0 => energy = 4.0 *)
  FOR i := 0 TO 63 DO
    signal[i] := 2.0
  END;

  Extract(ADR(signal), 64, 8000,
          0.008, 0.008,
          feats, numFrames, ok);

  IF ok AND (numFrames >= 1) THEN
    p := Elem(feats, 1);
    CheckApprox("Test 4: Energy of constant 2.0 signal = 4.0",
                p^, 4.0);
    FreeFeatures(feats, numFrames)
  ELSE
    Check("Test 4: Energy (extract failed)", FALSE)
  END
END TestEnergy;

(* Test 5: Feature extraction on sine wave -- verify dimensionality *)
PROCEDURE TestSineDimensionality;
VAR
  signal: ADDRESS;
  feats: ADDRESS;
  numFrames: CARDINAL;
  ok: BOOLEAN;
  i, expectedFrames: CARDINAL;
  numSamples, sampleRate, winSamp, stepSamp: CARDINAL;
  p: RealPtr;
BEGIN
  numSamples := 8000;
  sampleRate := 8000;

  ALLOCATE(signal, numSamples * TSIZE(LONGREAL));

  (* Generate 440 Hz sine wave at 8000 Hz sample rate, 1 second *)
  FOR i := 0 TO numSamples - 1 DO
    p := Elem(signal, i);
    p^ := LFLOAT(sin(FLOAT(TwoPi * 440.0 * LFLOAT(i) / LFLOAT(sampleRate))))
  END;

  (* Window = 0.05s = 400 samples, step = 0.025s = 200 samples *)
  Extract(signal, numSamples, sampleRate,
          0.05, 0.025,
          feats, numFrames, ok);

  Check("Test 5a: Sine extract ok", ok);

  (* Expected frames: (8000 - 400) / 200 + 1 = 39 *)
  winSamp := 400;
  stepSamp := 200;
  expectedFrames := (numSamples - winSamp) DIV stepSamp + 1;
  Check("Test 5b: Sine numFrames correct",
        numFrames = expectedFrames);

  (* Verify all feature values are finite (not NaN):
     a simple check is that the value equals itself *)
  IF ok AND (numFrames > 0) THEN
    ok := TRUE;
    FOR i := 0 TO NumFeatures - 1 DO
      p := Elem(feats, i);
      IF p^ # p^ THEN
        ok := FALSE
      END
    END;
    Check("Test 5c: First frame features are finite", ok)
  END;

  IF feats # NIL THEN FreeFeatures(feats, numFrames) END;
  DEALLOCATE(signal, numSamples * TSIZE(LONGREAL))
END TestSineDimensionality;

(* Test 6: FeatureName returns correct names *)
PROCEDURE TestFeatureNames;
VAR
  buf: ARRAY [0..63] OF CHAR;
BEGIN
  FeatureName(0, buf);
  Check("Test 6a: FeatureName(0) = Zero Crossing Rate",
        Compare(buf, "Zero Crossing Rate") = 0);

  FeatureName(1, buf);
  Check("Test 6b: FeatureName(1) = Energy",
        Compare(buf, "Energy") = 0);

  FeatureName(8, buf);
  Check("Test 6c: FeatureName(8) = MFCC 1",
        Compare(buf, "MFCC 1") = 0);

  FeatureName(20, buf);
  Check("Test 6d: FeatureName(20) = MFCC 13",
        Compare(buf, "MFCC 13") = 0);

  FeatureName(21, buf);
  Check("Test 6e: FeatureName(21) = Chroma 1",
        Compare(buf, "Chroma 1") = 0);

  FeatureName(33, buf);
  Check("Test 6f: FeatureName(33) = Chroma Std Dev",
        Compare(buf, "Chroma Std Dev") = 0)
END TestFeatureNames;

(* Test 7: MidFeats dimensionality check *)
PROCEDURE TestMidFeatsDimensionality;
VAR
  shortFeats, midFeats: ADDRESS;
  numShortFrames, numMidFrames: CARDINAL;
  numF, midWin, midStep: CARDINAL;
  ok: BOOLEAN;
  i: CARDINAL;
  p: RealPtr;
  expectedMidFrames: CARDINAL;
BEGIN
  numF := 4;
  numShortFrames := 20;
  midWin := 10;
  midStep := 5;

  (* Create synthetic short-term feature matrix: 20 frames x 4 features *)
  ALLOCATE(shortFeats, numShortFrames * numF * TSIZE(LONGREAL));
  FOR i := 0 TO numShortFrames * numF - 1 DO
    p := Elem(shortFeats, i);
    p^ := LFLOAT(i MOD 10) + 1.0
  END;

  MidFeats.Extract(shortFeats, numShortFrames, numF,
                   midWin, midStep,
                   midFeats, numMidFrames, ok);

  Check("Test 7a: MidFeats extract ok", ok);

  (* Expected: (20 - 10) / 5 + 1 = 3 mid frames *)
  expectedMidFrames := (numShortFrames - midWin) DIV midStep + 1;
  Check("Test 7b: MidFeats numMidFrames correct",
        numMidFrames = expectedMidFrames);

  IF ok AND (numMidFrames > 0) THEN
    (* Check that means are reasonable (> 0) *)
    p := Elem(midFeats, 0);
    Check("Test 7c: MidFeats first mean > 0", p^ > 0.0)
  END;

  IF midFeats # NIL THEN MidFeats.FreeMidFeatures(midFeats, numMidFrames, numF) END;
  DEALLOCATE(shortFeats, numShortFrames * numF * TSIZE(LONGREAL))
END TestMidFeatsDimensionality;

(* Test 8: Hamming window symmetry *)
PROCEDURE TestHammingSymmetry;
VAR
  i: CARDINAL;
  n: CARDINAL;
  w1, w2: LONGREAL;
  symmetric: BOOLEAN;
BEGIN
  n := 16;

  (* Hamming window: w[i] = 0.54 - 0.46 * cos(2*pi*i/(N-1))
     Verify symmetry: w[i] = w[N-1-i] *)
  symmetric := TRUE;
  FOR i := 0 TO (n DIV 2) - 1 DO
    w1 := 0.54 - 0.46 * LFLOAT(cos(FLOAT(TwoPi * LFLOAT(i) / LFLOAT(n - 1))));
    w2 := 0.54 - 0.46 * LFLOAT(cos(FLOAT(TwoPi * LFLOAT(n - 1 - i) / LFLOAT(n - 1))));
    IF Abs(w1 - w2) >= Eps THEN
      symmetric := FALSE
    END
  END;
  Check("Test 8a: Hamming window is symmetric", symmetric);

  (* Hamming window endpoints should be 0.08 *)
  w1 := 0.54 - 0.46 * cos(0.0);
  CheckApprox("Test 8b: Hamming window endpoint = 0.08",
              w1, 0.08);

  (* Hamming window midpoint should be 1.0 *)
  w1 := 0.54 - 0.46 * cos(Pi);
  CheckApprox("Test 8c: Hamming window midpoint = 1.0",
              w1, 1.0)
END TestHammingSymmetry;

BEGIN
  passed := 0;
  failed := 0;
  total := 0;

  WriteString("=== m2audio test suite ==="); WriteLn;
  WriteLn;

  TestPreEmphasis;
  TestZcrAlternating;
  TestZcrConstant;
  TestEnergy;
  TestSineDimensionality;
  TestFeatureNames;
  TestMidFeatsDimensionality;
  TestHammingSymmetry;

  WriteLn;
  WriteString("=== Results: ");
  WriteInt(passed, 1);
  WriteString(" passed, ");
  WriteInt(failed, 1);
  WriteString(" failed, ");
  WriteInt(total, 1);
  WriteString(" total ===");
  WriteLn;

  IF failed # 0 THEN
    HALT
  END
END AudioTests.
