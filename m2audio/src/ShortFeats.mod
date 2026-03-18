IMPLEMENTATION MODULE ShortFeats;
(* Short-term audio feature extraction — aligned with pyAudioAnalysis.

   Key algorithmic choices matching the reference:
   - No Hamming window (raw frame to FFT)
   - FFT magnitude normalized by N (num_fft = window/2)
   - Energy entropy and spectral entropy use log2
   - Spectral centroid/spread: Hz bins, normalized by max mag
   - Spectral flux: sum of squared diffs (no sqrt)
   - MFCC filterbank: scikits.talkbox (13 linear + 27 log filters)
   - MFCC: log10 + orthonormal DCT-II
   - Chroma: 27.50 Hz base, bin-count averaging *)

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt, cos, sin, ln;
FROM Strings IMPORT Assign;
FROM MathUtil IMPORT Pi, TwoPi, Log10, Log2, Pow, FAbs, NextPow2;
FROM FFT IMPORT Forward;

CONST
  NumMelFilters   = 40;  (* 13 linear + 27 log *)
  NumLinFilters   = 13;
  NumLogFilters   = 27;
  EntropySubBands = 10;
  RolloffThresh   = 0.90;
  Eps             = 1.0D-10;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END Elem;

(* ---- DC normalization (matches pyAudioAnalysis dc_normalize) ---- *)
(* Removes DC offset and normalizes to [-1, 1] range *)

PROCEDURE DCNormalize(signal: ADDRESS; n: CARDINAL);
VAR
  i: CARDINAL;
  mean, maxAbs, val: LONGREAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN END;

  (* Compute mean *)
  mean := 0.0;
  FOR i := 0 TO n - 1 DO
    p := Elem(signal, i);
    mean := mean + p^
  END;
  mean := mean / LFLOAT(n);

  (* Subtract mean *)
  FOR i := 0 TO n - 1 DO
    p := Elem(signal, i);
    p^ := p^ - mean
  END;

  (* Find max absolute value *)
  maxAbs := 0.0;
  FOR i := 0 TO n - 1 DO
    p := Elem(signal, i);
    val := FAbs(p^);
    IF val > maxAbs THEN maxAbs := val END
  END;

  (* Normalize *)
  IF maxAbs > Eps THEN
    FOR i := 0 TO n - 1 DO
      p := Elem(signal, i);
      p^ := p^ / maxAbs
    END
  END
END DCNormalize;

(* ---- Time-domain features ---- *)

PROCEDURE ComputeZCR(frame: ADDRESS; frameLen: CARDINAL): LONGREAL;
VAR
  i, count: CARDINAL;
  pCur, pPrev: RealPtr;
  sCur, sPrev: LONGREAL;
BEGIN
  IF frameLen <= 1 THEN RETURN 0.0 END;
  count := 0;
  pPrev := Elem(frame, 0);
  sPrev := pPrev^;
  FOR i := 1 TO frameLen - 1 DO
    pCur := Elem(frame, i);
    sCur := pCur^;
    (* Count sign changes using abs(diff(sign)) / 2 approach *)
    IF ((sCur >= 0.0) AND (sPrev < 0.0)) OR
       ((sCur < 0.0) AND (sPrev >= 0.0)) THEN
      INC(count)
    END;
    sPrev := sCur
  END;
  RETURN LFLOAT(count) / LFLOAT(frameLen - 1)
END ComputeZCR;

