IMPLEMENTATION MODULE Thumbnail;
(* Self-similarity matrix + diagonal convolution.
   Matches pyAudioAnalysis music_thumbnailing approach. *)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

(* Cosine similarity between two feature vectors *)
PROCEDURE CosineSim(a, b: ADDRESS; aOff, bOff, nFeats: CARDINAL): LONGREAL;
VAR
  f: CARDINAL;
  dot, normA, normB: LONGREAL;
  pa, pb: RealPtr;
BEGIN
  dot := 0.0;
  normA := 0.0;
  normB := 0.0;
  FOR f := 0 TO nFeats - 1 DO
    pa := Elem(a, aOff + f);
    pb := Elem(b, bOff + f);
    dot := dot + pa^ * pb^;
    normA := normA + pa^ * pa^;
    normB := normB + pb^ * pb^
  END;
  normA := LFLOAT(sqrt(FLOAT(normA)));
  normB := LFLOAT(sqrt(FLOAT(normB)));
  IF (normA < 1.0D-10) OR (normB < 1.0D-10) THEN RETURN 0.0 END;
  RETURN dot / (normA * normB)
END CosineSim;

PROCEDURE FindThumbnail(featureMatrix: ADDRESS;
                         numFrames, numFeatures: CARDINAL;
                         thumbDurationFrames: CARDINAL;
                         VAR startFrame: CARDINAL;
                         VAR score: LONGREAL);
VAR
  i, j, d, thumbLen: CARDINAL;
  diagSum, bestSum: LONGREAL;
  bestPos: CARDINAL;
  sim: LONGREAL;
BEGIN
  startFrame := 0;
  score := 0.0;

  IF (numFrames < 2) OR (thumbDurationFrames = 0) THEN RETURN END;

  thumbLen := thumbDurationFrames;
  IF thumbLen >= numFrames THEN thumbLen := numFrames - 1 END;

  (* For each possible starting position, compute the average
     self-similarity along the diagonal of length thumbLen.
     This measures how well the segment at position i matches
     the rest of the audio. *)
  bestSum := -1.0;
  bestPos := 0;

  FOR i := 0 TO numFrames - thumbLen - 1 DO
    diagSum := 0.0;

    (* Average similarity between segment [i..i+thumbLen-1]
       and all other non-overlapping positions *)
    FOR j := 0 TO numFrames - thumbLen - 1 DO
      IF j # i THEN
        (* Average cosine similarity along the diagonal *)
        sim := 0.0;
        FOR d := 0 TO thumbLen - 1 DO
          sim := sim + CosineSim(featureMatrix, featureMatrix,
                                 (i + d) * numFeatures,
                                 (j + d) * numFeatures,
                                 numFeatures)
        END;
        diagSum := diagSum + sim / LFLOAT(thumbLen)
      END
    END;

    IF diagSum > bestSum THEN
      bestSum := diagSum;
      bestPos := i
    END
  END;

  startFrame := bestPos;
  IF numFrames > thumbLen + 1 THEN
    score := bestSum / LFLOAT(numFrames - thumbLen - 1)
  ELSE
    score := bestSum
  END
END FindThumbnail;

END Thumbnail.
