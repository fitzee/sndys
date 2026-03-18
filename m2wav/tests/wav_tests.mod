MODULE WavTests;

FROM InOut IMPORT WriteString, WriteInt, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sin;
FROM Wav IMPORT WavInfo, ReadWav, FreeWav, WriteWav, GetDuration,
                StereoToMono, FreeMono;

CONST
  Pi = 3.14159265358979323846D0;
  Epsilon = 0.005D0;
  TestPath16 = "/tmp/test_m2wav_16.wav";
  TestPath8 = "/tmp/test_m2wav_8.wav";
  TestPathStereo = "/tmp/test_m2wav_stereo.wav";
  TestPathBad = "/tmp/nonexistent_m2wav_test.wav";

TYPE
  LongRealPtr = POINTER TO LONGREAL;

VAR
  passed, failed, total: INTEGER;

PROCEDURE SetElem(base: ADDRESS; idx: CARDINAL; val: LONGREAL);
VAR
  p: LongRealPtr;
  addr: LONGCARD;
BEGIN
  addr := LONGCARD(base) + LONGCARD(idx) * LONGCARD(TSIZE(LONGREAL));
  p := LongRealPtr(addr);
  p^ := val
END SetElem;

PROCEDURE GetElem(base: ADDRESS; idx: CARDINAL): LONGREAL;
VAR
  p: LongRealPtr;
  addr: LONGCARD;
BEGIN
  addr := LONGCARD(base) + LONGCARD(idx) * LONGCARD(TSIZE(LONGREAL));
  p := LongRealPtr(addr);
  RETURN p^
END GetElem;

PROCEDURE FAbs(x: LONGREAL): LONGREAL;
BEGIN
  IF x < 0.0D0 THEN
    RETURN -x
  END;
  RETURN x
END FAbs;

PROCEDURE Check(name: ARRAY OF CHAR; cond: BOOLEAN);
BEGIN
  INC(total);
  IF cond THEN
    INC(passed);
    WriteString("  PASS: ");
    WriteString(name);
    WriteLn
  ELSE
    INC(failed);
    WriteString("  FAIL: ");
    WriteString(name);
    WriteLn
  END
END Check;

PROCEDURE CheckApprox(name: ARRAY OF CHAR; got, expected, eps: LONGREAL);
BEGIN
  Check(name, FAbs(got - expected) < eps)
END CheckApprox;

(* Test 1: 16-bit write then read roundtrip *)
PROCEDURE TestRoundtrip16;
VAR
  samples, readSamples: ADDRESS;
  info: WavInfo;
  ok: BOOLEAN;
  i, numSamples, sampleRate: CARDINAL;
  val, readVal: LONGREAL;
  allClose: BOOLEAN;
BEGIN
  WriteString("Test 1: 16-bit roundtrip"); WriteLn;
  numSamples := 1000;
  sampleRate := 44100;

  (* Generate a 440 Hz sine wave *)
  ALLOCATE(samples, numSamples * TSIZE(LONGREAL));
  FOR i := 0 TO numSamples - 1 DO
    val := LFLOAT(sin(FLOAT(2.0D0 * Pi * 440.0D0 * LFLOAT(i) / LFLOAT(sampleRate))));
    SetElem(samples, i, val)
  END;

  (* Write *)
  WriteWav(TestPath16, samples, numSamples, sampleRate, 1, 16, ok);
  Check("WriteWav 16-bit succeeds", ok);

  (* Read back *)
  ReadWav(TestPath16, info, readSamples, ok);
  Check("ReadWav 16-bit succeeds", ok);
  Check("numSamples matches", info.numSamples = numSamples);
  Check("sampleRate matches", info.sampleRate = sampleRate);
  Check("numChannels = 1", info.numChannels = 1);
  Check("bitsPerSample = 16", info.bitsPerSample = 16);

  (* Compare samples within epsilon (quantization error) *)
  allClose := TRUE;
  IF ok THEN
    FOR i := 0 TO numSamples - 1 DO
      readVal := GetElem(readSamples, i);
      val := LFLOAT(sin(FLOAT(2.0D0 * Pi * 440.0D0 * LFLOAT(i) / LFLOAT(sampleRate))));
      IF FAbs(readVal - val) > Epsilon THEN
        allClose := FALSE
      END
    END
  ELSE
    allClose := FALSE
  END;
  Check("samples match within epsilon", allClose);

  DEALLOCATE(samples, numSamples * TSIZE(LONGREAL));
  IF readSamples # NIL THEN
    FreeWav(readSamples, info.numSamples * info.numChannels)
  END
END TestRoundtrip16;

(* Test 2: WavInfo fields correct *)
PROCEDURE TestWavInfo;
VAR
  samples, readSamples: ADDRESS;
  info: WavInfo;
  ok: BOOLEAN;
  numSamples, sampleRate: CARDINAL;
  i: CARDINAL;
