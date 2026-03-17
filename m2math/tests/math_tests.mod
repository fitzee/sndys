MODULE MathTests;
(* Deterministic test suite for m2math.

   Tests:
     1. Log10 known values
     2. Log2 known values
     3. Pow basic cases and edge cases
     4. Floor positive and negative values
     5. Ceil positive and negative values
     6. FAbs positive, negative, zero
     7. FMod basic cases
     8. Clamp within range, below, above
     9. Hypot known triangles
    10. NextPow2 various inputs
    11. IsPow2 powers and non-powers *)

FROM InOut IMPORT WriteString, WriteLn, WriteInt;
FROM MathUtil IMPORT Pi, TwoPi, Ln10, E,
                     Log10, Log2, Pow, Floor, Ceil,
                     FAbs, FMod, Clamp, Hypot,
                     NextPow2, IsPow2;

VAR
  passed, failed, total: INTEGER;

PROCEDURE Check(name: ARRAY OF CHAR; cond: BOOLEAN);
BEGIN
  INC(total);
  IF cond THEN
    INC(passed)
  ELSE
    INC(failed);
    WriteString("FAIL: "); WriteString(name); WriteLn
  END
END Check;

(* Helper: check that two LONGREALs are close within tolerance *)
PROCEDURE Near(a, b, tol: LONGREAL): BOOLEAN;
VAR diff: LONGREAL;
BEGIN
  diff := a - b;
  IF diff < 0.0D0 THEN diff := -diff END;
  RETURN diff < tol
END Near;

(* ── Test 1: Log10 known values ──────────────────── *)

PROCEDURE TestLog10;
BEGIN
  Check("log10: 1.0 = 0.0", Near(Log10(1.0D0), 0.0D0, 0.0001D0));
  Check("log10: 10.0 = 1.0", Near(Log10(10.0D0), 1.0D0, 0.0001D0));
  Check("log10: 100.0 = 2.0", Near(Log10(100.0D0), 2.0D0, 0.0001D0));
  Check("log10: 1000.0 = 3.0", Near(Log10(1000.0D0), 3.0D0, 0.0001D0));
  Check("log10: 0.1 = -1.0", Near(Log10(0.1D0), -1.0D0, 0.001D0));
  Check("log10: 0.01 = -2.0", Near(Log10(0.01D0), -2.0D0, 0.001D0))
END TestLog10;

(* ── Test 2: Log2 known values ───────────────────── *)

PROCEDURE TestLog2;
BEGIN
  Check("log2: 1.0 = 0.0", Near(Log2(1.0D0), 0.0D0, 0.0001D0));
  Check("log2: 2.0 = 1.0", Near(Log2(2.0D0), 1.0D0, 0.0001D0));
  Check("log2: 4.0 = 2.0", Near(Log2(4.0D0), 2.0D0, 0.0001D0));
  Check("log2: 8.0 = 3.0", Near(Log2(8.0D0), 3.0D0, 0.0001D0));
  Check("log2: 1024.0 = 10.0", Near(Log2(1024.0D0), 10.0D0, 0.001D0));
  Check("log2: 0.5 = -1.0", Near(Log2(0.5D0), -1.0D0, 0.0001D0))
END TestLog2;

(* ── Test 3: Pow basic and edge cases ────────────── *)

PROCEDURE TestPow;
BEGIN
  Check("pow: 2^0 = 1", Near(Pow(2.0D0, 0.0D0), 1.0D0, 0.0001D0));
  Check("pow: 2^1 = 2", Near(Pow(2.0D0, 1.0D0), 2.0D0, 0.0001D0));
  Check("pow: 2^10 = 1024", Near(Pow(2.0D0, 10.0D0), 1024.0D0, 0.1D0));
  Check("pow: 3^3 = 27", Near(Pow(3.0D0, 3.0D0), 27.0D0, 0.01D0));
  Check("pow: 10^2 = 100", Near(Pow(10.0D0, 2.0D0), 100.0D0, 0.1D0));
  Check("pow: 0^5 = 0", Near(Pow(0.0D0, 5.0D0), 0.0D0, 0.0001D0));
  Check("pow: 0^0 = 1", Near(Pow(0.0D0, 0.0D0), 1.0D0, 0.0001D0));
  Check("pow: 4^0.5 = 2", Near(Pow(4.0D0, 0.5D0), 2.0D0, 0.001D0));
  Check("pow: 27^(1/3) ~ 3", Near(Pow(27.0D0, 0.333333D0), 3.0D0, 0.01D0))
