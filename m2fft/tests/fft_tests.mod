MODULE FftTests;
(* Deterministic test suite for m2fft.

   Tests:
     1. RealToComplex packing
     2. Forward FFT of DC signal (all 1s)
     3. Forward FFT of impulse
     4. Forward then Inverse roundtrip
     5. Magnitude of known signal
     6. PowerSpectrum of known signal
     7. 4-point FFT manual verification
     8. Parseval's theorem check *)

FROM InOut IMPORT WriteString, WriteLn, WriteInt;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM FFT IMPORT Forward, Inverse, Magnitude, PowerSpectrum,
                RealToComplex, NormalizedPowerSpectrum;

CONST
  Eps = 1.0E-6;

TYPE
  RealPtr = POINTER TO LONGREAL;

VAR
  passed, failed, total: INTEGER;

(* ── Helpers ──────────────────────────────────────── *)

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

PROCEDURE Abs(x: LONGREAL): LONGREAL;
BEGIN
  IF x < 0.0 THEN
    RETURN -x
  END;
  RETURN x
END Abs;

PROCEDURE CheckApprox(name: ARRAY OF CHAR;
                      got, expected: LONGREAL);
BEGIN
  INC(total);
  IF Abs(got - expected) < Eps THEN
    INC(passed)
  ELSE
    INC(failed);
    WriteString("FAIL: "); WriteString(name); WriteLn
  END
END CheckApprox;

PROCEDURE Get(base: ADDRESS; idx: CARDINAL): LONGREAL;
VAR p: RealPtr;
BEGIN
  p := RealPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(LONGREAL)));
  RETURN p^
END Get;

PROCEDURE Put(base: ADDRESS; idx: CARDINAL; val: LONGREAL);
VAR p: RealPtr;
BEGIN
  p := RealPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(LONGREAL)));
  p^ := val
END Put;

(* ── Test 1: RealToComplex packing ───────────────── *)

PROCEDURE TestRealToComplex;
VAR realBuf: ARRAY [0..3] OF LONGREAL;
    cplxBuf: ARRAY [0..7] OF LONGREAL;
BEGIN
  realBuf[0] := 1.0;
  realBuf[1] := 2.0;
  realBuf[2] := 3.0;
  realBuf[3] := 4.0;

  RealToComplex(ADR(realBuf), 4, ADR(cplxBuf));

  CheckApprox("r2c: re[0]", cplxBuf[0], 1.0);
  CheckApprox("r2c: im[0]", cplxBuf[1], 0.0);
  CheckApprox("r2c: re[1]", cplxBuf[2], 2.0);
  CheckApprox("r2c: im[1]", cplxBuf[3], 0.0);
  CheckApprox("r2c: re[2]", cplxBuf[4], 3.0);
  CheckApprox("r2c: im[2]", cplxBuf[5], 0.0);
  CheckApprox("r2c: re[3]", cplxBuf[6], 4.0);
  CheckApprox("r2c: im[3]", cplxBuf[7], 0.0)
END TestRealToComplex;

(* ── Test 2: DC signal FFT ───────────────────────── *)

PROCEDURE TestDC;
VAR data: ARRAY [0..15] OF LONGREAL;
    i: CARDINAL;
BEGIN
  (* 8-point FFT of all ones: DC bin = N, all others = 0 *)
  i := 0;
  WHILE i < 8 DO
    data[2 * i] := 1.0;
    data[2 * i + 1] := 0.0;
    INC(i)
  END;

  Forward(ADR(data), 8);

  CheckApprox("dc: bin0 re", data[0], 8.0);
  CheckApprox("dc: bin0 im", data[1], 0.0);

  i := 1;
  WHILE i < 8 DO
    CheckApprox("dc: bin re", data[2 * i], 0.0);
    CheckApprox("dc: bin im", data[2 * i + 1], 0.0);
    INC(i)
  END
END TestDC;

(* ── Test 3: Impulse FFT ─────────────────────────── *)

PROCEDURE TestImpulse;
VAR data: ARRAY [0..15] OF LONGREAL;
    mag: ARRAY [0..7] OF LONGREAL;
    i: CARDINAL;
BEGIN
  (* 8-point FFT of [1,0,0,...,0] — all magnitudes should be 1 *)
  i := 0;
  WHILE i < 16 DO
    data[i] := 0.0;
    INC(i)
  END;
  data[0] := 1.0;

  Forward(ADR(data), 8);
  Magnitude(ADR(data), 8, ADR(mag));

  i := 0;
  WHILE i < 8 DO
    CheckApprox("impulse: mag", mag[i], 1.0);
    INC(i)
  END
END TestImpulse;

(* ── Test 4: Forward-Inverse roundtrip ───────────── *)

PROCEDURE TestRoundtrip;
VAR data: ARRAY [0..15] OF LONGREAL;
    orig: ARRAY [0..15] OF LONGREAL;
    i: CARDINAL;
BEGIN
  (* 8-point signal: [1, 2, 3, 4, 5, 6, 7, 8] *)
  i := 0;
  WHILE i < 8 DO
    data[2 * i] := LFLOAT(i + 1);
    data[2 * i + 1] := 0.0;
    orig[2 * i] := LFLOAT(i + 1);
    orig[2 * i + 1] := 0.0;
    INC(i)
  END;

  Forward(ADR(data), 8);
  Inverse(ADR(data), 8);

  i := 0;
  WHILE i < 8 DO
    CheckApprox("rt: re", data[2 * i], orig[2 * i]);
    CheckApprox("rt: im", data[2 * i + 1], 0.0);
    INC(i)
  END
END TestRoundtrip;

(* ── Test 5: Magnitude of known signal ───────────── *)