BEGIN
  WriteString("Test 2: WavInfo fields"); WriteLn;
  numSamples := 500;
  sampleRate := 22050;

  ALLOCATE(samples, numSamples * TSIZE(LONGREAL));
  FOR i := 0 TO numSamples - 1 DO
    SetElem(samples, i, 0.0D0)
  END;

  WriteWav(TestPath16, samples, numSamples, sampleRate, 1, 16, ok);
  Check("write silent WAV", ok);

  ReadWav(TestPath16, info, readSamples, ok);
  Check("read silent WAV", ok);
  Check("sampleRate = 22050", info.sampleRate = 22050);
  Check("numChannels = 1", info.numChannels = 1);
  Check("bitsPerSample = 16", info.bitsPerSample = 16);
  Check("numSamples = 500", info.numSamples = 500);
  Check("dataSize = 1000", info.dataSize = 1000);

  DEALLOCATE(samples, numSamples * TSIZE(LONGREAL));
  IF readSamples # NIL THEN
    FreeWav(readSamples, info.numSamples * info.numChannels)
  END
END TestWavInfo;

(* Test 3: GetDuration calculation *)
PROCEDURE TestGetDuration;
VAR
  info: WavInfo;
  dur: LONGREAL;
BEGIN
  WriteString("Test 3: GetDuration"); WriteLn;

  info.sampleRate := 44100;
  info.numChannels := 1;
  info.bitsPerSample := 16;
  info.numSamples := 44100;
  info.dataSize := 88200;

  dur := GetDuration(info);
  CheckApprox("duration = 1.0s", dur, 1.0D0, 0.0001D0);

  info.numSamples := 22050;
  dur := GetDuration(info);
  CheckApprox("duration = 0.5s", dur, 0.5D0, 0.0001D0);

  info.sampleRate := 48000;
  info.numSamples := 96000;
  dur := GetDuration(info);
  CheckApprox("duration = 2.0s", dur, 2.0D0, 0.0001D0)
END TestGetDuration;

(* Test 4: StereoToMono averaging *)
PROCEDURE TestStereoToMono;
VAR
  stereo, mono: ADDRESS;
  numFrames, i: CARDINAL;
  val: LONGREAL;
  allOk: BOOLEAN;
BEGIN
  WriteString("Test 4: StereoToMono"); WriteLn;
  numFrames := 100;

  (* Create stereo buffer: L=0.6, R=0.4 for each frame *)
  ALLOCATE(stereo, numFrames * 2 * TSIZE(LONGREAL));
  FOR i := 0 TO numFrames - 1 DO
    SetElem(stereo, i * 2, 0.6D0);
    SetElem(stereo, i * 2 + 1, 0.4D0)
  END;

  StereoToMono(stereo, numFrames, mono);

  allOk := TRUE;
  FOR i := 0 TO numFrames - 1 DO
    val := GetElem(mono, i);
    IF FAbs(val - 0.5D0) > 0.0001D0 THEN
      allOk := FALSE
    END
  END;
  Check("mono values = 0.5 (avg of 0.6 and 0.4)", allOk);

  (* Test with varying values *)
  SetElem(stereo, 0, 1.0D0);
  SetElem(stereo, 1, -1.0D0);
  FreeMono(mono, numFrames);
  StereoToMono(stereo, numFrames, mono);
  val := GetElem(mono, 0);
  CheckApprox("avg(1.0, -1.0) = 0.0", val, 0.0D0, 0.0001D0);

  FreeMono(mono, numFrames);
  DEALLOCATE(stereo, numFrames * 2 * TSIZE(LONGREAL))
END TestStereoToMono;

(* Test 5: Invalid file path returns ok=FALSE *)
PROCEDURE TestInvalidPath;
VAR
  info: WavInfo;
  samples: ADDRESS;
  ok: BOOLEAN;
BEGIN
  WriteString("Test 5: Invalid path"); WriteLn;
  ReadWav(TestPathBad, info, samples, ok);
  Check("invalid path returns ok=FALSE", NOT ok);
  Check("samples is NIL on failure", samples = NIL)
END TestInvalidPath;

(* Test 6: 8-bit roundtrip *)
PROCEDURE TestRoundtrip8;
VAR
  samples, readSamples: ADDRESS;
  info: WavInfo;
  ok: BOOLEAN;
  i, numSamples, sampleRate: CARDINAL;
  val, readVal: LONGREAL;
  allClose: BOOLEAN;
