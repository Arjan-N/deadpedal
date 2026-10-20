"""Builds the game's sound files in audio/ from downloaded source recordings.

Every source is a Freesound preview (CC0 or CC-BY, see audio/CREDITS.md).
This script records exactly how each game sound was cut from its source, so
the sounds can be rebuilt or re-tuned:

    python3 tools/audio/build_sounds.py <folder with the downloaded sources>

Sources are expected as <freesound id>.mp3 (the "-hq" preview). Requires
ffmpeg and numpy.
"""

import os
import subprocess
import sys

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "audio")


def load(path: str, stereo: bool) -> np.ndarray:
    channels = 2 if stereo else 1
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-ac", str(channels), "-ar", str(RATE), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, channels).copy()


def cut(x: np.ndarray, start: float, end: float) -> np.ndarray:
    return x[int(start * RATE):int(end * RATE)]


def fade(x: np.ndarray, fade_in: float = 0.01, fade_out: float = 0.05) -> np.ndarray:
    x = x.copy()
    n_in, n_out = int(fade_in * RATE), int(fade_out * RATE)
    if n_in:
        x[:n_in] *= np.linspace(0, 1, n_in)[:, None]
    if n_out:
        x[-n_out:] *= np.linspace(1, 0, n_out)[:, None]
    return x


def make_loop(x: np.ndarray, crossfade: float) -> np.ndarray:
    """Crossfades the end into the start so the sound repeats seamlessly."""
    n = int(crossfade * RATE)
    body = x[:-n].copy()
    t = np.linspace(0, 1, n)[:, None]
    # Equal-power crossfade avoids a volume dip at the seam.
    body[:n] = x[:n] * np.sin(t * np.pi / 2) + x[-n:] * np.cos(t * np.pi / 2)
    return body


def level(x: np.ndarray, rms_db: float | None = None, peak_db: float = -1.0) -> np.ndarray:
    """Sets the average loudness (rms_db) and/or keeps peaks under peak_db."""
    if rms_db is not None:
        rms = np.sqrt(np.mean(x ** 2)) + 1e-9
        x = x * (10 ** (rms_db / 20) / rms)
    peak = np.max(np.abs(x)) + 1e-9
    limit = 10 ** (peak_db / 20)
    if peak > limit:
        x = x * (limit / peak)
    return x


def save(x: np.ndarray, name: str) -> None:
    path = os.path.join(OUT, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", str(x.shape[1]), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", path], input=x.astype(np.float32).tobytes(), check=True)
    print(f"  {name:32s} {len(x) / RATE:5.1f}s  rms {20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9):6.1f} dBFS")


def main(src: str) -> None:
    s = lambda sid, stereo=False: load(os.path.join(src, f"{sid}.mp3"), stereo)

    # --- Zombies (mono, so they can be placed in 3D) ---
    groans = [
        cut(s(426628), 0.30, 3.60),   # mrh4hn - Zombie Moan
        cut(s(58626), 3.00, 5.80),    # kathol - A Moaning Zombie
        cut(s(58626), 6.55, 8.35),
        cut(s(58626), 8.80, 11.30),
        cut(s(173128), 5.80, 7.30),   # Taodan - Zombie
        cut(s(173128), 12.40, 15.85),
    ]
    for i, g in enumerate(groans, 1):
        save(level(fade(g, 0.02, 0.25), rms_db=-18), f"zombies/groan_{i}.ogg")
    save(level(fade(cut(s(42201), 0.0, 3.9), 0.01, 0.3), rms_db=-14), "zombies/horde_roar_1.ogg")  # SmallQuadruped - snarl
    save(level(fade(cut(s(435651), 0.05, 2.1), 0.01, 0.3), rms_db=-14), "zombies/horde_roar_2.ogg")  # Wakerone - Zombie Demon Scream
    save(level(make_loop(cut(s(165872, True), 2.0, 28.0), 2.0), rms_db=-18), "zombies/horde_loop.ogg")  # voiceofgup - ZombiesMoaning

    # --- Riding (kept quiet in-game; levelled consistently here) ---
    save(level(make_loop(cut(s(697217, True), 2.0, 32.0), 3.0), rms_db=-22), "riding/wind_loop.ogg")  # dhallcomposer - gentle wind
    save(level(make_loop(cut(s(340737, True), 5.0, 25.0), 1.5), rms_db=-22), "riding/tyre_loop.ogg")  # klankbeeld - biking on asphalt (CC-BY)
    save(level(make_loop(cut(s(426731), 8.5, 14.8), 0.8), rms_db=-24), "riding/drivetrain_loop.ogg")  # SamuelGremaud - BIKE CHAIN - 1
    save(level(make_loop(cut(s(274481), 0.05, 2.0), 0.25), rms_db=-24), "riding/freewheel_loop.ogg")  # yurkobb - bike wheel free

    # --- World ambience: crows with a distant siren drifting through ---
    crows = cut(s(214869, True), 54.5, 94.5)
    siren = fade(cut(s(469363, True), 1.3, 17.9), 2.0, 3.0) * 0.35
    start = int(14.0 * RATE)
    crows[start:start + len(siren)] += siren
    save(level(make_loop(crows, 3.0), rms_db=-24), "ambience/ambience_loop.ogg")
    save(level(fade(cut(s(22416), 0.0, 0.85), 0.005, 0.1), rms_db=-12), "ambience/heartbeat.ogg")  # Lunardrive - Four Heartbeats

    # --- Gate ---
    save(level(fade(cut(s(689528), 0.0, 0.2), 0.001, 0.03), rms_db=-14), "gate/gate_ratchet.ogg")  # InMotionAudio - ratchet
    save(level(fade(cut(s(336888), 0.0, 7.6), 0.01, 1.0), rms_db=-14), "gate/gate_open.ogg")  # Omnisis - heavy gate

    # --- Mission cues ---
    beeps = s(368779)  # gurie - Short beep countdown: three 420 Hz beeps, then a 720 Hz one
    save(level(fade(cut(beeps, 0.0, 0.5), 0.002, 0.05), rms_db=-16), "ui/countdown_beep.ogg")
    save(level(fade(cut(beeps, 3.0, 3.5), 0.002, 0.05), rms_db=-16), "ui/go.ogg")
    save(level(fade(cut(s(706753, True), 0.0, 6.0), 0.005, 1.0), rms_db=-18), "ui/success.ogg")  # xkeril - Victory (short sting)
    save(level(fade(cut(s(725225, True), 0.0, 7.4), 0.005, 1.5), rms_db=-20), "ui/failure.ogg")  # zombieallen - Plucked Horror Stinger

    # --- Criterium (race day) ---
    # A murmuring crowd along the course, applause when a lap is won, and the
    # bell for bell laps.
    save(level(make_loop(cut(s(482990, True), 20.0, 80.0), 3.0), rms_db=-24), "race/crowd_loop.ogg")  # priesjensen - People talking at cafe
    save(level(fade(cut(s(455659, True), 0.0, 7.0), 0.05, 2.5), rms_db=-18), "race/cheer.ogg")  # kyles - applause cheer ext medium crowd
    save(level(fade(cut(s(503134), 3.4, 7.0), 0.005, 0.6), rms_db=-16), "race/bell.ogg")  # se2001 - Small Bell Ringing


if __name__ == "__main__":
    main(sys.argv[1])
