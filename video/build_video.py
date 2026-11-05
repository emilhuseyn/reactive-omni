"""Builds the demo video from title cards, real terminal output, a Reactscan screenshot and text-to-speech narration.

Run: py video/build_video.py   (needs Pillow, edge-tts and ffmpeg on PATH)
"""
import asyncio
import json
import subprocess
import textwrap
from pathlib import Path

import edge_tts
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
FRAMES = HERE / "frames"
BUILD = HERE / "build"
OUT = HERE / "instant-withdrawal-queue-demo.mp4"
W, H = 1280, 720
VOICE = "en-US-AndrewNeural"
FONTS = Path("C:/Windows/Fonts")
BG, FG, MUTED, ACCENT, GREEN, AMBER = "#0f172a", "#f8fafc", "#94a3b8", "#22d3ee", "#34d399", "#fbbf24"


def font(name: str, size: int):
    return ImageFont.truetype(str(FONTS / name), size)


def card(title: str, lines: list[str], kicker: str = "", footer: str = "") -> Image.Image:
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    y = 140
    if kicker:
        d.text((100, y), kicker.upper(), font=font("segoeuib.ttf", 26), fill=ACCENT)
        y += 55
    d.text((100, y), title, font=font("segoeuib.ttf", 60), fill=FG)
    y += 105
    for line in lines:
        for part in textwrap.wrap(line, 62):
            d.text((100, y), part, font=font("segoeui.ttf", 32), fill=FG if not line.startswith("~") else MUTED)
            y += 46
        y += 12
    if footer:
        d.text((100, H - 80), footer, font=font("segoeui.ttf", 24), fill=MUTED)
    d.rectangle([0, 0, 14, H], fill=ACCENT)
    return img


def terminal(title: str, rows: list[tuple[str, str]], footer: str, size: int = 21, step: int = 36) -> Image.Image:
    img = Image.new("RGB", (W, H), "#0b0f14")
    d = ImageDraw.Draw(img)
    mono = font("consola.ttf", size)
    d.rectangle([0, 0, W, 44], fill="#1f2937")
    d.text((24, 10), title, font=font("segoeui.ttf", 20), fill=MUTED)
    y = 76
    for text, colour in rows:
        d.text((36, y), text, font=mono, fill=colour)
        y += step
    d.text((36, H - 56), footer, font=font("segoeui.ttf", 20), fill=MUTED)
    return img


def flow() -> Image.Image:
    img = card("One loop, no keeper", [], "How it works")
    d = ImageDraw.Draw(img)
    boxes = [
        (60, 300, "Base Sepolia", "Vault", "addLiquidity()", "emits LiquidityAdded"),
        (470, 300, "Reactive Lasna", "QueueReactive", "react(log)", "queued > 0: callback"),
        (880, 300, "Base Sepolia", "Vault", "settle()", "pays the queue, FIFO"),
    ]
    for x, y, chain, name, call, note in boxes:
        d.rounded_rectangle([x, y, x + 340, y + 220], 18, outline=ACCENT, width=3, fill="#111c33")
        d.text((x + 24, y + 18), chain.upper(), font=font("segoeuib.ttf", 20), fill=ACCENT)
        d.text((x + 24, y + 54), name, font=font("segoeuib.ttf", 34), fill=FG)
        d.text((x + 24, y + 112), call, font=font("consola.ttf", 26), fill=GREEN)
        d.text((x + 24, y + 158), note, font=font("segoeui.ttf", 24), fill=MUTED)
    for x in (410, 820):
        d.line([x, 410, x + 52, 410], fill=FG, width=4)
        d.polygon([(x + 52, 400), (x + 64, 410), (x + 52, 420)], fill=FG)
    d.text((100, 580), "Only the callback proxy may call settle(), and only for our own reactive contract.", font=font("segoeui.ttf", 26), fill=MUTED)
    return img


