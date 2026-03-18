# Ralph Loop Issue Ledger

## Iteration 1

[R1-01] [fixed] DTree.mod/Init — numClasses not clamped to array size [0..31]; bounds violation if numClasses > 32
[R1-02] [fixed] DTree.mod/MajorityClass,FindBestSplit — local arrays [0..31] indexed by unclamped numClasses
[R1-03] [fixed] Forest.mod/Train — selected[0..255] indexed by unclamped numFeatures; bounds violation if > 256
[R1-04] [fixed] Forest.mod/Train — seed MOD numFeatures with numFeatures=0 causes div-by-zero
[R1-05] [fixed] GBoost.mod/Predict — scores[0..31] indexed by unclamped numClasses; bounds violation if > 32
[R1-06] [fixed] HMM.mod/Init — 1.0/LFLOAT(numStates) div-by-zero when numStates=0
[R1-07] [fixed] PCA.mod/Fit — sum/LFLOAT(numSamples) div-by-zero when numSamples=0
[R1-08] [fixed] LDA.mod/Fit — sum/LFLOAT(numSamples) div-by-zero when numSamples=0
[R1-09] [fixed] PCA.mod/Fit — initial vector normalization divides by zero norm
[R1-10] [fixed] SVM.mod/ElemR,ElemI — pointer arithmetic overflow: i*TSIZE computed in CARDINAL before LONGCARD cast
[R1-11] [fixed] Classify.mod/ElemR,ElemI — same CARDINAL overflow in pointer arithmetic
[R1-12] [fixed] TempoCurve.mod/Elem — same CARDINAL overflow in pointer arithmetic
[R1-13] [fixed] DTree.mod/GetReal,SetReal,GetInt,SetInt,GetCard,GetNode — same CARDINAL overflow in pointer arithmetic
[R1-14] [fixed] GBoost.mod/GetReal,SetReal,GetInt,SetInt,GetCard,SetCard — same CARDINAL overflow in pointer arithmetic
[R1-15] [fixed] Forest.mod/GetCard,SetCard — same CARDINAL overflow in pointer arithmetic
[R1-16] [fixed] Beat.mod/ElemR — same CARDINAL overflow in pointer arithmetic
[R1-17] [fixed] AudioIO.mod/Elem — same CARDINAL overflow in pointer arithmetic
[R1-18] [fixed] Segment.mod/ElemR,ElemI — same CARDINAL overflow in pointer arithmetic
[R1-19] [fixed] Main.mod/ElemR,ChordPtr,NotePtr — same CARDINAL overflow in pointer arithmetic

## Iteration 2

[R2-01] [fixed] Wav.mod/ReadWav — LONGCARD(i*4), LONGCARD(i*3), LONGCARD(i*2) pointer arithmetic overflow for large WAV files
[R2-02] [fixed] Wav.mod/WriteWav — LONGCARD(i*2), LONGCARD(i*2+1) pointer arithmetic overflow
[R2-03] [fixed] TempoCurve.mod/ComputeTempoCurve — LONGCARD(startSamp*TSIZE(LONGREAL)) pointer arithmetic overflow
[R2-04] [fixed] TempoCurve.mod/ComputeTempoCurve — memory leak: feats not freed when ok=TRUE but numFrames<=4
[R2-05] [fixed] AudioProc.mod/Trim — CARDINAL underflow: numSamples-1 when numSamples=0

## Iteration 3

[R3-01] [fixed] Main.mod/CmdFlatness — LONGCARD(t * numBins * TSIZE(LONGREAL)) triple CARDINAL overflow
[R3-02] [fixed] Main.mod/CmdHarmonicFrame — LONGCARD(frameStart * TSIZE(LONGREAL)) CARDINAL overflow

Verified clean:
- REAL/LONGREAL narrowing: ALL source files use correct LFLOAT(fn(FLOAT(x))) pattern
- Division by zero: ALL division operations properly guarded
- ALLOCATE/DEALLOCATE symmetry: No leaks in 11 modules audited (ShortFeats early returns are before allocations)
- No remaining LONGCARD(x * y) patterns in any src/*.mod

## Formerly Deferred (now fixed)
[R1-D01] [fixed] Scaler.mod/Transform — guard stds[j] > 0 before dividing; zero output if std is 0
[R1-D02] [fixed] Filter.mod/DesignLP,DesignHP — guard fs < 1e-10 and q < 1e-10; passthrough filter on bad input
[R1-D03] [fixed] MidFeats.mod/Extract — guard count=0 in mean and stddev computation
[R1-D04] [closed] Wav.mod/FreeWav,FreeMono — DEALLOCATE with size 0 is mx convention; no fix needed
[R1-D05] [fixed] LDA.mod/Fit — near-singular rows now zeroed in inverse half, preventing corrupt downstream multiply
