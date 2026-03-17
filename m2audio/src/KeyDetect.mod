IMPLEMENTATION MODULE KeyDetect;
(* Krumhansl-Schmuckler key-finding algorithm.
   Correlates averaged chroma vector against 24 key profiles
   (12 major + 12 minor) and picks the best match. *)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;
FROM Strings IMPORT Assign;
FROM Spectro IMPORT ComputeChromagram, FreeSpectro;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

(* Krumhansl-Kessler major and minor profiles *)
CONST
  (* Major key profile (C major template) *)
  MajC0 = 6.35;  MajC1 = 2.23;  MajC2 = 3.48;
  MajC3 = 2.33;  MajC4 = 4.38;  MajC5 = 4.09;
  MajC6 = 2.52;  MajC7 = 5.19;  MajC8 = 2.39;
  MajC9 = 3.66;  MajC10 = 2.29; MajC11 = 2.88;

  (* Minor key profile (C minor template) *)
  MinC0 = 6.33;  MinC1 = 2.68;  MinC2 = 3.52;
  MinC3 = 5.38;  MinC4 = 2.60;  MinC5 = 3.53;
  MinC6 = 2.54;  MinC7 = 4.75;  MinC8 = 3.98;
  MinC9 = 2.69;  MinC10 = 3.34; MinC11 = 3.17;

VAR
  majorProfile: ARRAY [0..11] OF LONGREAL;
  minorProfile: ARRAY [0..11] OF LONGREAL;

(* Pearson correlation between two 12-element arrays *)
PROCEDURE Correlate(a, b: ARRAY OF LONGREAL): LONGREAL;
VAR
  i: CARDINAL;
  meanA, meanB, sumAB, sumAA, sumBB, dA, dB, denom: LONGREAL;
BEGIN
  meanA := 0.0; meanB := 0.0;
  FOR i := 0 TO 11 DO
    meanA := meanA + a[i];
    meanB := meanB + b[i]
  END;
  meanA := meanA / 12.0;
  meanB := meanB / 12.0;

  sumAB := 0.0; sumAA := 0.0; sumBB := 0.0;
  FOR i := 0 TO 11 DO
    dA := a[i] - meanA;
    dB := b[i] - meanB;
    sumAB := sumAB + dA * dB;
    sumAA := sumAA + dA * dA;
    sumBB := sumBB + dB * dB
  END;

  denom := LFLOAT(sqrt(FLOAT(sumAA))) * LFLOAT(sqrt(FLOAT(sumBB)));
  IF denom < 1.0D-10 THEN RETURN 0.0 END;
  RETURN sumAB / denom
END Correlate;

PROCEDURE DetectKey(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                    VAR keyName: ARRAY OF CHAR;
                    VAR confidence: LONGREAL);
VAR
  chroma: ADDRESS;
  numFrames, t, c, shift: CARDINAL;
  avgChroma: ARRAY [0..11] OF LONGREAL;
  rotated: ARRAY [0..11] OF LONGREAL;
  corr, bestCorr: LONGREAL;
  bestShift, bestMode: CARDINAL;
  p: RealPtr;
  names: ARRAY [0..23] OF ARRAY [0..15] OF CHAR;
BEGIN
  confidence := 0.0;
  Assign("Unknown", keyName);

  (* Compute chromagram *)
  ComputeChromagram(signal, numSamples, sampleRate, 0.050, 0.025,
                     chroma, numFrames);
  IF numFrames = 0 THEN RETURN END;

  (* Average chroma across all frames *)
  FOR c := 0 TO 11 DO avgChroma[c] := 0.0 END;

  FOR t := 0 TO numFrames - 1 DO
    FOR c := 0 TO 11 DO
      p := Elem(chroma, t * 12 + c);
      avgChroma[c] := avgChroma[c] + p^
    END
  END;

  FOR c := 0 TO 11 DO
    avgChroma[c] := avgChroma[c] / LFLOAT(numFrames)
  END;

  FreeSpectro(chroma);

  (* Key names: chroma order is A, A#, B, C, C#, D, D#, E, F, F#, G, G# *)
  Assign("A major", names[0]);
  Assign("A# major", names[1]);
  Assign("B major", names[2]);
  Assign("C major", names[3]);
  Assign("C# major", names[4]);
  Assign("D major", names[5]);
  Assign("D# major", names[6]);
  Assign("E major", names[7]);
  Assign("F major", names[8]);
  Assign("F# major", names[9]);
  Assign("G major", names[10]);
  Assign("G# major", names[11]);
  Assign("A minor", names[12]);
  Assign("A# minor", names[13]);
  Assign("B minor", names[14]);
  Assign("C minor", names[15]);
  Assign("C# minor", names[16]);
  Assign("D minor", names[17]);
  Assign("D# minor", names[18]);
  Assign("E minor", names[19]);
  Assign("F minor", names[20]);
  Assign("F# minor", names[21]);
  Assign("G minor", names[22]);
  Assign("G# minor", names[23]);

  (* Try all 24 keys (12 shifts x 2 modes) *)
  bestCorr := -2.0;
  bestShift := 0;
  bestMode := 0;

  FOR shift := 0 TO 11 DO
    (* Rotate chroma by shift positions *)
    FOR c := 0 TO 11 DO
      rotated[c] := avgChroma[(c + shift) MOD 12]
    END;

    (* Major correlation *)
    corr := Correlate(rotated, majorProfile);
    IF corr > bestCorr THEN
      bestCorr := corr;
      bestShift := shift;
      bestMode := 0
    END;

    (* Minor correlation *)
    corr := Correlate(rotated, minorProfile);
    IF corr > bestCorr THEN
      bestCorr := corr;
      bestShift := shift;
      bestMode := 1
    END
  END;

  confidence := bestCorr;
  IF confidence < 0.0 THEN confidence := 0.0 END;

  Assign(names[bestShift + bestMode * 12], keyName)
END DetectKey;

BEGIN
  (* Initialize profiles *)
  majorProfile[0] := MajC0; majorProfile[1] := MajC1;
  majorProfile[2] := MajC2; majorProfile[3] := MajC3;
  majorProfile[4] := MajC4; majorProfile[5] := MajC5;
  majorProfile[6] := MajC6; majorProfile[7] := MajC7;
  majorProfile[8] := MajC8; majorProfile[9] := MajC9;
  majorProfile[10] := MajC10; majorProfile[11] := MajC11;

  minorProfile[0] := MinC0; minorProfile[1] := MinC1;
  minorProfile[2] := MinC2; minorProfile[3] := MinC3;
  minorProfile[4] := MinC4; minorProfile[5] := MinC5;
  minorProfile[6] := MinC6; minorProfile[7] := MinC7;
  minorProfile[8] := MinC8; minorProfile[9] := MinC9;
  minorProfile[10] := MinC10; minorProfile[11] := MinC11
END KeyDetect.