def frame(name: str, caption: str) -> Image.Image:
    src = Image.open(FRAMES / name).convert("RGB")
    img = Image.new("RGB", (W, H), "#000000")
    scale = (H - 64) / src.height
    shot = src.resize((int(src.width * scale), H - 64), Image.LANCZOS)
    img.paste(shot, ((W - shot.width) // 2, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, H - 64, W, H], fill=BG)
    d.text((32, H - 50), caption, font=font("segoeuib.ttf", 28), fill=FG)
    return img


E2E = terminal(
    "script/e2e.sh base   (run 5 of 5, 6 Nov 2026)",
    [
        ("$ script/e2e.sh base", MUTED),
        ("  mint 1,000 mUSD, deposit, lend out all but 100 mUSD", MUTED),
        ("  requestWithdrawal(300 mUSD)", MUTED),
        ("queued: 1", AMBER),
        ("  addLiquidity(300 mUSD)", MUTED),
        ("liquidity added in block 54944928 at 1793910854", FG),
        ("settled in block 54944934 at 1793910855", GREEN),
        ("  by 0xF7E866D726658F6C3F14B8EE537fe268a4D91DDb  (Reactive Network relayer, not us)", MUTED),
        ("liquidity tx 0x330ee609ab6184df8e52c38994773a48a65523ed2096257453bcedd488312ffb", FG),
        ("settle tx    0xfd00804317e86a18fae521e7844ad7658871dd8cb5ac5bcb8a4baa17b59c760e", FG),
        ("liquidity -> payout: 1 s, 6 blocks", GREEN),
    ],
    "Real output; the grey lines name the script's steps. Vault 0x6A9B129a...501781f1 on Base Sepolia, QueueReactive 0xA0327B3C...BDeF2b684B on Lasna.",
    size=20, step=40,
)

TABLE = terminal(
    "latency.csv   (Base Sepolia, 6 Nov 2026)",
    [
        ("run   blocks   seconds   settle tx", ACCENT),
        ("1     7        2         0x59f53f95...ddf190a2", FG),
        ("2     10       2         0x814d51da...47ee575b", FG),
        ("3     11       2         0x4d5a6b94...af2b24e9", FG),
        ("4     10       2         0x1ac19907...cbf44d4c", FG),
        ("5     6        1         0xfd008043...b59c760e", FG),
        ("", FG),
        ("5 of 5 settled. 1-2 s, 6-11 blocks, from addLiquidity to payout.", GREEN),
        ("Each callback cost the reactive contract about 0.02 lREACT.", MUTED),
    ],
    "Seconds are block timestamp differences (1 s resolution). Every hash is in the README.",
    size=24, step=46,
)

SCENES = [
    ("s1", card("Instant Withdrawal Queue", ["A vault whose withdrawal queue is paid the moment liquidity comes back."], "Reactive Omni Buildathon, Every Second Counts", "Base Sepolia + Reactive Network (Lasna)"),
     "This is Instant Withdrawal Queue: a vault whose withdrawal queue is paid the moment liquidity comes back."),
    ("s2", card("The problem", [
        "Vaults lend out most of their deposits.",
        "Big withdrawals wait in a queue.",
        "Someone has to notice that liquidity is back: a keeper bot, a cron job, or the user clicking again.",
        "~Keepers cost money, go down, and skip small queues.",
    ], "Why it matters"),
     "Lending and yield vaults lend out most of their deposits, so a large withdrawal has to wait in a queue. Then someone has to notice that liquidity came back and push the queue forward: a keeper bot, a cron job, or the user clicking again. Keepers cost money, go down, and skip queues too small to be worth their gas. Meanwhile the money is already sitting in the vault."),
    ("s3", flow(),
     "Here, nobody has to watch. When liquidity returns, the vault on Base Sepolia emits LiquidityAdded. A reactive contract on Reactive Network is subscribed to that event. If anything is queued, it requests a callback, and the vault's settle function pays the queue in order, oldest request first. Only the callback proxy can call settle, and only on behalf of our own reactive contract."),
    ("s4", E2E,
     "This is a real run on Base Sepolia. A three hundred dollar withdrawal is queued because the vault holds only one hundred. Then three hundred comes back. One second and six blocks later, the queue is paid, by a transaction that Reactive Network sent, not us."),
    ("s5", frame("reactscan_callbacks.jpg", "Reactscan: every settle on Base is a confirmed callback of QueueReactive"),
     "On Reactscan, every one of those settle transactions shows up as a confirmed callback of our reactive contract, with the Lasna transaction that requested it."),
    ("s6", TABLE,
     "We ran the full loop five times. Every run settled, within one to two seconds, six to eleven blocks, from the liquidity transaction to the payout. Each callback cost about two hundredths of an lREACT."),
    ("s7", card("Built to be safe", [
        "settle() accepts only the callback proxy and our own reactive contract.",
        "Strict first in, first out: a small request never jumps the queue.",
        "At most 25 payouts per callback, so gas stays bounded.",
        "An idle vault costs nothing: no queue, no callback.",
    ], "Details"),
     "The queue is strictly first in, first out. Each callback pays at most twenty five requests, so gas stays bounded, and when nothing is queued, no callback is requested at all. Nine Foundry tests cover these rules."),
    ("s8", card("Instant Withdrawal Queue", ["Liquidity back. Queue paid. About one second.", "No keeper."], "Reactive Network callbacks on Base Sepolia", "github.com/emilhuseyn/reactive-omni"),
     "Instant Withdrawal Queue. Liquidity comes back, the queue is paid, in about a second, with no keeper."),
]


async def speak(text: str, path: Path):
    for attempt in range(5):
        try:
            await edge_tts.Communicate(text, VOICE).save(str(path))
            return
        except edge_tts.exceptions.NoAudioReceived:
            await asyncio.sleep(3 * (attempt + 1))
    raise RuntimeError(f"no audio for {path.name}")


def duration(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path)], capture_output=True, text=True, check=True)
    return float(json.loads(out.stdout)["format"]["duration"])


def main():
    BUILD.mkdir(exist_ok=True)
    parts = []
    for key, image, text in SCENES:
        png, mp3, mp4 = BUILD / f"{key}.png", BUILD / f"{key}.mp3", BUILD / f"{key}.mp4"
        image.save(png)
        asyncio.run(speak(text, mp3))
        length = duration(mp3) + 0.8
        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-i", str(png), "-i", str(mp3),
            "-af", "apad", "-t", f"{length:.2f}", "-c:v", "libx264", "-tune", "stillimage", "-pix_fmt", "yuv420p", "-r", "30",
            "-c:a", "aac", "-b:a", "160k", "-ar", "48000", str(mp4),
        ], check=True)
        parts.append(mp4)
        print(f"{key}: {length:.1f}s")
    listing = BUILD / "parts.txt"
    listing.write_text("".join(f"file '{p.as_posix()}'\n" for p in parts), encoding="utf-8")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", str(OUT)], check=True)
    print(f"{OUT.name}: {duration(OUT):.1f}s")


if __name__ == "__main__":
    main()
