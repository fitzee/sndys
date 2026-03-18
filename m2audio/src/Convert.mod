IMPLEMENTATION MODULE Convert;

FROM SYSTEM IMPORT ADDRESS, ADR;
FROM Strings IMPORT Length, Assign, Concat;
FROM Sys IMPORT m2sys_exec;

PROCEDURE ToLower(ch: CHAR): CHAR;
BEGIN
  IF (ch >= 'A') AND (ch <= 'Z') THEN
    RETURN CHR(ORD(ch) + 32)
  END;
  RETURN ch
END ToLower;

PROCEDURE EndsWith(path, ext: ARRAY OF CHAR): BOOLEAN;
VAR pLen, eLen, i: INTEGER;
BEGIN
  pLen := Length(path);
  eLen := Length(ext);
  IF pLen < eLen THEN RETURN FALSE END;
  FOR i := 0 TO eLen - 1 DO
    IF ToLower(path[pLen - eLen + i]) # ToLower(ext[i]) THEN
      RETURN FALSE
    END
  END;
  RETURN TRUE
END EndsWith;

PROCEDURE IsWavFile(path: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN EndsWith(path, ".wav")
END IsWavFile;

PROCEDURE NeedsConversion(path: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN NOT IsWavFile(path)
END NeedsConversion;

PROCEDURE ConvertToWav(inPath: ARRAY OF CHAR;
                       outPath: ARRAY OF CHAR;
                       sampleRate: CARDINAL;
                       VAR ok: BOOLEAN);
VAR
  cmd: ARRAY [0..1023] OF CHAR;
  rateStr: ARRAY [0..15] OF CHAR;
  quote: ARRAY [0..1] OF CHAR;
  result: INTEGER;
  digit: CARDINAL;
  r, pos: CARDINAL;
  cmdLen, inLen, outLen: CARDINAL;
BEGIN
  ok := FALSE;

  (* Build sample rate string *)
  r := sampleRate;
  pos := 0;
  IF r = 0 THEN
    rateStr[0] := '0'; pos := 1
  ELSE
    (* Write digits in reverse, then reverse *)
    WHILE r > 0 DO
      rateStr[pos] := CHR(ORD('0') + r MOD 10);
      r := r DIV 10;
      INC(pos)
    END;
    (* Reverse *)
    FOR digit := 0 TO pos DIV 2 - 1 DO
      r := ORD(rateStr[digit]);
      rateStr[digit] := rateStr[pos - 1 - digit];
      rateStr[pos - 1 - digit] := CHR(r)
    END
  END;
  rateStr[pos] := 0C;

  (* Check total length before building command *)
  inLen := Length(inPath);
  outLen := Length(outPath);
  (* Base parts: prefix(46) + 2 quotes + inPath + " -ac 1 -ar "(11) + rate(max 15) + " -acodec pcm_s16le "(19) + 2 quotes + outPath *)
  cmdLen := 46 + 2 + inLen + 11 + pos + 19 + 2 + outLen;
  IF cmdLen > 1023 THEN ok := FALSE; RETURN END;

  (* Build command: ffmpeg -y -i "inPath" -ac 1 -ar <rate> -acodec pcm_s16le "outPath" *)
  quote[0] := 42C; quote[1] := 0C;
  Assign("ffmpeg -y -hide_banner -loglevel error -i ", cmd);
  Concat(cmd, quote, cmd);
  Concat(cmd, inPath, cmd);
  Concat(cmd, quote, cmd);
  Concat(cmd, " -ac 1 -ar ", cmd);
  Concat(cmd, rateStr, cmd);
  Concat(cmd, " -acodec pcm_s16le ", cmd);
  Concat(cmd, quote, cmd);
  Concat(cmd, outPath, cmd);
  Concat(cmd, quote, cmd);

  result := m2sys_exec(ADR(cmd));
  ok := result = 0
END ConvertToWav;

END Convert.
