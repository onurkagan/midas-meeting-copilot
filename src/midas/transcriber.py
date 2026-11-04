"""Local Whisper transcription on Apple Silicon (mlx-whisper)."""

import logging
import re
from pathlib import Path

import numpy as np

log = logging.getLogger("midas.whisper")

# Whisper invents these from YouTube subtitles when it hears noise or music. The first
# ones match Turkish credits ("Subtitles: M.K.", "Thanks for watching", "Don't forget to
# subscribe"), which it produces for Turkish audio.
HALLUCINATION_PATTERNS = [
    r"altyaz[ıi]\s*m\.?\s*k\.?",
    r"altyaz[ıi]lar?\s*:?",
    r"izledi[ğg]iniz i[çc]in te[şs]ekk[üu]r\w*",
    r"abone olma\w*\s*unutma\w*",
    r"thanks? (you )?for watching",
    r"subtitles? by .*",
    r"please subscribe",
    r"amara\.org",
]
_HALLUCINATION = re.compile("|".join(HALLUCINATION_PATTERNS), re.IGNORECASE)


def clean_text(text: str) -> str:
    text = _HALLUCINATION.sub("", text)
    text = re.sub(r"[♪♫]+", "", text)
    text = re.sub(r"\s+", " ", text).strip(" -–—")
    return text if re.search(r"\w{2,}", text) else ""


class Transcriber:
    """Transcribes one utterance (at most 30 s, a single Whisper window) at a time.

    The audio is encoded once and the same features serve both language detection
    and decoding, which halves the latency compared to mlx_whisper.transcribe.
    """

    def __init__(self, model: str, languages: list[str], vocabulary: str = ""):
        self.model_repo = model
        self.languages = [lang.strip().lower() for lang in languages if lang.strip()]
        self.vocabulary = vocabulary.strip()
        self.language = self.languages[0] if self.languages else None
        self._model = None

    def load(self):
        import mlx.core as mx
        from huggingface_hub import snapshot_download
        from mlx_whisper.load_models import load_model

        log.info("loading model: %s (downloaded on first use)", self.model_repo)
        path = Path(self.model_repo).expanduser()
        if not path.exists():
            # A downloaded model loads without asking Hugging Face for updates, so Midas
            # makes no network requests of its own once it's set up.
            try:
                path = snapshot_download(self.model_repo, local_files_only=True)
            except Exception:
                path = snapshot_download(self.model_repo)
        self._model = load_model(str(path), dtype=mx.float16)
        self.transcribe(np.zeros(16000, dtype=np.float32), final=False)
        log.info("model ready")

    def transcribe(self, audio: np.ndarray, final: bool, context: str = "") -> str:
        import mlx.core as mx
        from mlx_whisper.audio import N_FRAMES, N_SAMPLES, log_mel_spectrogram, pad_or_trim
        from mlx_whisper.decoding import DecodingOptions, decode, detect_language

        audio = audio.astype(np.float32)
        peak = float(np.max(np.abs(audio))) if audio.size else 0.0
        if peak > 1e-4:
            audio = audio * min(0.9 / peak, 20.0)
        mel = log_mel_spectrogram(audio, n_mels=self._model.dims.n_mels, padding=N_SAMPLES)
        mel = pad_or_trim(mel, N_FRAMES, axis=-2).astype(mx.float16)
        features = self._model.encoder(mel[None])[0]

        # Partials reuse the last language to stay fast; finals re-detect it.
        if final and len(self.languages) > 1:
            _, probs = detect_language(self._model, features)
            self.language = max(self.languages, key=lambda lang: probs.get(lang, 0.0))

        prompt = " ".join(part for part in (self.vocabulary, context[-200:]) if part).strip()
        for temperature in (0.0, 0.2, 0.4) if final else (0.0,):
            options = DecodingOptions(
                language=self.language,
                temperature=temperature,
                prompt=prompt or None,
                without_timestamps=True,
            )
            result = decode(self._model, features, options)
            if result.compression_ratio <= 2.4 and result.avg_logprob >= -1.0:
                break
        text = clean_text(result.text)
        # large-v3-turbo's no_speech_prob is always ~0, so confidence does the gating:
        # noise decodes below -1.0, and a lone "you"/"so" from silence near -0.5.
        if result.avg_logprob < -1.0 or (result.no_speech_prob > 0.6 and result.avg_logprob < -0.7):
            return ""
        if len(text.split()) <= 1 and result.avg_logprob < -0.4:
            return ""
        return text
