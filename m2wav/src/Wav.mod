IMPLEMENTATION MODULE Wav;

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sin;
FROM Sys IMPORT m2sys_fopen, m2sys_fclose,
                m2sys_fread_bytes, m2sys_fwrite_bytes;

TYPE
  LongRealPtr = POINTER TO LONGREAL;
  BytePtr = POINTER TO CHAR;

(* Helper: read a 16-bit unsigned little-endian value from buffer at offset *)
PROCEDURE Get16(VAR buf: ARRAY OF CHAR; off: CARDINAL): CARDINAL;
BEGIN
  RETURN ORD(buf[off]) + ORD(buf[off + 1]) * 256
END Get16;

(* Helper: read a 32-bit unsigned little-endian value from buffer at offset *)
PROCEDURE Get32(VAR buf: ARRAY OF CHAR; off: CARDINAL): CARDINAL;
BEGIN
  RETURN ORD(buf[off])
       + ORD(buf[off + 1]) * 256
       + ORD(buf[off + 2]) * 65536
       + ORD(buf[off + 3]) * 16777216
END Get32;

(* Helper: write a 16-bit unsigned little-endian value into buffer at offset *)
PROCEDURE Put16(VAR buf: ARRAY OF CHAR; off: CARDINAL; val: CARDINAL);
BEGIN
  buf[off]     := CHR(val MOD 256);
  buf[off + 1] := CHR((val DIV 256) MOD 256)
END Put16;

(* Helper: write a 32-bit unsigned little-endian value into buffer at offset *)
PROCEDURE Put32(VAR buf: ARRAY OF CHAR; off: CARDINAL; val: CARDINAL);
BEGIN
  buf[off]     := CHR(val MOD 256);
  buf[off + 1] := CHR((val DIV 256) MOD 256);
  buf[off + 2] := CHR((val DIV 65536) MOD 256);
  buf[off + 3] := CHR((val DIV 16777216) MOD 256)
END Put32;

(* Helper: access a LONGREAL element by index from a base ADDRESS *)
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

PROCEDURE ReadWav(path: ARRAY OF CHAR;
                  VAR info: WavInfo;
                  VAR samples: ADDRESS;
                  VAR ok: BOOLEAN);
VAR
  f: INTEGER;
  hdr: ARRAY [0..43] OF CHAR;
  n: INTEGER;
  audioFmt, chunkSize: CARDINAL;
  totalSamples, i: CARDINAL;
  rawBuf: ADDRESS;
  bp: BytePtr;
  lo, hi, b2, b3: CARDINAL;
  sval: INTEGER;
  lval: LONGCARD;
  sample: LONGREAL;
  addr: LONGCARD;
  chunkHdr: ARRAY [0..7] OF CHAR;
  skipBuf: ARRAY [0..255] OF CHAR;
  extraBytes, toSkip, fmtSize: CARDINAL;
  modeRb: ARRAY [0..2] OF CHAR;
  dummy: INTEGER;
