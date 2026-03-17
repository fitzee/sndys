IMPLEMENTATION MODULE Waveform;
(* Renders a signal as ASCII art by computing min/max per column
   and drawing vertical bars. *)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM InOut IMPORT WriteString, Write, WriteLn;
FROM MathUtil IMPORT FAbs;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE DrawWaveform(signal: ADDRESS; numSamples: CARDINAL;
                       width, height: CARDINAL);
VAR
  col, row, i: CARDINAL;
  startIdx, endIdx, samplesPerCol: CARDINAL;
  minVal, maxVal, val: LONGREAL;
  minRow, maxRow, midRow: CARDINAL;
  p: RealPtr;
  ch: CHAR;
BEGIN
  IF (numSamples = 0) OR (width = 0) OR (height = 0) THEN RETURN END;

  samplesPerCol := numSamples DIV width;
  IF samplesPerCol = 0 THEN samplesPerCol := 1 END;
  midRow := height DIV 2;

  (* Draw row by row, top to bottom *)
  FOR row := 0 TO height - 1 DO
    FOR col := 0 TO width - 1 DO
      startIdx := col * samplesPerCol;
      endIdx := startIdx + samplesPerCol;
      IF endIdx > numSamples THEN endIdx := numSamples END;

      (* Find min/max in this column's sample range *)
      minVal := 0.0;
      maxVal := 0.0;
      FOR i := startIdx TO endIdx - 1 DO
        p := Elem(signal, i);
        val := p^;
        IF val < minVal THEN minVal := val END;
        IF val > maxVal THEN maxVal := val END
      END;

      (* Map min/max to row indices.
         Row 0 = top = +1.0, row height-1 = bottom = -1.0 *)
      IF maxVal > 1.0 THEN maxVal := 1.0 END;
      IF minVal < -1.0 THEN minVal := -1.0 END;

      (* Top row of the waveform bar for this column *)
      minRow := TRUNC((1.0 - maxVal) * LFLOAT(height - 1) / 2.0 + 0.5);
      (* Bottom row of the waveform bar *)
      maxRow := TRUNC((1.0 - minVal) * LFLOAT(height - 1) / 2.0 + 0.5);
      IF maxRow >= height THEN maxRow := height - 1 END;

      (* Draw character for this cell *)
      IF (row >= minRow) AND (row <= maxRow) THEN
        IF row = midRow THEN
          Write('=')
        ELSE
          Write('|')
        END
      ELSIF row = midRow THEN
        Write('-')
      ELSE
        Write(' ')
      END
    END;
    WriteLn
  END
END DrawWaveform;

END Waveform.
