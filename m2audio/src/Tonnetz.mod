IMPLEMENTATION MODULE Tonnetz;

FROM MathLib IMPORT sin, cos;
FROM MathUtil IMPORT Pi;

(* ComputeTonnetz -- map 12-element chroma to 6 tonnetz dimensions.
   Standard librosa tonnetz mapping using pitch class to tonal space:
     [0] = sum(chroma[i] * sin(i * pi/2))     fifths y
     [1] = sum(chroma[i] * cos(i * pi/2))     fifths x
     [2] = sum(chroma[i] * sin(i * 2*pi/3))   minor thirds y
     [3] = sum(chroma[i] * cos(i * 2*pi/3))   minor thirds x
     [4] = sum(chroma[i] * sin(i * 7*pi/6))   major thirds y
     [5] = sum(chroma[i] * cos(i * 7*pi/6))   major thirds x  *)

PROCEDURE ComputeTonnetz(chroma: ARRAY OF LONGREAL;
                          VAR tonnetz: ARRAY OF LONGREAL);
VAR
  i: CARDINAL;
  angle0, angle1, angle2: LONGREAL;
  c: LONGREAL;
  fifthsCoeff, minorCoeff, majorCoeff: LONGREAL;
BEGIN
  (* Initialize output *)
  IF HIGH(tonnetz) < 5 THEN RETURN END;

  tonnetz[0] := 0.0;
  tonnetz[1] := 0.0;
  tonnetz[2] := 0.0;
  tonnetz[3] := 0.0;
  tonnetz[4] := 0.0;
  tonnetz[5] := 0.0;

  fifthsCoeff := Pi / 2.0;
  minorCoeff := 2.0 * Pi / 3.0;
  majorCoeff := 7.0 * Pi / 6.0;

  FOR i := 0 TO 11 DO
    c := chroma[i];

    angle0 := LFLOAT(i) * fifthsCoeff;
    tonnetz[0] := tonnetz[0] + c * LFLOAT(sin(FLOAT(angle0)));
    tonnetz[1] := tonnetz[1] + c * LFLOAT(cos(FLOAT(angle0)));

    angle1 := LFLOAT(i) * minorCoeff;
    tonnetz[2] := tonnetz[2] + c * LFLOAT(sin(FLOAT(angle1)));
    tonnetz[3] := tonnetz[3] + c * LFLOAT(cos(FLOAT(angle1)));

    angle2 := LFLOAT(i) * majorCoeff;
    tonnetz[4] := tonnetz[4] + c * LFLOAT(sin(FLOAT(angle2)));
    tonnetz[5] := tonnetz[5] + c * LFLOAT(cos(FLOAT(angle2)))
  END
END ComputeTonnetz;

END Tonnetz.