PROCEDURE ComputeEnergy(frame: ADDRESS; frameLen: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  s: LONGREAL;
  p: RealPtr;
BEGIN
  IF frameLen = 0 THEN RETURN 0.0 END;
  s := 0.0;
  FOR i := 0 TO frameLen - 1 DO
    p := Elem(frame, i);
    s := s + p^ * p^
  END;
  RETURN s / LFLOAT(frameLen)
END ComputeEnergy;

PROCEDURE ComputeEnergyEntropy(frame: ADDRESS; frameLen: CARDINAL;
                                numSubFrames: CARDINAL): LONGREAL;
VAR
  i, j, subLen, block, pos: CARDINAL;
  totalEnergy, subEnergy, p_i, h: LONGREAL;
  p: RealPtr;
  subEnergies: ARRAY [0..63] OF LONGREAL;
  effectiveLen: CARDINAL;
BEGIN
  IF (frameLen = 0) OR (numSubFrames = 0) THEN RETURN 0.0 END;

  subLen := frameLen DIV numSubFrames;
  IF subLen = 0 THEN RETURN 0.0 END;
  effectiveLen := subLen * numSubFrames;

  (* Compute total energy of effective region *)
  totalEnergy := 0.0;
  FOR i := 0 TO effectiveLen - 1 DO
    p := Elem(frame, i);
    totalEnergy := totalEnergy + p^ * p^
  END;

  IF totalEnergy = 0.0 THEN RETURN 0.0 END;

  (* Compute sub-frame energies using column-major order
     (matching numpy reshape with order='F') *)
  FOR block := 0 TO numSubFrames - 1 DO
    subEnergies[block] := 0.0
  END;

  FOR i := 0 TO effectiveLen - 1 DO
    (* Column-major: element i maps to column (i DIV subLen) *)
    block := i DIV subLen;
    p := Elem(frame, i);
    subEnergies[block] := subEnergies[block] + p^ * p^
  END;

  (* Entropy with log2 *)
  h := 0.0;
  FOR i := 0 TO numSubFrames - 1 DO
    p_i := subEnergies[i] / (totalEnergy + Eps);
    h := h - p_i * Log2(p_i + Eps)
  END;
  RETURN h
END ComputeEnergyEntropy;

(* ---- Frequency-domain features ---- *)

PROCEDURE ComputeSpectralCentroidSpread(fftMag: ADDRESS; n: CARDINAL;
                                         sampleRate: CARDINAL;
                                         VAR centroid: LONGREAL;
                                         VAR spread: LONGREAL);
VAR
  i: CARDINAL;
  freq, maxMag, num, den, diff: LONGREAL;
  p: RealPtr;
  halfSr: LONGREAL;
BEGIN
  centroid := 0.0;
  spread := 0.0;
  IF n = 0 THEN RETURN END;

  halfSr := LFLOAT(sampleRate) / 2.0;

  (* Find max magnitude for normalization *)
  maxMag := 0.0;
  FOR i := 0 TO n - 1 DO
    p := Elem(fftMag, i);
    IF p^ > maxMag THEN maxMag := p^ END
  END;

  IF maxMag = 0.0 THEN maxMag := Eps END;

  (* Compute centroid in Hz using (i+1)-based frequency bins *)
  num := 0.0;
  den := 0.0;
  FOR i := 0 TO n - 1 DO
    freq := LFLOAT(i + 1) * halfSr / LFLOAT(n);
    p := Elem(fftMag, i);
    num := num + freq * (p^ / maxMag);
    den := den + p^ / maxMag
  END;

  den := den + Eps;
  centroid := num / den;

  (* Compute spread in Hz *)
  num := 0.0;
  FOR i := 0 TO n - 1 DO
    freq := LFLOAT(i + 1) * halfSr / LFLOAT(n);
    p := Elem(fftMag, i);
    diff := freq - centroid;
    num := num + diff * diff * (p^ / maxMag)
  END;
  spread := LFLOAT(sqrt(FLOAT(num / den)));

  (* Normalize to [0, 1] by dividing by half sample rate *)
  centroid := centroid / halfSr;
  spread := spread / halfSr
END ComputeSpectralCentroidSpread;

PROCEDURE ComputeSpectralEntropy(fftMag: ADDRESS; n: CARDINAL;
                                  numSubBands: CARDINAL): LONGREAL;
VAR
  i, block, subLen, effectiveLen: CARDINAL;
  totalEnergy, p_i, h: LONGREAL;
  p: RealPtr;
  subEnergies: ARRAY [0..63] OF LONGREAL;
BEGIN
  IF (n = 0) OR (numSubBands = 0) THEN RETURN 0.0 END;

  subLen := n DIV numSubBands;
  IF subLen = 0 THEN RETURN 0.0 END;
  effectiveLen := subLen * numSubBands;

  totalEnergy := 0.0;
  FOR i := 0 TO effectiveLen - 1 DO
    p := Elem(fftMag, i);
    totalEnergy := totalEnergy + p^ * p^
  END;

  IF totalEnergy = 0.0 THEN RETURN 0.0 END;

  FOR i := 0 TO numSubBands - 1 DO
    subEnergies[i] := 0.0
  END;

  (* Column-major sub-band splitting *)
  FOR i := 0 TO effectiveLen - 1 DO
    block := i DIV subLen;
    p := Elem(fftMag, i);
    subEnergies[block] := subEnergies[block] + p^ * p^
  END;

  h := 0.0;
  FOR i := 0 TO numSubBands - 1 DO
    p_i := subEnergies[i] / (totalEnergy + Eps);
    h := h - p_i * Log2(p_i + Eps)
  END;
  RETURN h
END ComputeSpectralEntropy;

PROCEDURE ComputeSpectralFlux(fftMag, prevFftMag: ADDRESS;
                               n: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  sumCur, sumPrev, diff, flux: LONGREAL;
  pCur, pPrev: RealPtr;
BEGIN
  IF n = 0 THEN RETURN 0.0 END;

  sumCur := 0.0;
  sumPrev := 0.0;
  FOR i := 0 TO n - 1 DO
    pCur := Elem(fftMag, i);
    sumCur := sumCur + pCur^ + Eps;
    pPrev := Elem(prevFftMag, i);
    sumPrev := sumPrev + pPrev^ + Eps
  END;

  (* Sum of squared differences of normalized spectra — no sqrt *)
  flux := 0.0;
  FOR i := 0 TO n - 1 DO
    pCur := Elem(fftMag, i);
    pPrev := Elem(prevFftMag, i);
    diff := pCur^ / sumCur - pPrev^ / sumPrev;
    flux := flux + diff * diff
  END;
  RETURN flux
END ComputeSpectralFlux;

PROCEDURE ComputeSpectralRolloff(fftMag: ADDRESS; n: CARDINAL;
                                  threshold: LONGREAL): LONGREAL;
VAR
  i: CARDINAL;
  totalEnergy, cumEnergy: LONGREAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN 0.0 END;

  totalEnergy := 0.0;
  FOR i := 0 TO n - 1 DO
    p := Elem(fftMag, i);
    totalEnergy := totalEnergy + p^ * p^
  END;

  IF totalEnergy = 0.0 THEN RETURN 0.0 END;

  cumEnergy := 0.0;
  FOR i := 0 TO n - 1 DO
    p := Elem(fftMag, i);
    cumEnergy := cumEnergy + p^ * p^;
    IF cumEnergy > threshold * totalEnergy THEN
      RETURN LFLOAT(i) / LFLOAT(n)
    END
  END;
  RETURN 0.0
END ComputeSpectralRolloff;

(* ---- MFCC (scikits.talkbox filterbank) ---- *)

PROCEDURE ComputeMFCC(fftMag: ADDRESS; fftLen: CARDINAL;
                       sampleRate: CARDINAL;
                       VAR mfcc: ARRAY OF LONGREAL;
                       fbank: ADDRESS;
                       fbankReady: BOOLEAN);
VAR
  i, j, k, filtIdx: CARDINAL;
  lowfreq, linc, logsc: LONGREAL;
  freqs: ARRAY [0..41] OF LONGREAL;  (* 40 filters + 2 *)
  heights: ARRAY [0..39] OF LONGREAL;
  nfreq, lowF, centF, highF, lslope, rslope: LONGREAL;
  mspec: ARRAY [0..39] OF LONGREAL;
  dctOut: ARRAY [0..13] OF LONGREAL;
  dotSum, angle, normFactor: LONGREAL;
  p, pDst: RealPtr;
  lid, rid: INTEGER;
  sr: LONGREAL;
BEGIN
  sr := LFLOAT(sampleRate);

  IF NOT fbankReady THEN
    (* Build scikits.talkbox filterbank *)
    lowfreq := 133.33;
    linc := 200.0 / 3.0;
    logsc := 1.0711703;

    (* Compute frequency points *)
    FOR i := 0 TO NumLinFilters - 1 DO
      freqs[i] := lowfreq + LFLOAT(i) * linc
    END;
    FOR i := 0 TO NumLogFilters + 1 DO
      freqs[NumLinFilters + i] := freqs[NumLinFilters - 1] *
                                   Pow(logsc, LFLOAT(i + 1))
    END;

    (* Heights: 2 / (f[i+2] - f[i]) *)
    FOR i := 0 TO NumMelFilters - 1 DO
      heights[i] := 2.0 / (freqs[i + 2] - freqs[i])
    END;

    (* Build filter coefficients in fbank array
       Layout: fbank[filtIdx * fftLen + bin] *)
    FOR i := 0 TO NumMelFilters * fftLen - 1 DO
      p := Elem(fbank, i);
      p^ := 0.0
    END;

    FOR filtIdx := 0 TO NumMelFilters - 1 DO
      lowF := freqs[filtIdx];
      centF := freqs[filtIdx + 1];
      highF := freqs[filtIdx + 2];
      lslope := heights[filtIdx] / (centF - lowF);
      rslope := heights[filtIdx] / (highF - centF);

      FOR j := 0 TO fftLen - 1 DO
        nfreq := LFLOAT(j) / LFLOAT(fftLen) * sr;

        IF (nfreq >= lowF) AND (nfreq < centF) THEN
          p := Elem(fbank, filtIdx * fftLen + j);
          p^ := lslope * (nfreq - lowF)
        ELSIF (nfreq >= centF) AND (nfreq < highF) THEN
          p := Elem(fbank, filtIdx * fftLen + j);
          p^ := rslope * (highF - nfreq)
        END
      END
    END
  END;

  (* Apply filterbank: mspec = log10(fftMag . fbank^T) *)
  FOR i := 0 TO NumMelFilters - 1 DO
    dotSum := 0.0;
    FOR j := 0 TO fftLen - 1 DO
      p := Elem(fftMag, j);
      pDst := Elem(fbank, i * fftLen + j);
      dotSum := dotSum + p^ * pDst^
    END;
    mspec[i] := Log10(dotSum + Eps)
  END;

  (* Orthonormal DCT-II: scipy dct type=2, norm='ortho' *)
  FOR k := 0 TO NumMfcc - 1 DO
    dotSum := 0.0;
    FOR i := 0 TO NumMelFilters - 1 DO
      angle := Pi / LFLOAT(NumMelFilters)
               * (LFLOAT(i) + 0.5) * LFLOAT(k);
      dotSum := dotSum + mspec[i] * LFLOAT(cos(FLOAT(angle)))
    END;
    (* Orthonormal scaling *)
    IF k = 0 THEN
      normFactor := LFLOAT(sqrt(FLOAT(1.0 / LFLOAT(NumMelFilters))))
    ELSE
      normFactor := LFLOAT(sqrt(FLOAT(2.0 / LFLOAT(NumMelFilters))))
    END;
    mfcc[k] := dotSum * normFactor
  END
END ComputeMFCC;

(* ---- Chroma (matching pyAudioAnalysis chroma_features) ---- *)

PROCEDURE ComputeChroma(fftMag: ADDRESS; fftLen: CARDINAL;
                         sampleRate: CARDINAL;
                         VAR chroma: ARRAY OF LONGREAL;
                         VAR chromaStd: LONGREAL);
VAR
  i, j, chromaIdx, nBins: CARDINAL;
  freq, semitone, specSum, m, s, diff: LONGREAL;
  p: RealPtr;
  chromaRaw: ARRAY [0..255] OF LONGREAL;  (* accumulator before folding *)
  binCount: ARRAY [0..255] OF CARDINAL;
  maxChroma: INTEGER;
  final12: ARRAY [0..11] OF LONGREAL;
  halfSr: LONGREAL;
  numChromaArr: ARRAY [0..8191] OF INTEGER;
  numFreqsPerChroma: ARRAY [0..255] OF CARDINAL;
  maxIdx: INTEGER;
  newD, rows, r, c: CARDINAL;
  c2: ARRAY [0..1023] OF LONGREAL;  (* folded chroma *)
BEGIN
  halfSr := LFLOAT(sampleRate) / 2.0;

  (* Map each FFT bin to chroma index: round(12 * log2(freq / 27.50))
     matching pyAudioAnalysis chroma_features_init *)
  maxIdx := 0;
  FOR i := 0 TO fftLen - 1 DO
    freq := LFLOAT(i + 1) * halfSr / LFLOAT(fftLen);
    IF freq > 0.0 THEN
      semitone := 12.0 * Log2(freq / 27.50);
      (* Round to nearest integer *)
      IF semitone >= 0.0 THEN
        numChromaArr[i] := TRUNC(semitone + 0.5)
      ELSE
        numChromaArr[i] := -TRUNC(-semitone + 0.5)
      END
    ELSE
      numChromaArr[i] := 0
    END;
    IF numChromaArr[i] > maxIdx THEN
      maxIdx := numChromaArr[i]
    END
  END;

  (* Build power spectrum and map to chroma bins *)
  FOR i := 0 TO 255 DO
    chromaRaw[i] := 0.0;
    binCount[i] := 0;
    numFreqsPerChroma[i] := 0
  END;

  (* Count frequencies per chroma bin *)
  FOR i := 0 TO fftLen - 1 DO
    IF (numChromaArr[i] >= 0) AND (numChromaArr[i] < 256) THEN
      INC(numFreqsPerChroma[numChromaArr[i]])
    END
  END;

  (* Assign power spectrum to chroma bins — last-write-wins,
     matching numpy advanced indexing: C[num_chroma] = spec *)
  specSum := 0.0;
  FOR i := 0 TO fftLen - 1 DO
    p := Elem(fftMag, i);
    IF (numChromaArr[i] >= 0) AND (numChromaArr[i] < 256) THEN
      chromaRaw[numChromaArr[i]] := p^ * p^  (* overwrites, not accumulates *)
    END;
    specSum := specSum + p^ * p^
  END;

  (* Divide each position by num_freqs_per_chroma for that chroma index,
     matching: C /= num_freqs_per_chroma[num_chroma] *)
  FOR i := 0 TO fftLen - 1 DO
    IF (numChromaArr[i] >= 0) AND (numChromaArr[i] < 256) THEN
      IF numFreqsPerChroma[numChromaArr[i]] > 0 THEN
        chromaRaw[numChromaArr[i]] := chromaRaw[numChromaArr[i]]
          / LFLOAT(numFreqsPerChroma[numChromaArr[i]])
      END
    END
  END;

  (* Fold into 12 bins by summing rows *)
  nBins := CARDINAL(maxIdx) + 1;
  IF nBins < 12 THEN nBins := 12 END;
  (* Round up to multiple of 12 *)
  newD := ((nBins + 11) DIV 12) * 12;

  FOR i := 0 TO 11 DO
    final12[i] := 0.0
  END;

  FOR i := 0 TO newD - 1 DO
    IF i < 256 THEN
      final12[i MOD 12] := final12[i MOD 12] + chromaRaw[i]
    END
  END;

  (* Normalize by total spectral power *)
  IF specSum = 0.0 THEN specSum := Eps END;
  FOR i := 0 TO 11 DO
    chroma[i] := final12[i] / specSum
  END;

  (* Compute std dev of chroma vector *)
  m := 0.0;
  FOR i := 0 TO 11 DO
    m := m + chroma[i]
  END;
  m := m / 12.0;

  s := 0.0;
  FOR i := 0 TO 11 DO
    diff := chroma[i] - m;
    s := s + diff * diff
  END;
  (* Use numpy std (population std, ddof=0) *)
  chromaStd := LFLOAT(sqrt(FLOAT(s / 12.0)))
END ComputeChroma;

(* ---- Direct DFT for exact-size magnitude computation ---- *)
(* Computes the first numBins magnitude values of an N-point DFT.
   This avoids the radix-2 constraint and resampling artifacts.
   O(numBins * N) — acceptable for numBins=1102, N=2205. *)

PROCEDURE DirectMagnitude(signal: ADDRESS; n: CARDINAL;
                           mag: ADDRESS; numBins: CARDINAL;
                           normalize: BOOLEAN);
VAR
  k, j: CARDINAL;
  re, im, angle, sVal: LONGREAL;
  p, pOut: RealPtr;
BEGIN
  FOR k := 0 TO numBins - 1 DO
    re := 0.0;
    im := 0.0;
    FOR j := 0 TO n - 1 DO
      p := Elem(signal, j);
      sVal := p^;
      angle := TwoPi * LFLOAT(k) * LFLOAT(j) / LFLOAT(n);
      re := re + sVal * LFLOAT(cos(FLOAT(angle)));
      im := im - sVal * LFLOAT(sin(FLOAT(angle)))
    END;
    pOut := Elem(mag, k);
    pOut^ := LFLOAT(sqrt(FLOAT(re * re + im * im)));
    IF normalize THEN
      pOut^ := pOut^ / LFLOAT(numBins)
    END
  END
END DirectMagnitude;

(* ---- Main Extract procedure ---- *)

PROCEDURE Extract(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                  winSizeSec, winStepSec: LONGREAL;
                  VAR featureMatrix: ADDRESS; VAR numFrames: CARDINAL;
                  VAR ok: BOOLEAN);
VAR
  winSizeSamp, winStepSamp, numFft: CARDINAL;
  frameStart, frameIdx, i, j: CARDINAL;
  totalFrames: CARDINAL;
  magBuf, prevMag, normSignal: ADDRESS;
  pSrc, pDst, pMat: RealPtr;
  centroid, spread: LONGREAL;
  mfccVals: ARRAY [0..12] OF LONGREAL;
  chromaVals: ARRAY [0..11] OF LONGREAL;
  chromaStdVal: LONGREAL;
  hasPrev: BOOLEAN;
  fbank: ADDRESS;
  fbankSize: CARDINAL;
  fbankReady: BOOLEAN;
BEGIN
  ok := FALSE;
  featureMatrix := NIL;
  numFrames := 0;

  winSizeSamp := TRUNC(winSizeSec * LFLOAT(sampleRate));
  winStepSamp := TRUNC(winStepSec * LFLOAT(sampleRate));

  IF (winSizeSamp = 0) OR (winStepSamp = 0) OR (numSamples = 0) THEN
    RETURN
  END;

  IF numSamples < winSizeSamp THEN RETURN END;

  totalFrames := (numSamples - winSizeSamp) DIV winStepSamp + 1;
  IF totalFrames = 0 THEN RETURN END;

  (* num_fft = window / 2, matching pyAudioAnalysis *)
  numFft := winSizeSamp DIV 2;

  (* DC normalize the signal (makes a copy) *)
  ALLOCATE(normSignal, numSamples * TSIZE(LONGREAL));
  FOR i := 0 TO numSamples - 1 DO
    pSrc := Elem(signal, i);
    pDst := Elem(normSignal, i);
    pDst^ := pSrc^
  END;
  DCNormalize(normSignal, numSamples);

  (* Allocate working buffers *)
  ALLOCATE(magBuf, numFft * TSIZE(LONGREAL));
  ALLOCATE(prevMag, numFft * TSIZE(LONGREAL));

  (* Zero-initialize prevMag *)
  FOR i := 0 TO numFft - 1 DO
    pDst := Elem(prevMag, i);
    pDst^ := 0.0
  END;

  (* Allocate feature matrix *)
  ALLOCATE(featureMatrix, totalFrames * NumFeatures * TSIZE(LONGREAL));

  (* Allocate filterbank on heap: 40 filters x numFft bins *)
  fbankSize := NumMelFilters * numFft * TSIZE(LONGREAL);
  ALLOCATE(fbank, fbankSize);

  hasPrev := FALSE;
  fbankReady := FALSE;

  FOR frameIdx := 0 TO totalFrames - 1 DO
    frameStart := frameIdx * winStepSamp;

    (* Direct DFT at exact window size — no zero-padding artifacts.
       Computes first numFft magnitude bins, normalized by numFft. *)
    DirectMagnitude(
      ADDRESS(LONGCARD(normSignal) + LONGCARD(frameStart) * LONGCARD(TSIZE(LONGREAL))),
      winSizeSamp, magBuf, numFft, TRUE);

    (* --- Compute features --- *)

    (* 0: ZCR — from raw (non-DC-normalized) frame for consistency,
       but pyAudio uses DC-normalized signal *)
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 0);
    pMat^ := ComputeZCR(
      ADDRESS(LONGCARD(normSignal) + LONGCARD(frameStart) * LONGCARD(TSIZE(LONGREAL))),
      winSizeSamp);

    (* 1: Energy *)
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 1);
    pMat^ := ComputeEnergy(
      ADDRESS(LONGCARD(normSignal) + LONGCARD(frameStart) * LONGCARD(TSIZE(LONGREAL))),
      winSizeSamp);

    (* 2: Energy Entropy *)
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 2);
    pMat^ := ComputeEnergyEntropy(
      ADDRESS(LONGCARD(normSignal) + LONGCARD(frameStart) * LONGCARD(TSIZE(LONGREAL))),
      winSizeSamp, EntropySubBands);

    (* 3-4: Spectral Centroid and Spread *)
    ComputeSpectralCentroidSpread(magBuf, numFft, sampleRate,
                                   centroid, spread);
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 3);
    pMat^ := centroid;
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 4);
    pMat^ := spread;

    (* 5: Spectral Entropy *)
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 5);
    pMat^ := ComputeSpectralEntropy(magBuf, numFft, EntropySubBands);

    (* 6: Spectral Flux *)
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 6);
    IF hasPrev THEN
      pMat^ := ComputeSpectralFlux(magBuf, prevMag, numFft)
    ELSE
      pMat^ := 0.0
    END;

    (* 7: Spectral Rolloff *)
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 7);
    pMat^ := ComputeSpectralRolloff(magBuf, numFft, RolloffThresh);

    (* 8-20: MFCC 1-13 *)
    ComputeMFCC(magBuf, numFft, sampleRate, mfccVals,
                fbank, fbankReady);
    fbankReady := TRUE;
    FOR j := 0 TO NumMfcc - 1 DO
      pMat := Elem(featureMatrix, frameIdx * NumFeatures + 8 + j);
      pMat^ := mfccVals[j]
    END;

    (* 21-32: Chroma 1-12 and 33: Chroma Std Dev *)
    ComputeChroma(magBuf, numFft, sampleRate, chromaVals, chromaStdVal);
    FOR j := 0 TO NumChroma - 1 DO
      pMat := Elem(featureMatrix, frameIdx * NumFeatures + 21 + j);
      pMat^ := chromaVals[j]
    END;
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 33);
    pMat^ := chromaStdVal;

    (* Save current magnitude as previous *)
    FOR i := 0 TO numFft - 1 DO
      pSrc := Elem(magBuf, i);
      pDst := Elem(prevMag, i);
      pDst^ := pSrc^
    END;
    hasPrev := TRUE
  END;

  numFrames := totalFrames;
  ok := TRUE;

  (* Free working buffers *)
  DEALLOCATE(fbank, fbankSize);
  DEALLOCATE(normSignal, numSamples * TSIZE(LONGREAL));
  DEALLOCATE(magBuf, numFft * TSIZE(LONGREAL));
  DEALLOCATE(prevMag, numFft * TSIZE(LONGREAL))
