IMPLEMENTATION MODULE Filter;
(* Butterworth biquad IIR filtering.
   Sample-by-sample processing — no blocks, no boundaries, no clicks.
   Cascades two second-order sections for steeper rolloff (-24 dB/oct). *)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM MathLib IMPORT sin, cos, sqrt;
FROM MathUtil IMPORT Pi;

TYPE
  RealPtr = POINTER TO LONGREAL;

  (* Second-order biquad section: y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2]
                                          - a1*y[n-1] - a2*y[n-2] *)
  Biquad = RECORD
    b0, b1, b2, a1, a2: LONGREAL;
    x1, x2, y1, y2: LONGREAL;  (* state *)
  END;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE ResetBiquad(VAR bq: Biquad);
BEGIN
  bq.x1 := 0.0; bq.x2 := 0.0;
  bq.y1 := 0.0; bq.y2 := 0.0
END ResetBiquad;

(* Design a lowpass biquad with given Q.
   fc = cutoff Hz, fs = sample rate Hz. *)
PROCEDURE DesignLP(VAR bq: Biquad; fc, fs, q: LONGREAL);
VAR
  w0, alpha, cosw0, a0: LONGREAL;
BEGIN
  w0 := 2.0 * Pi * fc / fs;
  cosw0 := LFLOAT(cos(FLOAT(w0)));
  alpha := LFLOAT(sin(FLOAT(w0))) / (2.0 * q);

  a0 := 1.0 + alpha;
  bq.b0 := (1.0 - cosw0) / 2.0 / a0;
  bq.b1 := (1.0 - cosw0) / a0;
  bq.b2 := (1.0 - cosw0) / 2.0 / a0;
  bq.a1 := (-2.0 * cosw0) / a0;
  bq.a2 := (1.0 - alpha) / a0;
  ResetBiquad(bq)
END DesignLP;

(* Design a highpass biquad with given Q. *)
PROCEDURE DesignHP(VAR bq: Biquad; fc, fs, q: LONGREAL);
VAR
  w0, alpha, cosw0, a0: LONGREAL;
BEGIN
  w0 := 2.0 * Pi * fc / fs;
  cosw0 := LFLOAT(cos(FLOAT(w0)));
  alpha := LFLOAT(sin(FLOAT(w0))) / (2.0 * q);

  a0 := 1.0 + alpha;
  bq.b0 := (1.0 + cosw0) / 2.0 / a0;
  bq.b1 := -(1.0 + cosw0) / a0;
  bq.b2 := (1.0 + cosw0) / 2.0 / a0;
  bq.a1 := (-2.0 * cosw0) / a0;
  bq.a2 := (1.0 - alpha) / a0;
  ResetBiquad(bq)
END DesignHP;

(* Process one sample through a biquad section *)
PROCEDURE ProcessSample(VAR bq: Biquad; x: LONGREAL): LONGREAL;
VAR y: LONGREAL;
BEGIN
  y := bq.b0 * x + bq.b1 * bq.x1 + bq.b2 * bq.x2
       - bq.a1 * bq.y1 - bq.a2 * bq.y2;
  bq.x2 := bq.x1;
  bq.x1 := x;
  bq.y2 := bq.y1;
  bq.y1 := y;
  RETURN y
END ProcessSample;

(* Apply two cascaded biquad sections to a signal in-place *)
PROCEDURE ApplyBiquads(signal: ADDRESS; numSamples: CARDINAL;
                       VAR bq1, bq2: Biquad);
VAR
  i: CARDINAL;
  p: RealPtr;
  x: LONGREAL;
BEGIN
  FOR i := 0 TO numSamples - 1 DO
    p := Elem(signal, i);
    x := ProcessSample(bq1, p^);
    p^ := ProcessSample(bq2, x)
  END
END ApplyBiquads;

(* 4th-order Butterworth: two cascaded biquads with Q values
   derived from Butterworth pole angles.
   Q1 = 1 / (2*cos(pi/8)) = 0.5412
   Q2 = 1 / (2*cos(3*pi/8)) = 1.3065 *)

PROCEDURE Lowpass(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                  cutoffHz: LONGREAL);
VAR bq1, bq2: Biquad; fs: LONGREAL;
BEGIN
  fs := LFLOAT(sampleRate);
  DesignLP(bq1, cutoffHz, fs, 0.5412);
  DesignLP(bq2, cutoffHz, fs, 1.3065);
  ApplyBiquads(signal, numSamples, bq1, bq2)
END Lowpass;

PROCEDURE Highpass(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                   cutoffHz: LONGREAL);
VAR bq1, bq2: Biquad; fs: LONGREAL;
BEGIN
  fs := LFLOAT(sampleRate);
  DesignHP(bq1, cutoffHz, fs, 0.5412);
  DesignHP(bq2, cutoffHz, fs, 1.3065);
  ApplyBiquads(signal, numSamples, bq1, bq2)
END Highpass;

PROCEDURE Bandpass(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                   loHz, hiHz: LONGREAL);
VAR lpBq1, lpBq2, hpBq1, hpBq2: Biquad; fs: LONGREAL;
BEGIN
  fs := LFLOAT(sampleRate);
  DesignLP(lpBq1, hiHz, fs, 0.5412);
  DesignLP(lpBq2, hiHz, fs, 1.3065);
  ApplyBiquads(signal, numSamples, lpBq1, lpBq2);
  DesignHP(hpBq1, loHz, fs, 0.5412);
  DesignHP(hpBq2, loHz, fs, 1.3065);
  ApplyBiquads(signal, numSamples, hpBq1, hpBq2)
END Bandpass;

END Filter.