END TestPow;

(* ── Test 4: Floor ───────────────────────────────── *)

PROCEDURE TestFloor;
BEGIN
  Check("floor: 2.7 = 2", Floor(2.7D0) = 2);
  Check("floor: 2.0 = 2", Floor(2.0D0) = 2);
  Check("floor: 0.5 = 0", Floor(0.5D0) = 0);
  Check("floor: 0.0 = 0", Floor(0.0D0) = 0);
  Check("floor: -0.5 = -1", Floor(-0.5D0) = -1);
  Check("floor: -2.0 = -2", Floor(-2.0D0) = -2);
  Check("floor: -2.3 = -3", Floor(-2.3D0) = -3);
  Check("floor: 99.99 = 99", Floor(99.99D0) = 99)
END TestFloor;

(* ── Test 5: Ceil ────────────────────────────────── *)

PROCEDURE TestCeil;
BEGIN
  Check("ceil: 2.1 = 3", Ceil(2.1D0) = 3);
  Check("ceil: 2.0 = 2", Ceil(2.0D0) = 2);
  Check("ceil: 0.1 = 1", Ceil(0.1D0) = 1);
  Check("ceil: 0.0 = 0", Ceil(0.0D0) = 0);
  Check("ceil: -0.5 = 0", Ceil(-0.5D0) = 0);
  Check("ceil: -2.0 = -2", Ceil(-2.0D0) = -2);
  Check("ceil: -2.3 = -2", Ceil(-2.3D0) = -2)
END TestCeil;

(* ── Test 6: FAbs ────────────────────────────────── *)

PROCEDURE TestFAbs;
BEGIN
  Check("fabs: 3.14 = 3.14", Near(FAbs(3.14D0), 3.14D0, 0.0001D0));
  Check("fabs: -3.14 = 3.14", Near(FAbs(-3.14D0), 3.14D0, 0.0001D0));
  Check("fabs: 0.0 = 0.0", Near(FAbs(0.0D0), 0.0D0, 0.0001D0));
  Check("fabs: -0.0 = 0.0", Near(FAbs(-0.0D0), 0.0D0, 0.0001D0));
  Check("fabs: -1000.5 = 1000.5", Near(FAbs(-1000.5D0), 1000.5D0, 0.0001D0))
END TestFAbs;

(* ── Test 7: FMod ────────────────────────────────── *)

PROCEDURE TestFMod;
BEGIN
  Check("fmod: 5.5/2.0 = 1.5", Near(FMod(5.5D0, 2.0D0), 1.5D0, 0.0001D0));
  Check("fmod: 10.0/3.0 ~ 1.0", Near(FMod(10.0D0, 3.0D0), 1.0D0, 0.0001D0));
  Check("fmod: 7.0/7.0 = 0.0", Near(FMod(7.0D0, 7.0D0), 0.0D0, 0.0001D0));
  Check("fmod: 1.0/3.0 = 1.0", Near(FMod(1.0D0, 3.0D0), 1.0D0, 0.0001D0))
END TestFMod;

(* ── Test 8: Clamp ───────────────────────────────── *)

PROCEDURE TestClamp;
BEGIN
  Check("clamp: 5 in [0,10] = 5", Near(Clamp(5.0D0, 0.0D0, 10.0D0), 5.0D0, 0.0001D0));
  Check("clamp: -1 in [0,10] = 0", Near(Clamp(-1.0D0, 0.0D0, 10.0D0), 0.0D0, 0.0001D0));
  Check("clamp: 15 in [0,10] = 10", Near(Clamp(15.0D0, 0.0D0, 10.0D0), 10.0D0, 0.0001D0));
  Check("clamp: 0 in [0,10] = 0", Near(Clamp(0.0D0, 0.0D0, 10.0D0), 0.0D0, 0.0001D0));
  Check("clamp: 10 in [0,10] = 10", Near(Clamp(10.0D0, 0.0D0, 10.0D0), 10.0D0, 0.0001D0));
  Check("clamp: -5 in [-3,-1] = -3", Near(Clamp(-5.0D0, -3.0D0, -1.0D0), -3.0D0, 0.0001D0))
END TestClamp;

(* ── Test 9: Hypot known triangles ───────────────── *)