END Extract;

(* ---- Fast Extract using radix-2 FFT ---- *)

PROCEDURE ExtractFast(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                      winSizeSec, winStepSec: LONGREAL;
                      VAR featureMatrix: ADDRESS; VAR numFrames: CARDINAL;
                      VAR ok: BOOLEAN);
VAR
  winSizeSamp, winStepSamp, numFft, fftSize: CARDINAL;
  frameStart, frameIdx, i, j: CARDINAL;
  totalFrames: CARDINAL;
  complexBuf, magBuf, prevMag, normSignal: ADDRESS;
  pSrc, pDst, pMat: RealPtr;
  centroid, spread, re, im: LONGREAL;
  mfccVals: ARRAY [0..12] OF LONGREAL;
  chromaVals: ARRAY [0..11] OF LONGREAL;
  chromaStdVal: LONGREAL;
  hasPrev: BOOLEAN;
  fbank: ADDRESS;
  fbankSize: CARDINAL;
  fbankReady: BOOLEAN;
BEGIN
  ok := FALSE;
  featureMatrix := NIL;
  numFrames := 0;

  winSizeSamp := TRUNC(winSizeSec * LFLOAT(sampleRate));
  winStepSamp := TRUNC(winStepSec * LFLOAT(sampleRate));

  IF (winSizeSamp = 0) OR (winStepSamp = 0) OR (numSamples = 0) THEN
    RETURN
  END;

  IF numSamples < winSizeSamp THEN RETURN END;

  totalFrames := (numSamples - winSizeSamp) DIV winStepSamp + 1;
  IF totalFrames = 0 THEN RETURN END;

  fftSize := NextPow2(winSizeSamp);
  numFft := fftSize DIV 2;

  (* DC normalize the signal (makes a copy) *)
  ALLOCATE(normSignal, numSamples * TSIZE(LONGREAL));
  FOR i := 0 TO numSamples - 1 DO
    pSrc := Elem(signal, i);
    pDst := Elem(normSignal, i);
    pDst^ := pSrc^
  END;
  DCNormalize(normSignal, numSamples);

  (* Allocate working buffers *)
  ALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));
  ALLOCATE(magBuf, numFft * TSIZE(LONGREAL));
  ALLOCATE(prevMag, numFft * TSIZE(LONGREAL));

  FOR i := 0 TO numFft - 1 DO
    pDst := Elem(prevMag, i);
    pDst^ := 0.0
  END;

  ALLOCATE(featureMatrix, totalFrames * NumFeatures * TSIZE(LONGREAL));

  fbankSize := NumMelFilters * numFft * TSIZE(LONGREAL);
  ALLOCATE(fbank, fbankSize);

  hasPrev := FALSE;
  fbankReady := FALSE;

  FOR frameIdx := 0 TO totalFrames - 1 DO
    frameStart := frameIdx * winStepSamp;

    (* Pack frame into complex buffer with zero-padding *)
    FOR i := 0 TO fftSize - 1 DO
      pDst := Elem(complexBuf, 2 * i);
      IF i < winSizeSamp THEN
        pSrc := Elem(normSignal, frameStart + i);
        pDst^ := pSrc^
      ELSE
        pDst^ := 0.0
      END;
      pDst := Elem(complexBuf, 2 * i + 1);
      pDst^ := 0.0
    END;

    (* Radix-2 FFT — O(N log N) *)
    Forward(complexBuf, fftSize);

    (* Magnitude of first half, normalized by numFft *)
    FOR i := 0 TO numFft - 1 DO
      pSrc := Elem(complexBuf, 2 * i);
      pDst := Elem(complexBuf, 2 * i + 1);
      re := pSrc^;
      im := pDst^;
      pMat := Elem(magBuf, i);
      pMat^ := LFLOAT(sqrt(FLOAT(re * re + im * im))) / LFLOAT(numFft)
    END;

    (* Features — identical to Extract from here *)

    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 0);
    pMat^ := ComputeZCR(
      ADDRESS(LONGCARD(normSignal) + LONGCARD(frameStart) * LONGCARD(TSIZE(LONGREAL))),
      winSizeSamp);

    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 1);
    pMat^ := ComputeEnergy(
      ADDRESS(LONGCARD(normSignal) + LONGCARD(frameStart) * LONGCARD(TSIZE(LONGREAL))),
      winSizeSamp);

    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 2);
    pMat^ := ComputeEnergyEntropy(
      ADDRESS(LONGCARD(normSignal) + LONGCARD(frameStart) * LONGCARD(TSIZE(LONGREAL))),
      winSizeSamp, EntropySubBands);

    ComputeSpectralCentroidSpread(magBuf, numFft, sampleRate,
                                   centroid, spread);
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 3);
    pMat^ := centroid;
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 4);
    pMat^ := spread;

    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 5);
    pMat^ := ComputeSpectralEntropy(magBuf, numFft, EntropySubBands);

    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 6);
    IF hasPrev THEN
      pMat^ := ComputeSpectralFlux(magBuf, prevMag, numFft)
    ELSE
      pMat^ := 0.0
    END;

    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 7);
    pMat^ := ComputeSpectralRolloff(magBuf, numFft, RolloffThresh);

    ComputeMFCC(magBuf, numFft, sampleRate, mfccVals,
                fbank, fbankReady);
    fbankReady := TRUE;
    FOR j := 0 TO NumMfcc - 1 DO
      pMat := Elem(featureMatrix, frameIdx * NumFeatures + 8 + j);
      pMat^ := mfccVals[j]
    END;

    ComputeChroma(magBuf, numFft, sampleRate, chromaVals, chromaStdVal);
    FOR j := 0 TO NumChroma - 1 DO
      pMat := Elem(featureMatrix, frameIdx * NumFeatures + 21 + j);
      pMat^ := chromaVals[j]
    END;
    pMat := Elem(featureMatrix, frameIdx * NumFeatures + 33);
    pMat^ := chromaStdVal;

    FOR i := 0 TO numFft - 1 DO
      pSrc := Elem(magBuf, i);
      pDst := Elem(prevMag, i);
      pDst^ := pSrc^
    END;
    hasPrev := TRUE
  END;

  numFrames := totalFrames;
  ok := TRUE;

  DEALLOCATE(fbank, fbankSize);
  DEALLOCATE(normSignal, numSamples * TSIZE(LONGREAL));
  DEALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));
  DEALLOCATE(magBuf, numFft * TSIZE(LONGREAL));
  DEALLOCATE(prevMag, numFft * TSIZE(LONGREAL))
