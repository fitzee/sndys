MODULE BridgeEntry;
(* Dummy entry module — forces mx to link all m2audio modules.
   The real API is in sndys_bridge.c (extra-c). *)

FROM AudioIO IMPORT ReadAudio;
FROM AudioStats IMPORT Analyze;
FROM ShortFeats IMPORT Extract, ExtractFast, FreeFeatures, FeatureName;
FROM Beat IMPORT BeatExtract;
FROM Rhythm IMPORT BeatStrength;
FROM Onset IMPORT DetectOnsets;
FROM Spectro IMPORT ComputeSpectrogram, ComputeChromagram, FreeSpectro;
FROM PitchTrack IMPORT TrackPitch, FreePitch;
FROM Chords IMPORT DetectChordSequence, FreeChords;
FROM NoteTranscribe IMPORT Transcribe, FreeNotes;
FROM Harmonic IMPORT ComputeHarmonicF0;
FROM VoiceFeats IMPORT ComputeFormants, ComputeJitter, ComputeShimmer,
                       ComputeHNR;
FROM KeyDetect IMPORT DetectKey;
FROM Filter IMPORT Lowpass, Highpass, Bandpass;

BEGIN
  (* This module is never executed — it just ensures all symbols are linked *)
END BridgeEntry.