PROCEDURE TestMagnitude;
VAR data: ARRAY [0..7] OF LONGREAL;
    mag: ARRAY [0..3] OF LONGREAL;
BEGIN
  (* 4-point: [3+4j, 1+0j, 0+0j, 0+0j] *)
  data[0] := 3.0; data[1] := 4.0;
  data[2] := 1.0; data[3] := 0.0;
  data[4] := 0.0; data[5] := 0.0;
  data[6] := 0.0; data[7] := 0.0;

  Magnitude(ADR(data), 4, ADR(mag));

  CheckApprox("mag: 3+4j", mag[0], 5.0);
  CheckApprox("mag: 1+0j", mag[1], 1.0);
  CheckApprox("mag: 0+0j a", mag[2], 0.0);
  CheckApprox("mag: 0+0j b", mag[3], 0.0)
END TestMagnitude;

(* ── Test 6: PowerSpectrum of known signal ────────── *)

PROCEDURE TestPowerSpectrum;
VAR data: ARRAY [0..7] OF LONGREAL;
    power: ARRAY [0..3] OF LONGREAL;
BEGIN
  (* 4-point: [3+4j, 1+0j, 0+2j, 0+0j] *)
  data[0] := 3.0; data[1] := 4.0;
  data[2] := 1.0; data[3] := 0.0;
  data[4] := 0.0; data[5] := 2.0;
  data[6] := 0.0; data[7] := 0.0;

  PowerSpectrum(ADR(data), 4, ADR(power));

  CheckApprox("pow: 3+4j", power[0], 25.0);
  CheckApprox("pow: 1+0j", power[1], 1.0);
  CheckApprox("pow: 0+2j", power[2], 4.0);
  CheckApprox("pow: 0+0j", power[3], 0.0)
END TestPowerSpectrum;

(* ── Test 7: 4-point FFT manual verification ──────── *)
(* Input x = [1, 2, 3, 4], W4 = exp(-j pi/2) = -j.
   X[0] = 10 + 0j
   X[1] = -2 + 2j
   X[2] = -2 + 0j
   X[3] = -2 - 2j *)

PROCEDURE TestManual4;
VAR data: ARRAY [0..7] OF LONGREAL;
BEGIN
  data[0] := 1.0; data[1] := 0.0;
  data[2] := 2.0; data[3] := 0.0;
  data[4] := 3.0; data[5] := 0.0;
  data[6] := 4.0; data[7] := 0.0;

  Forward(ADR(data), 4);

  CheckApprox("4pt: X[0] re", data[0], 10.0);
  CheckApprox("4pt: X[0] im", data[1], 0.0);
  CheckApprox("4pt: X[1] re", data[2], -2.0);
  CheckApprox("4pt: X[1] im", data[3], 2.0);
  CheckApprox("4pt: X[2] re", data[4], -2.0);
  CheckApprox("4pt: X[2] im", data[5], 0.0);
  CheckApprox("4pt: X[3] re", data[6], -2.0);
  CheckApprox("4pt: X[3] im", data[7], -2.0)
END TestManual4;

(* ── Test 8: Parseval's theorem ───────────────────── *)
(* Sum of |x[n]|^2 = (1/N) * Sum of |X[k]|^2 *)

PROCEDURE TestParseval;
VAR data: ARRAY [0..15] OF LONGREAL;
    orig: ARRAY [0..15] OF LONGREAL;
    timeEnergy, freqEnergy: LONGREAL;
    i: CARDINAL;
BEGIN
  (* 8-point signal *)
  data[0] := 1.0; data[1] := 0.0;
  data[2] := -2.0; data[3] := 0.0;
  data[4] := 3.0; data[5] := 0.0;
  data[6] := -4.0; data[7] := 0.0;
  data[8] := 5.0; data[9] := 0.0;
  data[10] := -1.0; data[11] := 0.0;
  data[12] := 2.0; data[13] := 0.0;
  data[14] := -3.0; data[15] := 0.0;

  (* save original for time-domain energy *)
  i := 0;
  WHILE i < 16 DO
    orig[i] := data[i];
    INC(i)
  END;

  (* time-domain energy: sum |x[n]|^2 *)
  timeEnergy := 0.0;
  i := 0;
  WHILE i < 8 DO
    timeEnergy := timeEnergy
                + orig[2 * i] * orig[2 * i]
                + orig[2 * i + 1] * orig[2 * i + 1];
    INC(i)
  END;

  Forward(ADR(data), 8);

  (* frequency-domain energy: (1/N) * sum |X[k]|^2 *)
  freqEnergy := 0.0;
  i := 0;
  WHILE i < 8 DO
    freqEnergy := freqEnergy
                + data[2 * i] * data[2 * i]
                + data[2 * i + 1] * data[2 * i + 1];
    INC(i)
  END;
  freqEnergy := freqEnergy / 8.0;

  CheckApprox("parseval: energy", freqEnergy, timeEnergy)
END TestParseval;

(* ── Main ─────────────────────────────────────────── *)

BEGIN
  passed := 0;
  failed := 0;
  total := 0;

  WriteString("m2fft test suite"); WriteLn;
  WriteString("================"); WriteLn;

  TestRealToComplex;
  TestDC;
  TestImpulse;
  TestRoundtrip;
  TestMagnitude;
  TestPowerSpectrum;
  TestManual4;
  TestParseval;

  WriteLn;
  WriteInt(total, 0); WriteString(" tests, ");
  WriteInt(passed, 0); WriteString(" passed, ");
  WriteInt(failed, 0); WriteString(" failed"); WriteLn;

  IF failed > 0 THEN
    WriteString("*** FAILURES ***"); WriteLn
  ELSE
    WriteString("*** ALL TESTS PASSED ***"); WriteLn
  END
END FftTests.
