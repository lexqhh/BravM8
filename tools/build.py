"""Construit l'add-on FlyMedia à partir du dossier medias/.

- images (png, jpg, webp, bmp)       -> TGA, 512 px max
- GIF animés et vidéos (mp4, webm…)  -> planche d'images TGA + son .ogg
- un fichier audio du même nom qu'une image (ex. chat.jpg + chat.mp3)
  est joué avec cette image

Sortie dans dist/ : FlyMedia.zip (l'add-on complet), version.txt,
update.ps1 et FlyMedia.bat (le fichier à donner aux potes).
Nécessite Python 3.9+, Pillow et ffmpeg/ffprobe dans le PATH.

Usage : python tools/build.py --version 12
"""

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from PIL import Image, ImageSequence

# --- Réglages ---------------------------------------------------------------
IMAGE_MAX = 512        # côté le plus long d'une image, en pixels
FRAME_MAX = 200        # côté le plus long d'une image de clip
CLIP_FPS = 10          # images par seconde des clips
CLIP_MAX_SECONDS = 60  # sécurité : au-delà, le clip est coupé
ATLAS_MAX = 2048       # taille max d'une planche d'images
SOUND_MAX_SECONDS = 30
# ---------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parent.parent
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}
VIDEO_EXT = {".gif", ".mp4", ".webm", ".mov", ".mkv", ".avi", ".m4v"}
AUDIO_EXT = {".mp3", ".ogg", ".wav", ".m4a", ".flac", ".opus"}


def pow2(n: int) -> int:
    return 1 << max(0, math.ceil(math.log2(max(1, n))))


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def fit(w: int, h: int, limit: int) -> tuple[int, int]:
    scale = min(1.0, limit / max(w, h))
    return max(1, round(w * scale)), max(1, round(h * scale))


def save_padded(img: Image.Image, dest: Path) -> tuple[int, int]:
    """Colle l'image en haut à gauche d'une toile en puissance de 2 et l'enregistre en TGA."""
    has_alpha = img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info)
    mode = "RGBA" if has_alpha else "RGB"
    img = img.convert(mode)
    tw, th = pow2(img.width), pow2(img.height)
    canvas = Image.new(mode, (tw, th))
    canvas.paste(img, (0, 0))
    canvas.save(dest, format="TGA")
    return tw, th


def convert_audio(src: Path, dest: Path, max_seconds: float) -> bool:
    r = run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-t", str(max_seconds),
             "-vn", "-ac", "2", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "3", str(dest)])
    return r.returncode == 0 and dest.exists() and dest.stat().st_size > 0


def has_audio(src: Path) -> bool:
    r = run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries",
             "stream=index", "-of", "json", str(src)])
    try:
        return bool(json.loads(r.stdout or "{}").get("streams"))
    except json.JSONDecodeError:
        return False


def build_image(src: Path, name: str, out: Path) -> dict:
    with Image.open(src) as im:
        im = next(ImageSequence.Iterator(im)).copy()
        im = im.resize(fit(im.width, im.height, IMAGE_MAX), Image.LANCZOS)
        tw, th = save_padded(im, out / f"{name}.tga")
        return {"type": "image", "file": name, "w": im.width, "h": im.height, "tw": tw, "th": th}


