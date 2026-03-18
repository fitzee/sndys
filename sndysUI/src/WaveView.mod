IMPLEMENTATION MODULE WaveView;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Gfx IMPORT Renderer;
FROM Canvas IMPORT SetColor, FillRect, DrawLine, DrawRect;
FROM Color IMPORT UnpackR, UnpackG, UnpackB;
FROM UI IMPORT colBg, colWave, colSelection, colGrid, colBorder,
               colAccent, colTextDim, SetCol;
FROM MathLib IMPORT ln, exp;
FROM MathUtil IMPORT FAbs;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END Elem;

(* ── Waveform ─────────────────────────────────────────── *)

PROCEDURE Draw(ren: Renderer;
               x, y, w, h: INTEGER;
               signal: ADDRESS; numSamples: CARDINAL;
               selStart, selEnd: CARDINAL);
VAR
  col, midY: INTEGER;
  samplesPerCol: CARDINAL;
  startIdx, endIdx, i: CARDINAL;
  minVal, maxVal, val: LONGREAL;
  topY, botY: INTEGER;
  p: RealPtr;
  inSel: BOOLEAN;
  selPixStart, selPixEnd: INTEGER;
BEGIN
  (* Background *)
  SetCol(ren, colBg);
  FillRect(ren, x, y, w, h);

  IF (numSamples = 0) OR (signal = NIL) OR (w <= 0) OR (h <= 0) THEN
    RETURN
  END;

  midY := y + h DIV 2;

  (* Draw center line *)
  SetCol(ren, colGrid);
  DrawLine(ren, x, midY, x + w - 1, midY);

  (* Draw selection background *)
  IF selStart # selEnd THEN
    selPixStart := x + INTEGER((LONGCARD(selStart) * LONGCARD(w)) DIV LONGCARD(numSamples));
    selPixEnd := x + INTEGER((LONGCARD(selEnd) * LONGCARD(w)) DIV LONGCARD(numSamples));
    SetColor(ren, UnpackR(colSelection), UnpackG(colSelection),
             UnpackB(colSelection), 40);
    FillRect(ren, selPixStart, y, selPixEnd - selPixStart, h)
  END;

  samplesPerCol := numSamples DIV CARDINAL(w);
  IF samplesPerCol = 0 THEN samplesPerCol := 1 END;

  FOR col := 0 TO w - 1 DO
    startIdx := CARDINAL(col) * numSamples DIV CARDINAL(w);
    endIdx := CARDINAL(col + 1) * numSamples DIV CARDINAL(w);
    IF endIdx > numSamples THEN endIdx := numSamples END;
    IF endIdx <= startIdx THEN endIdx := startIdx + 1 END;
    IF endIdx > numSamples THEN endIdx := numSamples END;

    minVal := 0.0;
    maxVal := 0.0;
    FOR i := startIdx TO endIdx - 1 DO
      p := Elem(signal, i);
      val := p^;
      IF val < minVal THEN minVal := val END;
      IF val > maxVal THEN maxVal := val END
    END;

    (* Clamp *)
    IF maxVal > 1.0 THEN maxVal := 1.0 END;
    IF minVal < -1.0 THEN minVal := -1.0 END;

    topY := midY - TRUNC(maxVal * LFLOAT(h DIV 2));
    botY := midY - TRUNC(minVal * LFLOAT(h DIV 2));
    IF topY < y THEN topY := y END;
    IF botY > y + h - 1 THEN botY := y + h - 1 END;

    (* Color: brighter in selection *)
    inSel := (selStart # selEnd) AND
             (startIdx >= selStart) AND (startIdx < selEnd);
    IF inSel THEN
      SetColor(ren, 120, 230, 150, 255)
    ELSE
      SetCol(ren, colWave)
    END;

    IF botY > topY THEN
      FillRect(ren, x + col, topY, 1, botY - topY)
    ELSE
      FillRect(ren, x + col, topY, 1, 1)
    END
  END;

  (* Border *)
  SetCol(ren, colBorder);
  DrawRect(ren, x, y, w, h)
END Draw;

PROCEDURE PixelToSample(px, rectX, rectW: INTEGER;
                        numSamples: CARDINAL): CARDINAL;
VAR rel: INTEGER; s: CARDINAL;
BEGIN
  rel := px - rectX;
  IF rel < 0 THEN RETURN 0 END;
  IF rel >= rectW THEN RETURN numSamples END;
  s := CARDINAL(rel) * numSamples DIV CARDINAL(rectW);
  IF s > numSamples THEN s := numSamples END;
  RETURN s
END PixelToSample;

(* ── Spectrogram heatmap ──────────────────────────────── *)

PROCEDURE HeatColor(val: LONGREAL; VAR r, g, b: INTEGER);
(* Map 0..1 to blue→cyan→green→yellow→red *)
VAR t: LONGREAL;
BEGIN
  IF val < 0.0 THEN val := 0.0 END;
  IF val > 1.0 THEN val := 1.0 END;
  t := val * 4.0;
  IF t < 1.0 THEN
    r := 0; g := TRUNC(t * 255.0); b := 255
  ELSIF t < 2.0 THEN
    r := 0; g := 255; b := TRUNC((2.0 - t) * 255.0)
  ELSIF t < 3.0 THEN
    r := TRUNC((t - 2.0) * 255.0); g := 255; b := 0
  ELSE
    r := 255; g := TRUNC((4.0 - t) * 255.0); b := 0
  END
END HeatColor;

PROCEDURE DrawSpectrogram(ren: Renderer;
                           x, y, w, h: INTEGER;
                           data: ADDRESS;
                           numFrames, numBins: CARDINAL);
VAR
  col, row: INTEGER;
  frameIdx, binIdx: CARDINAL;
  val, maxVal: LONGREAL;
  p: RealPtr;
  i: CARDINAL;
  r, g, b: INTEGER;
BEGIN
  SetCol(ren, colBg);
  FillRect(ren, x, y, w, h);

  IF (numFrames = 0) OR (numBins = 0) OR (data = NIL) THEN RETURN END;

  (* Find max for normalization *)
  maxVal := 0.0;
  FOR i := 0 TO numFrames * numBins - 1 DO
    p := Elem(data, i);
    IF p^ > maxVal THEN maxVal := p^ END
  END;
  IF maxVal < 1.0D-20 THEN maxVal := 1.0D-20 END;

  FOR col := 0 TO w - 1 DO
    frameIdx := CARDINAL(col) * numFrames DIV CARDINAL(w);
    IF frameIdx >= numFrames THEN frameIdx := numFrames - 1 END;

    FOR row := 0 TO h - 1 DO
      (* Bottom = low freq, top = high freq *)
      binIdx := CARDINAL(h - 1 - row) * numBins DIV CARDINAL(h);
      IF binIdx >= numBins THEN binIdx := numBins - 1 END;

      p := Elem(data, frameIdx * numBins + binIdx);
      val := p^ / maxVal;
      (* Power-law gamma correction: val^0.3 expands low values *)
      IF val < 1.0D-10 THEN
        val := 0.0
      ELSE
        val := LFLOAT(exp(FLOAT(0.3 * LFLOAT(ln(FLOAT(val))))))
      END;
      IF val > 1.0 THEN val := 1.0 END;
      HeatColor(val, r, g, b);
      SetColor(ren, r, g, b, 255);
      FillRect(ren, x + col, y + row, 1, 1)
    END
  END;

  SetCol(ren, colBorder);
  DrawRect(ren, x, y, w, h)
END DrawSpectrogram;

(* ── Chromagram ───────────────────────────────────────── *)

PROCEDURE DrawChromagram(ren: Renderer;
                          x, y, w, h: INTEGER;
                          data: ADDRESS;
                          numFrames: CARDINAL);
VAR
  col, row: INTEGER;
  frameIdx, chromaIdx: CARDINAL;
  val, maxVal: LONGREAL;
  p: RealPtr;
  i: CARDINAL;
  r, g, b: INTEGER;
BEGIN
  SetCol(ren, colBg);
  FillRect(ren, x, y, w, h);

  IF (numFrames = 0) OR (data = NIL) THEN RETURN END;

  maxVal := 0.0;
  FOR i := 0 TO numFrames * 12 - 1 DO
    p := Elem(data, i);
    IF p^ > maxVal THEN maxVal := p^ END
  END;
  IF maxVal < 1.0D-20 THEN maxVal := 1.0D-20 END;

  FOR col := 0 TO w - 1 DO
    frameIdx := CARDINAL(col) * numFrames DIV CARDINAL(w);
    IF frameIdx >= numFrames THEN frameIdx := numFrames - 1 END;

    FOR row := 0 TO h - 1 DO
      chromaIdx := CARDINAL(11 - (row * 12 DIV h));
      IF chromaIdx > 11 THEN chromaIdx := 0 END;

      p := Elem(data, frameIdx * 12 + chromaIdx);
      val := p^ / maxVal;
      HeatColor(val, r, g, b);
      SetColor(ren, r, g, b, 255);
      FillRect(ren, x + col, y + row, 1, 1)
    END
  END;

  SetCol(ren, colBorder);
  DrawRect(ren, x, y, w, h)
END DrawChromagram;

(* ── Pitch contour ────────────────────────────────────── *)

PROCEDURE DrawPitchContour(ren: Renderer;
                            x, y, w, h: INTEGER;
                            pitches: ADDRESS;
                            numFrames: CARDINAL);
VAR
  col: INTEGER;
  frameIdx: CARDINAL;
  f0, maxF0: LONGREAL;
  p: RealPtr;
  i: CARDINAL;
  py, prevPy: INTEGER;
  first: BOOLEAN;
BEGIN
  SetCol(ren, colBg);
  FillRect(ren, x, y, w, h);

  IF (numFrames = 0) OR (pitches = NIL) THEN RETURN END;

  (* Find max pitch for scaling *)
  maxF0 := 0.0;
  FOR i := 0 TO numFrames - 1 DO
    p := Elem(pitches, i);
    IF p^ > maxF0 THEN maxF0 := p^ END
  END;
  IF maxF0 < 50.0 THEN maxF0 := 500.0 END;

  (* Grid lines *)
  SetCol(ren, colGrid);
  DrawLine(ren, x, y + h DIV 4, x + w - 1, y + h DIV 4);
  DrawLine(ren, x, y + h DIV 2, x + w - 1, y + h DIV 2);
  DrawLine(ren, x, y + 3 * h DIV 4, x + w - 1, y + 3 * h DIV 4);

  (* Draw pitch dots *)
  SetCol(ren, colAccent);
  first := TRUE;
  prevPy := y + h;
  FOR col := 0 TO w - 1 DO
    frameIdx := CARDINAL(col) * numFrames DIV CARDINAL(w);
    IF frameIdx >= numFrames THEN frameIdx := numFrames - 1 END;

    p := Elem(pitches, frameIdx);
    f0 := p^;
    IF f0 > 0.0 THEN
      py := y + h - TRUNC(f0 / maxF0 * LFLOAT(h));
      IF py < y THEN py := y END;
      IF py > y + h - 1 THEN py := y + h - 1 END;
      FillRect(ren, x + col, py, 2, 2);
      IF NOT first THEN
        DrawLine(ren, x + col - 1, prevPy, x + col, py)
      END;
      prevPy := py;
      first := FALSE
    ELSE
      first := TRUE
    END
  END;

  SetCol(ren, colBorder);
  DrawRect(ren, x, y, w, h)
END DrawPitchContour;

END WaveView.