PROCEDURE TestHypot;
BEGIN
  Check("hypot: 3,4 = 5", Near(Hypot(3.0D0, 4.0D0), 5.0D0, 0.001D0));
  Check("hypot: 5,12 = 13", Near(Hypot(5.0D0, 12.0D0), 13.0D0, 0.001D0));
  Check("hypot: 0,5 = 5", Near(Hypot(0.0D0, 5.0D0), 5.0D0, 0.001D0));
  Check("hypot: 1,0 = 1", Near(Hypot(1.0D0, 0.0D0), 1.0D0, 0.001D0));
  Check("hypot: 1,1 ~ 1.414", Near(Hypot(1.0D0, 1.0D0), 1.41421D0, 0.001D0));
  Check("hypot: 8,15 = 17", Near(Hypot(8.0D0, 15.0D0), 17.0D0, 0.001D0))
END TestHypot;

(* ── Test 10: NextPow2 ──────────────────────────── *)

PROCEDURE TestNextPow2;
BEGIN
  Check("np2: 0 = 1", NextPow2(0) = 1);
  Check("np2: 1 = 1", NextPow2(1) = 1);
  Check("np2: 2 = 2", NextPow2(2) = 2);
  Check("np2: 3 = 4", NextPow2(3) = 4);
  Check("np2: 4 = 4", NextPow2(4) = 4);
  Check("np2: 5 = 8", NextPow2(5) = 8);
  Check("np2: 7 = 8", NextPow2(7) = 8);
  Check("np2: 8 = 8", NextPow2(8) = 8);
  Check("np2: 9 = 16", NextPow2(9) = 16);
  Check("np2: 255 = 256", NextPow2(255) = 256);
  Check("np2: 256 = 256", NextPow2(256) = 256);
  Check("np2: 257 = 512", NextPow2(257) = 512);
  Check("np2: 1000 = 1024", NextPow2(1000) = 1024);
  Check("np2: 1024 = 1024", NextPow2(1024) = 1024)
END TestNextPow2;

(* ── Test 11: IsPow2 ────────────────────────────── *)

PROCEDURE TestIsPow2;
BEGIN
  Check("ip2: 0 = FALSE", NOT IsPow2(0));
  Check("ip2: 1 = TRUE", IsPow2(1));
  Check("ip2: 2 = TRUE", IsPow2(2));
  Check("ip2: 3 = FALSE", NOT IsPow2(3));
  Check("ip2: 4 = TRUE", IsPow2(4));
  Check("ip2: 5 = FALSE", NOT IsPow2(5));
  Check("ip2: 6 = FALSE", NOT IsPow2(6));
  Check("ip2: 7 = FALSE", NOT IsPow2(7));
  Check("ip2: 8 = TRUE", IsPow2(8));
  Check("ip2: 16 = TRUE", IsPow2(16));
  Check("ip2: 15 = FALSE", NOT IsPow2(15));
  Check("ip2: 256 = TRUE", IsPow2(256));
  Check("ip2: 1024 = TRUE", IsPow2(1024));
  Check("ip2: 1023 = FALSE", NOT IsPow2(1023))
END TestIsPow2;

(* ── Test 12: Constants ─────────────────────────── *)

PROCEDURE TestConstants;
BEGIN
  Check("const: Pi ~ 3.14159", Near(Pi, 3.14159D0, 0.00001D0));
  Check("const: TwoPi ~ 6.28318", Near(TwoPi, 6.28318D0, 0.00001D0));
  Check("const: TwoPi = 2*Pi", Near(TwoPi, 2.0D0 * Pi, 0.00001D0));
  Check("const: Ln10 ~ 2.30258", Near(Ln10, 2.30258D0, 0.00001D0));
  Check("const: E ~ 2.71828", Near(E, 2.71828D0, 0.00001D0))
END TestConstants;

BEGIN
  passed := 0;
  failed := 0;
  total := 0;

  WriteString("m2math test suite"); WriteLn;
  WriteString("================="); WriteLn;

  TestLog10;
  TestLog2;
  TestPow;
  TestFloor;
  TestCeil;
  TestFAbs;
  TestFMod;
  TestClamp;
  TestHypot;
  TestNextPow2;
  TestIsPow2;
  TestConstants;

  WriteLn;
  WriteInt(total, 0); WriteString(" tests, ");
  WriteInt(passed, 0); WriteString(" passed, ");
  WriteInt(failed, 0); WriteString(" failed"); WriteLn;

  IF failed > 0 THEN
    WriteString("*** FAILURES ***"); WriteLn
  ELSE
    WriteString("*** ALL TESTS PASSED ***"); WriteLn
  END
END MathTests.
