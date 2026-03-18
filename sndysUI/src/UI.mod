IMPLEMENTATION MODULE UI;

FROM Gfx IMPORT Renderer;
FROM Font IMPORT FontHandle, Open, OpenPhysical, Close, Height, TextWidth,
                 DrawText, DpiScale, SetHinting, HINT_MONO;
FROM Canvas IMPORT SetColor, Clear, FillRect, DrawRect, FillCircle;
FROM Color IMPORT Pack, UnpackR, UnpackG, UnpackB;
FROM Strings IMPORT Assign;
FROM MathUtil IMPORT FAbs;

(* ── Theme ────────────────────────────────────────────── *)

PROCEDURE InitTheme;
BEGIN
  colBg        := Pack(30, 30, 34);
  colPanel     := Pack(42, 42, 48);
  colToolbar   := Pack(50, 50, 56);
  colTab       := Pack(55, 55, 62);
  colTabActive := Pack(70, 70, 80);
  colText      := Pack(220, 220, 225);
  colTextDim   := Pack(140, 140, 150);
  colAccent    := Pack(80, 160, 240);
  colWave      := Pack(100, 200, 120);
  colSelection := Pack(80, 160, 240);
  colGrid      := Pack(55, 55, 62);
  colBorder    := Pack(65, 65, 72);
  colButton    := Pack(60, 60, 68);
  colButtonHover := Pack(75, 75, 85);
  colRed       := Pack(220, 80, 80);
  colGreen     := Pack(80, 200, 120);
  colYellow    := Pack(220, 200, 80);
  colCyan      := Pack(80, 200, 220)
END InitTheme;

(* ── Fonts ────────────────────────────────────────────── *)

PROCEDURE TryFont(path: ARRAY OF CHAR; size: INTEGER): FontHandle;
BEGIN
  RETURN OpenPhysical(path, size * DpiScale())
END TryFont;

PROCEDURE LoadFonts(): BOOLEAN;
BEGIN
  (* Font sizes: logical points, scaled to physical by TryFont *)
  fontNormal := TryFont("/System/Library/Fonts/SFNSMono.ttf", 14);
  IF fontNormal = NIL THEN
    fontNormal := TryFont("/System/Library/Fonts/Menlo.ttc", 14)
  END;
  IF fontNormal = NIL THEN
    fontNormal := TryFont("/System/Library/Fonts/Monaco.ttf", 14)
  END;
  IF fontNormal = NIL THEN
    fontNormal := TryFont("/Library/Fonts/Courier New.ttf", 14)
  END;
  IF fontNormal = NIL THEN RETURN FALSE END;

  fontSmall := TryFont("/System/Library/Fonts/SFNSMono.ttf", 12);
  IF fontSmall = NIL THEN
    fontSmall := TryFont("/System/Library/Fonts/Menlo.ttc", 12)
  END;
  IF fontSmall = NIL THEN fontSmall := fontNormal END;

  fontBold := fontNormal;

  SetHinting(fontNormal, HINT_MONO);
  IF fontSmall # fontNormal THEN SetHinting(fontSmall, HINT_MONO) END;

  lineH := Height(fontNormal) + 2;
  smallH := Height(fontSmall) + 2;
  RETURN TRUE
END LoadFonts;