def build_clip(src: Path, name: str, out: Path, tmp: Path) -> dict:
    frames_dir = tmp / name
    frames_dir.mkdir()
    r = run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-t", str(CLIP_MAX_SECONDS),
             "-vf", f"fps={CLIP_FPS},scale={FRAME_MAX}:{FRAME_MAX}:force_original_aspect_ratio=decrease",
             str(frames_dir / "%04d.png")])
    files = sorted(frames_dir.glob("*.png"))
    if r.returncode != 0 or not files:
        raise RuntimeError(r.stderr.strip() or "aucune image extraite")

    with Image.open(files[0]) as first:
        fw, fh = first.size
    cols_max = ATLAS_MAX // fw
    rows_max = ATLAS_MAX // fh
    per_page = cols_max * rows_max
    count = len(files)

    # un clip long est réparti sur plusieurs planches, lues à la suite par l'add-on
    pages = []
    for p, start in enumerate(range(0, count, per_page), 1):
        chunk = files[start:start + per_page]
        n = len(chunk)
        # nombre de colonnes qui donne la plus petite texture une fois arrondie en puissance de 2
        cols = min(range(1, min(n, cols_max) + 1),
                   key=lambda c: (math.ceil(n / c) <= rows_max
                                  and pow2(c * fw) * pow2(math.ceil(n / c) * fh) or float("inf"),
                                  abs(c * fw - math.ceil(n / c) * fh)))
        rows = math.ceil(n / cols)
        atlas = Image.new("RGB", (cols * fw, rows * fh))
        for i, f in enumerate(chunk):
            with Image.open(f) as fr:
                atlas.paste(fr.convert("RGB"), ((i % cols) * fw, (i // cols) * fh))
        file = name if count <= per_page else f"{name}_{p}"
        tw, th = save_padded(atlas, out / f"{file}.tga")
        pages.append({"file": file, "tw": tw, "th": th, "cols": cols})

    entry = {"type": "video", "file": pages[0]["file"], "w": fw, "h": fh,
             "tw": pages[0]["tw"], "th": pages[0]["th"], "frames": count, "fps": CLIP_FPS,
             "perPage": per_page, "duration": round(count / CLIP_FPS, 2), "pages": pages}
    if src.suffix.lower() != ".gif" and has_audio(src):
        if convert_audio(src, out / f"{name}.ogg", count / CLIP_FPS):
            entry["sound"] = f"{name}.ogg"
    return entry


def lua_value(v) -> str:
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        return "{ " + ", ".join(lua_value(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {lua_value(x)}" for k, x in v.items()) + " }"
    return str(v)


def audio_duration(path: Path) -> float:
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)])
    try:
        return float(r.stdout.strip())
    except ValueError:
        return 5.0


def write_media_lua(entries: list[dict], eggs: list[dict], dest: Path) -> None:
    lines = ["-- Fichier généré automatiquement par tools/build.py : ne pas modifier à la main."]
    for var, items in (("FlyMedia_List", entries), ("FlyMedia_Easter", eggs)):
        lines.append(f"{var} = {{")
        for e in items:
            fields = ", ".join(f"{k} = {lua_value(v)}" for k, v in e.items() if k != "source")
            lines.append(f"    {{ {fields} }}, -- {e['source']}")
        lines.append("}")
    dest.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--repo", default="OWNER/REPO", help="dépôt GitHub, ex. pseudo/FlyMedia")
    parser.add_argument("--medias", default=str(ROOT / "medias"))
    parser.add_argument("--out", default=str(ROOT / "dist"))
    args = parser.parse_args()

    medias = Path(args.medias)
    dist = Path(args.out)
    if dist.exists():
        shutil.rmtree(dist)
    addon = dist / "FlyMedia"
    shutil.copytree(ROOT / "addon" / "FlyMedia", addon)
    out = addon / "media"
    out.mkdir()

    all_files = sorted(p for p in medias.rglob("*") if p.is_file()) if medias.exists() else []
    easter_dir = medias / "easter"
    easter = [p for p in all_files if easter_dir in p.parents and p.suffix.lower() in AUDIO_EXT]
    sources = [p for p in all_files if easter_dir not in p.parents]
    audio_by_stem = {p.stem.lower(): p for p in sources if p.suffix.lower() in AUDIO_EXT}
    visuals = [p for p in sources if p.suffix.lower() in IMAGE_EXT | VIDEO_EXT]

    entries, errors = [], []
    with tempfile.TemporaryDirectory() as tmp:
        for i, src in enumerate(visuals, 1):
            name = f"m{i:03d}"
            rel = src.relative_to(medias).as_posix()
            try:
                if src.suffix.lower() in IMAGE_EXT:
                    e = build_image(src, name, out)
                else:
                    e = build_clip(src, name, out, Path(tmp))
                companion = audio_by_stem.get(src.stem.lower())
                if companion and convert_audio(companion, out / f"{name}.ogg", SOUND_MAX_SECONDS):
                    e["sound"] = f"{name}.ogg"
                e["source"] = rel
                entries.append(e)
                print(f"ok    {rel}  ->  {e['type']} {e['w']}x{e['h']}"
                      + (f", {e['frames']} images" if e["type"] == "video" else "")
                      + (", avec son" if "sound" in e else ""))
            except Exception as exc:  # un fichier cassé ne doit pas bloquer les autres
                errors.append(rel)
                print(f"ERREUR {rel} : {exc}", file=sys.stderr)

    # sons rares (medias/easter/) : joués seuls, de temps en temps, pendant un vol
    eggs = []
    for i, src in enumerate(easter, 1):
        rel = src.relative_to(medias).as_posix()
        name = f"e{i:03d}.ogg"
        if convert_audio(src, out / name, SOUND_MAX_SECONDS):
            eggs.append({"sound": name, "duration": round(audio_duration(out / name), 2), "source": rel})
            print(f"ok    {rel}  ->  easter egg, {eggs[-1]['duration']} s")
        else:
            errors.append(rel)
            print(f"ERREUR {rel} : conversion audio impossible", file=sys.stderr)

    write_media_lua(entries, eggs, addon / "Media.lua")
    toc = addon / "FlyMedia.toc"
    toc.write_text(toc.read_text(encoding="utf-8").replace("## Version: dev", f"## Version: {args.version}"),
                   encoding="utf-8")
    (addon / "version.txt").write_text(args.version, encoding="utf-8")
    (dist / "version.txt").write_text(args.version, encoding="utf-8")

    # programme de mise à jour : BOM UTF-8 pour Windows PowerShell 5.1, fins de ligne Windows pour le .bat
    tools = ROOT / "tools"
    ps1 = (tools / "update.ps1").read_text(encoding="utf-8").replace("\r\n", "\n")
    (dist / "update.ps1").write_bytes(b"\xef\xbb\xbf" + ps1.replace("\n", "\r\n").encode("utf-8"))
    bat = (tools / "FlyMedia.bat").read_text(encoding="ascii").replace("\r\n", "\n")
    (dist / "FlyMedia.bat").write_bytes(bat.replace("__REPO__", args.repo).replace("\n", "\r\n").encode("ascii"))

    zip_path = dist / "FlyMedia.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in sorted(addon.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(dist).as_posix())

    size = sum(f.stat().st_size for f in addon.rglob("*") if f.is_file())
    print(f"\n{len(entries)} média(s), {len(errors)} erreur(s). "
          f"Add-on : {size / 1e6:.1f} Mo, zip : {zip_path.stat().st_size / 1e6:.1f} Mo.")
    return 1 if errors and not entries else 0


if __name__ == "__main__":
    sys.exit(main())