BEGIN
  WriteString("Test 6: 8-bit roundtrip"); WriteLn;
  numSamples := 500;
  sampleRate := 22050;

  ALLOCATE(samples, numSamples * TSIZE(LONGREAL));
  FOR i := 0 TO numSamples - 1 DO
    val := LFLOAT(sin(FLOAT(2.0D0 * Pi * 440.0D0 * LFLOAT(i) / LFLOAT(sampleRate))));
    SetElem(samples, i, val)
  END;

  WriteWav(TestPath8, samples, numSamples, sampleRate, 1, 8, ok);
  Check("WriteWav 8-bit succeeds", ok);

  ReadWav(TestPath8, info, readSamples, ok);
  Check("ReadWav 8-bit succeeds", ok);
  Check("8-bit numSamples matches", info.numSamples = numSamples);
  Check("8-bit bitsPerSample = 8", info.bitsPerSample = 8);

  (* 8-bit has lower precision, use larger epsilon *)
  allClose := TRUE;
  IF ok THEN
    FOR i := 0 TO numSamples - 1 DO
      readVal := GetElem(readSamples, i);
      val := LFLOAT(sin(FLOAT(2.0D0 * Pi * 440.0D0 * LFLOAT(i) / LFLOAT(sampleRate))));
      IF FAbs(readVal - val) > 0.02D0 THEN
        allClose := FALSE
      END
    END
  ELSE
    allClose := FALSE
  END;
  Check("8-bit samples match within epsilon", allClose);

  DEALLOCATE(samples, numSamples * TSIZE(LONGREAL));
  IF readSamples # NIL THEN
    FreeWav(readSamples, info.numSamples * info.numChannels)
  END
END TestRoundtrip8;

(* Test 7: Stereo write/read roundtrip *)
PROCEDURE TestStereoRoundtrip;
VAR
  samples, readSamples: ADDRESS;
  info: WavInfo;
  ok: BOOLEAN;
  numFrames, sampleRate, i: CARDINAL;
  lVal, rVal: LONGREAL;
  allClose: BOOLEAN;
BEGIN
  WriteString("Test 7: Stereo roundtrip"); WriteLn;
  numFrames := 200;
  sampleRate := 44100;

  ALLOCATE(samples, numFrames * 2 * TSIZE(LONGREAL));
  FOR i := 0 TO numFrames - 1 DO
    lVal := LFLOAT(sin(FLOAT(2.0D0 * Pi * 440.0D0 * LFLOAT(i) / LFLOAT(sampleRate))));
    rVal := LFLOAT(sin(FLOAT(2.0D0 * Pi * 880.0D0 * LFLOAT(i) / LFLOAT(sampleRate))));
    SetElem(samples, i * 2, lVal);
    SetElem(samples, i * 2 + 1, rVal)
  END;

  WriteWav(TestPathStereo, samples, numFrames, sampleRate, 2, 16, ok);
  Check("WriteWav stereo succeeds", ok);

  ReadWav(TestPathStereo, info, readSamples, ok);
  Check("ReadWav stereo succeeds", ok);
  Check("stereo numChannels = 2", info.numChannels = 2);
  Check("stereo numSamples matches", info.numSamples = numFrames);

  allClose := TRUE;
  IF ok THEN
    FOR i := 0 TO numFrames - 1 DO
      lVal := LFLOAT(sin(FLOAT(2.0D0 * Pi * 440.0D0 * LFLOAT(i) / LFLOAT(sampleRate))));
      rVal := LFLOAT(sin(FLOAT(2.0D0 * Pi * 880.0D0 * LFLOAT(i) / LFLOAT(sampleRate))));
      IF FAbs(GetElem(readSamples, i * 2) - lVal) > Epsilon THEN
        allClose := FALSE
      END;
      IF FAbs(GetElem(readSamples, i * 2 + 1) - rVal) > Epsilon THEN
        allClose := FALSE
      END
    END
  ELSE
    allClose := FALSE
  END;
  Check("stereo samples match within epsilon", allClose);

  DEALLOCATE(samples, numFrames * 2 * TSIZE(LONGREAL));
  IF readSamples # NIL THEN
    FreeWav(readSamples, info.numSamples * info.numChannels)
  END
END TestStereoRoundtrip;

BEGIN
  passed := 0;
  failed := 0;
  total := 0;

  WriteString("=== m2wav test suite ==="); WriteLn;
  WriteLn;

  TestRoundtrip16;
  WriteLn;
  TestWavInfo;
  WriteLn;
  TestGetDuration;
  WriteLn;
  TestStereoToMono;
  WriteLn;
  TestInvalidPath;
  WriteLn;
  TestRoundtrip8;
  WriteLn;
  TestStereoRoundtrip;
  WriteLn;

  WriteString("=== Results: ");
  WriteInt(passed, 1);
  WriteString(" passed, ");
  WriteInt(failed, 1);
  WriteString(" failed, ");
  WriteInt(total, 1);
  WriteString(" total ===");
  WriteLn;

  IF failed > 0 THEN
    HALT
  END
END WavTests.