PROCEDURE FreeFonts;
BEGIN
  IF fontNormal # NIL THEN Close(fontNormal) END;
  IF (fontSmall # NIL) AND (fontSmall # fontNormal) THEN Close(fontSmall) END
END FreeFonts;

(* ── Drawing helpers ──────────────────────────────────── *)

PROCEDURE SetCol(ren: Renderer; packed: CARDINAL);
BEGIN
  SetColor(ren, UnpackR(packed), UnpackG(packed), UnpackB(packed), 255)
END SetCol;

PROCEDURE Label(ren: Renderer; x, y: INTEGER; text: ARRAY OF CHAR;
                col: CARDINAL);
BEGIN
  DrawText(ren, fontNormal, text, x, y,
           UnpackR(col), UnpackG(col), UnpackB(col), 255)
END Label;

PROCEDURE LabelSmall(ren: Renderer; x, y: INTEGER; text: ARRAY OF CHAR;
                     col: CARDINAL);
BEGIN
  DrawText(ren, fontSmall, text, x, y,
           UnpackR(col), UnpackG(col), UnpackB(col), 255)
END LabelSmall;

PROCEDURE LabelBold(ren: Renderer; x, y: INTEGER; text: ARRAY OF CHAR;
                    col: CARDINAL);
BEGIN
  DrawText(ren, fontBold, text, x, y,
           UnpackR(col), UnpackG(col), UnpackB(col), 255)
END LabelBold;

PROCEDURE Panel(ren: Renderer; x, y, w, h: INTEGER; col: CARDINAL);
BEGIN
  SetCol(ren, col);
  FillRect(ren, x, y, w, h)
END Panel;

PROCEDURE PanelBorder(ren: Renderer; x, y, w, h: INTEGER;
                       bg, border: CARDINAL);
BEGIN
  SetCol(ren, bg);
  FillRect(ren, x, y, w, h);
  SetCol(ren, border);
  DrawRect(ren, x, y, w, h)
END PanelBorder;

(* ── Buttons ──────────────────────────────────────────── *)

PROCEDURE InRect(px, py, rx, ry, rw, rh: INTEGER): BOOLEAN;
BEGIN
  RETURN (px >= rx) AND (px < rx + rw) AND
         (py >= ry) AND (py < ry + rh)
END InRect;

PROCEDURE Button(ren: Renderer; x, y, w, h: INTEGER;
                 text: ARRAY OF CHAR;
                 mx, my: INTEGER; clicked: BOOLEAN): BOOLEAN;
VAR hover: BOOLEAN; tw, tx, ty: INTEGER;
BEGIN
  hover := InRect(mx, my, x, y, w, h);
  IF hover THEN
    Panel(ren, x, y, w, h, colButtonHover)
  ELSE
    Panel(ren, x, y, w, h, colButton)
  END;
  SetCol(ren, colBorder);
  DrawRect(ren, x, y, w, h);

  tw := TextWidth(fontNormal, text);
  tx := x + (w - tw) DIV 2;
  ty := y + (h - lineH) DIV 2;
  Label(ren, tx, ty, text, colText);

  RETURN hover AND clicked
END Button;

PROCEDURE GetTabLabel(VAR t0, t1, t2, t3, t4, t5, t6, t7: ARRAY OF CHAR;
                       idx: CARDINAL;
                       VAR out: ARRAY OF CHAR);
BEGIN
  CASE idx OF
    0: Assign(t0, out) |
    1: Assign(t1, out) |
    2: Assign(t2, out) |
    3: Assign(t3, out) |
    4: Assign(t4, out) |
    5: Assign(t5, out) |
    6: Assign(t6, out) |
    7: Assign(t7, out)
  ELSE
    out[0] := 0C
  END
END GetTabLabel;

PROCEDURE TabBar(ren: Renderer; x, y, w: INTEGER;
                 VAR t0, t1, t2, t3, t4, t5, t6, t7: ARRAY OF CHAR;
                 numTabs, current: CARDINAL;
                 mx, my: INTEGER; clicked: BOOLEAN): CARDINAL;
VAR
  i: CARDINAL;
  tabW, tx: INTEGER;
  result: CARDINAL;
  hover: BOOLEAN;
  tw, lx: INTEGER;
  h: INTEGER;
  lbl: ARRAY [0..31] OF CHAR;
BEGIN
  result := current;
  IF numTabs = 0 THEN RETURN result END;
  h := lineH + 8;
  tabW := w DIV INTEGER(numTabs);

  (* Background *)
  Panel(ren, x, y, w, h, colPanel);

  FOR i := 0 TO numTabs - 1 DO
    tx := x + INTEGER(i) * tabW;
    hover := InRect(mx, my, tx, y, tabW, h);

    IF i = current THEN
      Panel(ren, tx, y, tabW, h, colTabActive);
      SetCol(ren, colAccent);
      FillRect(ren, tx, y + h - 2, tabW, 2)
    ELSIF hover THEN
      Panel(ren, tx, y, tabW, h, colTab)
    END;

    GetTabLabel(t0, t1, t2, t3, t4, t5, t6, t7, i, lbl);
    tw := TextWidth(fontNormal, lbl);
    lx := tx + (tabW - tw) DIV 2;
    IF i = current THEN
      Label(ren, lx, y + 4, lbl, colText)
    ELSE
      Label(ren, lx, y + 4, lbl, colTextDim)
    END;

    IF hover AND clicked THEN
      result := i
    END
  END;

  RETURN result
END TabBar;

(* ── Modal overlay ────────────────────────────────────── *)

PROCEDURE ModalOverlay(ren: Renderer; winW, winH: INTEGER;
                        msg: ARRAY OF CHAR; tick: CARDINAL);
CONST
  BoxW = 320;
  BoxH = 100;
  NumDots = 8;
  DotRadius = 4;
  SpinRadius = 20;
VAR
  bx, by, cx, cy, i: INTEGER;
  tw: INTEGER;
  phase: CARDINAL;
  dx, dy: INTEGER;
  alpha: INTEGER;
  spinnerMsg: ARRAY [0..31] OF CHAR;
BEGIN
  (* Dim background *)
  SetColor(ren, 0, 0, 0, 160);
  FillRect(ren, 0, 0, winW, winH);

  (* Centered box *)
  bx := (winW - BoxW) DIV 2;
  by := (winH - BoxH) DIV 2;
  Panel(ren, bx, by, BoxW, BoxH, colPanel);
  SetCol(ren, colBorder);
  DrawRect(ren, bx, by, BoxW, BoxH);

  (* Spinner: rotating dots *)
  cx := bx + BoxW DIV 2;
  cy := by + 32;
  phase := tick MOD CARDINAL(NumDots);

  FOR i := 0 TO NumDots - 1 DO
    (* Position: circle of dots *)
    CASE i OF
      0: dx :=  0; dy := -SpinRadius |
      1: dx :=  14; dy := -14 |
      2: dx :=  SpinRadius; dy :=  0 |
      3: dx :=  14; dy :=  14 |
      4: dx :=  0; dy :=  SpinRadius |
      5: dx := -14; dy :=  14 |
      6: dx := -SpinRadius; dy :=  0 |
      7: dx := -14; dy := -14
    END;

    (* Brightness based on distance from active phase *)
    alpha := 255 - ((CARDINAL(NumDots) + CARDINAL(i) - phase) MOD CARDINAL(NumDots)) * 28;
    IF alpha < 60 THEN alpha := 60 END;
    SetColor(ren, UnpackR(colAccent), UnpackG(colAccent),
             UnpackB(colAccent), alpha);
    FillCircle(ren, cx + dx, cy + dy, DotRadius)
  END;

  (* Message text *)
  tw := TextWidth(fontNormal, msg);
  Label(ren, bx + (BoxW - tw) DIV 2, by + BoxH - lineH - 24, msg, colText);

  (* Cancel hint *)
  Assign("ESC to cancel", spinnerMsg);
  tw := TextWidth(fontSmall, spinnerMsg);
  LabelSmall(ren, bx + (BoxW - tw) DIV 2, by + BoxH - smallH - 6,
             spinnerMsg, colTextDim)
END ModalOverlay;

(* ── Number formatting ────────────────────────────────── *)

PROCEDURE FmtCard(x: CARDINAL; VAR buf: ARRAY OF CHAR);
VAR
  tmp: ARRAY [0..15] OF CHAR;
  i, j, len: CARDINAL;
  d: CARDINAL;
BEGIN
  IF x = 0 THEN
    buf[0] := '0'; buf[1] := 0C; RETURN
  END;
  len := 0;
  d := x;
  WHILE d > 0 DO
    tmp[len] := CHR(ORD('0') + d MOD 10);
    d := d DIV 10;
    INC(len)
  END;
  j := 0;
  FOR i := 1 TO len DO
    IF j <= HIGH(buf) THEN
      buf[j] := tmp[len - i];
      INC(j)
    END
  END;
  IF j <= HIGH(buf) THEN buf[j] := 0C END
END FmtCard;

PROCEDURE FmtInt(x: INTEGER; VAR buf: ARRAY OF CHAR);
VAR pos: CARDINAL;
BEGIN
  IF x < 0 THEN
    buf[0] := '-';
    FmtCard(CARDINAL(-x), buf);
    (* shift *)
    pos := 0;
    WHILE (pos <= HIGH(buf)) AND (buf[pos] # 0C) DO INC(pos) END;
    WHILE pos > 0 DO
      IF pos <= HIGH(buf) THEN buf[pos] := buf[pos - 1] END;
      DEC(pos)
    END;
    buf[0] := '-'
  ELSE
    FmtCard(CARDINAL(x), buf)
  END
END FmtInt;

PROCEDURE FmtReal(x: LONGREAL; decimals: CARDINAL;
                  VAR buf: ARRAY OF CHAR);
VAR
  intPart: CARDINAL;
  fracPart: CARDINAL;
  neg: BOOLEAN;
  pos, i: CARDINAL;
  mult: CARDINAL;
  v: LONGREAL;
  tmp: ARRAY [0..15] OF CHAR;
BEGIN
  neg := x < 0.0;
  IF neg THEN v := -x ELSE v := x END;

  intPart := TRUNC(v);
  mult := 1;
  FOR i := 1 TO decimals DO mult := mult * 10 END;
  fracPart := TRUNC((v - LFLOAT(intPart)) * LFLOAT(mult) + 0.5);
  IF fracPart >= mult THEN
    INC(intPart);
    fracPart := 0
  END;

  pos := 0;
  IF neg THEN
    IF pos <= HIGH(buf) THEN buf[pos] := '-'; INC(pos) END
  END;

  FmtCard(intPart, tmp);
  i := 0;
  WHILE (i <= HIGH(tmp)) AND (tmp[i] # 0C) DO
    IF pos <= HIGH(buf) THEN buf[pos] := tmp[i]; INC(pos) END;
    INC(i)
  END;

  IF decimals > 0 THEN
    IF pos <= HIGH(buf) THEN buf[pos] := '.'; INC(pos) END;
    FmtCard(fracPart, tmp);
    (* pad with leading zeros *)
    i := 0;
    WHILE (i <= HIGH(tmp)) AND (tmp[i] # 0C) DO INC(i) END;
    WHILE i < decimals DO
      IF pos <= HIGH(buf) THEN buf[pos] := '0'; INC(pos) END;
      INC(i)
    END;
    i := 0;
    WHILE (i <= HIGH(tmp)) AND (tmp[i] # 0C) DO
      IF pos <= HIGH(buf) THEN buf[pos] := tmp[i]; INC(pos) END;
      INC(i)
    END
  END;

  IF pos <= HIGH(buf) THEN buf[pos] := 0C END
END FmtReal;

END UI.