BEGIN
  ok := FALSE;
  samples := NIL;

  modeRb[0] := 'r'; modeRb[1] := 'b'; modeRb[2] := 0C;
  f := m2sys_fopen(ADR(path), ADR(modeRb));
  IF f < 0 THEN
    RETURN
  END;

  (* Read first 12 bytes: RIFF header *)
  n := m2sys_fread_bytes(f, ADR(hdr), 12);
  IF n # 12 THEN
    dummy := m2sys_fclose(f);
    RETURN
  END;

  (* Check "RIFF" *)
  IF (hdr[0] # 'R') OR (hdr[1] # 'I') OR (hdr[2] # 'F') OR (hdr[3] # 'F') THEN
    dummy := m2sys_fclose(f);
    RETURN
  END;

  (* Check "WAVE" *)
  IF (hdr[8] # 'W') OR (hdr[9] # 'A') OR (hdr[10] # 'V') OR (hdr[11] # 'E') THEN
    dummy := m2sys_fclose(f);
    RETURN
  END;

  (* Find "fmt " chunk *)
  LOOP
    n := m2sys_fread_bytes(f, ADR(chunkHdr), 8);
    IF n # 8 THEN
      dummy := m2sys_fclose(f);
      RETURN
    END;
    chunkSize := ORD(chunkHdr[4])
               + ORD(chunkHdr[5]) * 256
               + ORD(chunkHdr[6]) * 65536
               + ORD(chunkHdr[7]) * 16777216;

    IF (chunkHdr[0] = 'f') AND (chunkHdr[1] = 'm') AND
       (chunkHdr[2] = 't') AND (chunkHdr[3] = ' ') THEN
      EXIT
    END;

    (* Skip this chunk *)
    extraBytes := chunkSize;
    WHILE extraBytes > 0 DO
      IF extraBytes > 256 THEN
        toSkip := 256
      ELSE
        toSkip := extraBytes
      END;
      n := m2sys_fread_bytes(f, ADR(skipBuf), INTEGER(toSkip));
      IF n <= 0 THEN
        dummy := m2sys_fclose(f);
        RETURN
      END;
      DEC(extraBytes, CARDINAL(n))
    END
  END;

  (* Read fmt chunk data (at least 16 bytes) *)
  fmtSize := chunkSize;
  IF fmtSize < 16 THEN
    dummy := m2sys_fclose(f);
    RETURN
  END;

  (* Read 16 bytes of fmt data into hdr[0..15] *)
  n := m2sys_fread_bytes(f, ADR(hdr), 16);
  IF n # 16 THEN
    dummy := m2sys_fclose(f);
    RETURN
  END;

  audioFmt := Get16(hdr, 0);
  IF (audioFmt # 1) AND (audioFmt # 65534) THEN
    (* Not PCM and not WAVE_FORMAT_EXTENSIBLE *)
    dummy := m2sys_fclose(f);
    RETURN
  END;

  info.numChannels := Get16(hdr, 2);
  info.sampleRate := Get32(hdr, 4);
  (* skip byteRate (4 bytes) and blockAlign (2 bytes) *)
  info.bitsPerSample := Get16(hdr, 14);

  IF (info.bitsPerSample # 8) AND (info.bitsPerSample # 16) AND
     (info.bitsPerSample # 24) AND (info.bitsPerSample # 32) THEN
    dummy := m2sys_fclose(f);
    RETURN
  END;

  (* Skip any extra fmt bytes *)
  IF fmtSize > 16 THEN
    extraBytes := fmtSize - 16;
    WHILE extraBytes > 0 DO
      IF extraBytes > 256 THEN
        toSkip := 256
      ELSE
        toSkip := extraBytes
      END;
      n := m2sys_fread_bytes(f, ADR(skipBuf), INTEGER(toSkip));
      IF n <= 0 THEN
        dummy := m2sys_fclose(f);
        RETURN
      END;
      DEC(extraBytes, CARDINAL(n))
    END
  END;

  (* Find "data" chunk *)
  LOOP
    n := m2sys_fread_bytes(f, ADR(chunkHdr), 8);
    IF n # 8 THEN
      dummy := m2sys_fclose(f);
      RETURN
    END;
    chunkSize := ORD(chunkHdr[4])
               + ORD(chunkHdr[5]) * 256
               + ORD(chunkHdr[6]) * 65536
               + ORD(chunkHdr[7]) * 16777216;

    IF (chunkHdr[0] = 'd') AND (chunkHdr[1] = 'a') AND
       (chunkHdr[2] = 't') AND (chunkHdr[3] = 'a') THEN
      EXIT
    END;

    (* Skip this chunk *)
    extraBytes := chunkSize;
    WHILE extraBytes > 0 DO
      IF extraBytes > 256 THEN
        toSkip := 256
      ELSE
        toSkip := extraBytes
      END;
      n := m2sys_fread_bytes(f, ADR(skipBuf), INTEGER(toSkip));
      IF n <= 0 THEN
        dummy := m2sys_fclose(f);
        RETURN
      END;
      DEC(extraBytes, CARDINAL(n))
    END
  END;

  info.dataSize := chunkSize;

  (* Calculate number of sample frames *)
  totalSamples := info.dataSize DIV
                  ((info.bitsPerSample DIV 8) * info.numChannels);
  info.numSamples := totalSamples;

  (* Read raw PCM data *)
  ALLOCATE(rawBuf, info.dataSize);
  n := m2sys_fread_bytes(f, rawBuf, INTEGER(info.dataSize));
  dummy := m2sys_fclose(f);

  IF n # INTEGER(info.dataSize) THEN
    DEALLOCATE(rawBuf, info.dataSize);
    RETURN
  END;

  (* Allocate LONGREAL sample array *)
  ALLOCATE(samples, totalSamples * info.numChannels * TSIZE(LONGREAL));

  (* Convert raw PCM to LONGREAL [-1.0, 1.0] *)
  IF info.bitsPerSample = 32 THEN
    (* 32-bit signed PCM: 4 bytes little-endian per sample *)
    FOR i := 0 TO totalSamples * info.numChannels - 1 DO
      addr := LONGCARD(rawBuf) + LONGCARD(i * 4);
      bp := BytePtr(addr);
      lo := ORD(bp^);
      bp := BytePtr(addr + 1);
      hi := ORD(bp^);
      bp := BytePtr(addr + 2);
      b2 := ORD(bp^);
      bp := BytePtr(addr + 3);
      b3 := ORD(bp^);
      (* Assemble as unsigned, then handle sign *)
      lval := LONGCARD(lo)
            + LONGCARD(hi) * 256
            + LONGCARD(b2) * 65536
            + LONGCARD(b3) * 16777216;
      IF lval >= 2147483648 THEN
        sample := LFLOAT(lval) / 2147483648.0D0 - 2.0D0
      ELSE
        sample := LFLOAT(lval) / 2147483648.0D0
      END;
      SetElem(samples, i, sample)
    END
  ELSIF info.bitsPerSample = 24 THEN
    (* 24-bit signed PCM: 3 bytes little-endian per sample *)
    FOR i := 0 TO totalSamples * info.numChannels - 1 DO
      addr := LONGCARD(rawBuf) + LONGCARD(i * 3);
      bp := BytePtr(addr);
      lo := ORD(bp^);
      bp := BytePtr(addr + 1);
      hi := ORD(bp^);
      bp := BytePtr(addr + 2);
      b2 := ORD(bp^);
      sval := INTEGER(lo + hi * 256 + b2 * 65536);
      IF sval >= 8388608 THEN
        sval := sval - 16777216
      END;
      sample := LFLOAT(sval) / 8388608.0D0;
      SetElem(samples, i, sample)
    END
  ELSIF info.bitsPerSample = 16 THEN
    FOR i := 0 TO totalSamples * info.numChannels - 1 DO
      addr := LONGCARD(rawBuf) + LONGCARD(i * 2);
      bp := BytePtr(addr);
      lo := ORD(bp^);
      bp := BytePtr(addr + 1);
      hi := ORD(bp^);
      sval := INTEGER(lo + hi * 256);
      IF sval >= 32768 THEN
        sval := sval - 65536
      END;
      sample := LFLOAT(sval) / 32768.0D0;
      SetElem(samples, i, sample)
    END
  ELSE
    (* 8-bit unsigned *)
    FOR i := 0 TO totalSamples * info.numChannels - 1 DO
      addr := LONGCARD(rawBuf) + LONGCARD(i);
      bp := BytePtr(addr);
      sample := (LFLOAT(ORD(bp^)) - 128.0D0) / 128.0D0;
      SetElem(samples, i, sample)
    END
  END;

  DEALLOCATE(rawBuf, info.dataSize);
  ok := TRUE
END ReadWav;

PROCEDURE FreeWav(VAR samples: ADDRESS);
BEGIN
  IF samples # NIL THEN
    DEALLOCATE(samples, 0);
    samples := NIL
  END
END FreeWav;

PROCEDURE StereoToMono(stereo: ADDRESS;
                       numFrames: CARDINAL;
                       VAR mono: ADDRESS);
VAR
  i: CARDINAL;
  left, right, avg: LONGREAL;
BEGIN
  ALLOCATE(mono, numFrames * TSIZE(LONGREAL));
  FOR i := 0 TO numFrames - 1 DO
    left := GetElem(stereo, i * 2);
    right := GetElem(stereo, i * 2 + 1);
    avg := (left + right) / 2.0D0;
    SetElem(mono, i, avg)
  END
END StereoToMono;

PROCEDURE FreeMono(VAR mono: ADDRESS);
BEGIN
  IF mono # NIL THEN
    DEALLOCATE(mono, 0);
    mono := NIL
  END
END FreeMono;

(* ── Downsampling via windowed sinc interpolation ──── *)

PROCEDURE Downsample(input: ADDRESS; numSamples, numChannels,
                     srcRate, targetRate: CARDINAL;
                     VAR output: ADDRESS; VAR outSamples: CARDINAL);
CONST
  WinHalf = 16;
  Pi = 3.14159265358979323846D0;
VAR
  ratio: LONGREAL;
  i: CARDINAL;
  srcPos: LONGREAL;
  srcIdx: INTEGER;
  k: INTEGER;
  x, sincVal, winVal, sum, normSum, sampleVal: LONGREAL;
  cutoff: LONGREAL;
  nc: CARDINAL;
BEGIN
  IF (srcRate = 0) OR (targetRate = 0) OR (numSamples = 0) THEN
    output := NIL;
    outSamples := 0;
    RETURN
  END;

  nc := numChannels;
  IF nc = 0 THEN nc := 1 END;

  IF targetRate >= srcRate THEN
    (* No downsampling — just convert stereo to mono if needed *)
    outSamples := numSamples;
    ALLOCATE(output, outSamples * TSIZE(LONGREAL));
    IF nc = 1 THEN
      FOR i := 0 TO numSamples - 1 DO
        SetElem(output, i, GetElem(input, i))
      END
    ELSE
      FOR i := 0 TO numSamples - 1 DO
        SetElem(output, i,
          (GetElem(input, i * 2) + GetElem(input, i * 2 + 1)) / 2.0)
      END
    END;
    RETURN
  END;

  ratio := LFLOAT(srcRate) / LFLOAT(targetRate);
  outSamples := TRUNC(LFLOAT(numSamples) / ratio);
  IF outSamples = 0 THEN
    output := NIL;
    RETURN
  END;

  ALLOCATE(output, outSamples * TSIZE(LONGREAL));

  cutoff := 1.0 / ratio;

  FOR i := 0 TO outSamples - 1 DO
    srcPos := LFLOAT(i) * ratio;

    sum := 0.0;
    normSum := 0.0;

    FOR k := -WinHalf TO WinHalf DO
      srcIdx := TRUNC(srcPos) + k;
      IF (srcIdx >= 0) AND (CARDINAL(srcIdx) < numSamples) THEN
        x := srcPos - LFLOAT(srcIdx);

        (* Sinc function *)
        IF (x > -0.0001) AND (x < 0.0001) THEN
          sincVal := cutoff
        ELSE
          sincVal := LFLOAT(sin(FLOAT(Pi * x * cutoff))) / (Pi * x)
        END;

        (* Lanczos window *)
        IF (x > -0.0001) AND (x < 0.0001) THEN
          winVal := 1.0
        ELSIF (x > LFLOAT(-WinHalf)) AND (x < LFLOAT(WinHalf)) THEN
          winVal := LFLOAT(sin(FLOAT(Pi * x / LFLOAT(WinHalf))))
                    / (Pi * x / LFLOAT(WinHalf))
        ELSE
          winVal := 0.0
        END;

        (* Read sample — average channels if stereo *)
        IF nc = 1 THEN
          sampleVal := GetElem(input, CARDINAL(srcIdx))
        ELSE
          sampleVal := (GetElem(input, CARDINAL(srcIdx) * 2)
                       + GetElem(input, CARDINAL(srcIdx) * 2 + 1)) / 2.0
        END;

        sum := sum + sampleVal * sincVal * winVal;
        normSum := normSum + sincVal * winVal
      END
    END;

    IF (normSum > 0.0001) OR (normSum < -0.0001) THEN
      SetElem(output, i, sum / normSum)
    ELSE
      SetElem(output, i, 0.0)
    END
  END
END Downsample;

PROCEDURE WriteWav(path: ARRAY OF CHAR;
                   samples: ADDRESS;
                   numSamples, sampleRate, numChannels,
                   bitsPerSample: CARDINAL;
                   VAR ok: BOOLEAN);
VAR
  f: INTEGER;
  hdr: ARRAY [0..43] OF CHAR;
  dataSize, fileSize, byteRate, blockAlign: CARDINAL;
  i, totalElems: CARDINAL;
  rawBuf: ADDRESS;
  bp: BytePtr;
  addr: LONGCARD;
  sample: LONGREAL;
  sval: INTEGER;
  uval: CARDINAL;
  n: INTEGER;
  modeWb: ARRAY [0..2] OF CHAR;
  dummy: INTEGER;
BEGIN
  ok := FALSE;

  blockAlign := numChannels * (bitsPerSample DIV 8);
  byteRate := sampleRate * blockAlign;
  totalElems := numSamples * numChannels;
  dataSize := totalElems * (bitsPerSample DIV 8);
  fileSize := 36 + dataSize;

  (* Build 44-byte header *)
  hdr[0] := 'R'; hdr[1] := 'I'; hdr[2] := 'F'; hdr[3] := 'F';
  Put32(hdr, 4, fileSize);
  hdr[8] := 'W'; hdr[9] := 'A'; hdr[10] := 'V'; hdr[11] := 'E';
  hdr[12] := 'f'; hdr[13] := 'm'; hdr[14] := 't'; hdr[15] := ' ';
  Put32(hdr, 16, 16);
  Put16(hdr, 20, 1);
  Put16(hdr, 22, numChannels);
  Put32(hdr, 24, sampleRate);
  Put32(hdr, 28, byteRate);
  Put16(hdr, 32, blockAlign);
  Put16(hdr, 34, bitsPerSample);
  hdr[36] := 'd'; hdr[37] := 'a'; hdr[38] := 't'; hdr[39] := 'a';
  Put32(hdr, 40, dataSize);

  (* Convert LONGREAL samples to raw PCM *)
  ALLOCATE(rawBuf, dataSize);

  IF bitsPerSample = 16 THEN
    FOR i := 0 TO totalElems - 1 DO
      sample := GetElem(samples, i);
      IF sample > 1.0D0 THEN
        sample := 1.0D0
      ELSIF sample < -1.0D0 THEN
        sample := -1.0D0
      END;
      sval := TRUNC(sample * 32767.0D0);
      IF sval < 0 THEN
        uval := CARDINAL(sval + 65536)
      ELSE
        uval := CARDINAL(sval)
      END;
      addr := LONGCARD(rawBuf) + LONGCARD(i * 2);
      bp := BytePtr(addr);
      bp^ := CHR(uval MOD 256);
      addr := LONGCARD(rawBuf) + LONGCARD(i * 2 + 1);
      bp := BytePtr(addr);
      bp^ := CHR((uval DIV 256) MOD 256)
    END
  ELSE
    FOR i := 0 TO totalElems - 1 DO
      sample := GetElem(samples, i);
      IF sample > 1.0D0 THEN
        sample := 1.0D0
      ELSIF sample < -1.0D0 THEN
        sample := -1.0D0
      END;
      sval := TRUNC(sample * 128.0D0) + 128;
      IF sval < 0 THEN
        sval := 0
      ELSIF sval > 255 THEN
        sval := 255
      END;
      addr := LONGCARD(rawBuf) + LONGCARD(i);
      bp := BytePtr(addr);
      bp^ := CHR(sval)
    END
  END;

  modeWb[0] := 'w'; modeWb[1] := 'b'; modeWb[2] := 0C;
  f := m2sys_fopen(ADR(path), ADR(modeWb));
  IF f < 0 THEN
    DEALLOCATE(rawBuf, dataSize);
    RETURN
  END;

  n := m2sys_fwrite_bytes(f, ADR(hdr), 44);
  IF n # 44 THEN
    dummy := m2sys_fclose(f);
    DEALLOCATE(rawBuf, dataSize);
    RETURN
  END;

  n := m2sys_fwrite_bytes(f, rawBuf, INTEGER(dataSize));
  dummy := m2sys_fclose(f);
  DEALLOCATE(rawBuf, dataSize);

  IF n # INTEGER(dataSize) THEN
    RETURN
  END;

  ok := TRUE
END WriteWav;

PROCEDURE GetDuration(VAR info: WavInfo): LONGREAL;
BEGIN
  IF info.sampleRate = 0 THEN
    RETURN 0.0D0
  END;
  RETURN LFLOAT(info.numSamples) / LFLOAT(info.sampleRate)
END GetDuration;

END Wav.