END ExtractFast;

PROCEDURE FreeFeatures(VAR featureMatrix: ADDRESS; numFrames: CARDINAL);
BEGIN
  IF featureMatrix # NIL THEN
    DEALLOCATE(featureMatrix, numFrames * NumFeatures * TSIZE(LONGREAL));
    featureMatrix := NIL
  END
END FreeFeatures;

PROCEDURE FeatureName(idx: CARDINAL; VAR name: ARRAY OF CHAR);
BEGIN
  CASE idx OF
    0:  Assign("Zero Crossing Rate", name)  |
    1:  Assign("Energy", name)              |
    2:  Assign("Energy Entropy", name)      |
    3:  Assign("Spectral Centroid", name)   |
    4:  Assign("Spectral Spread", name)     |
    5:  Assign("Spectral Entropy", name)    |
    6:  Assign("Spectral Flux", name)       |
    7:  Assign("Spectral Rolloff", name)    |
    8:  Assign("MFCC 1", name)              |
    9:  Assign("MFCC 2", name)              |
    10: Assign("MFCC 3", name)              |
    11: Assign("MFCC 4", name)              |
    12: Assign("MFCC 5", name)              |
    13: Assign("MFCC 6", name)              |
    14: Assign("MFCC 7", name)              |
    15: Assign("MFCC 8", name)              |
    16: Assign("MFCC 9", name)              |
    17: Assign("MFCC 10", name)             |
    18: Assign("MFCC 11", name)             |
    19: Assign("MFCC 12", name)             |
    20: Assign("MFCC 13", name)             |
    21: Assign("Chroma 1", name)            |
    22: Assign("Chroma 2", name)            |
    23: Assign("Chroma 3", name)            |
    24: Assign("Chroma 4", name)            |
    25: Assign("Chroma 5", name)            |
    26: Assign("Chroma 6", name)            |
    27: Assign("Chroma 7", name)            |
    28: Assign("Chroma 8", name)            |
    29: Assign("Chroma 9", name)            |
    30: Assign("Chroma 10", name)           |
    31: Assign("Chroma 11", name)           |
    32: Assign("Chroma 12", name)           |
    33: Assign("Chroma Std Dev", name)
  ELSE
    Assign("Unknown", name)
  END
END FeatureName;

END ShortFeats.
