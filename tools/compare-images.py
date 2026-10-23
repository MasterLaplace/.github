#!/usr/bin/env python3
"""Draws the same images from two commits and shows where their pixels changed.

usage: tools/compare-images.py --draw <command> (--before <commit> | --before-images <dir>)
                               [--after <commit> | --after-images <dir>] [--out <dir>]
                               [--title <text>] [--threshold <t>] [--images-url <url>]
       tools/compare-images.py --draw <command> --draw-into <dir> [--after <commit>]
       tools/compare-images.py --compare <before-dir> <after-dir> [--out <dir>] [...]
       tools/compare-images.py --self-test

--draw runs <command> through the shell at the root of each side's tree, with IMAGES_DIR set to
the directory it must write its images into (PNG or binary PPM, one file per image, named after
it). The command must draw a commit the same way whichever side it stands for: a commit's images
are kept and read back as either. The before side is <commit>, checked out in a
temporary worktree; the after side is --after, or the working tree when there is none. Both sides
are drawn on this machine, so a difference is the code's. --before-images takes the before side
from a directory instead, a reference kept from an earlier drawing, so it is not drawn again;
--after-images does the same for the after side. --draw-into draws the after side into a directory and stops, to keep it as a reference.
--compare takes two directories of images already drawn.

An image differs visibly when the perceived distance between two of its pixels, in the YIQ space,
passes the threshold (0.1 by default); it differs at all when one pixel is not the same. Into
--out (build/compare-images by default) go:
  before/, after/       the images of each side;
  images/               for each image not the same on both sides: <name>-before.png,
                        <name>-after.png and <name>-diff.png, the changed pixels in red over the
                        before image faded to grey (the visible changes, or every change when none
                        is visible);
  index.html            a page that shows each such image under a curtain to drag;
  result.md             the table for a pull request, with the images inline when --images-url
                        gives the address images/ is published at;
  result.json           the same, for a program.
The table is also printed.

The colour distance, the 35215 * t^2 threshold and the faded grey are pixelmatch's
(https://github.com/mapbox/pixelmatch, 5.3.0, index.js), which takes the distance from Kotsarenko
and Ramos, "Measuring perceived color difference using YIQ NTSC transmission color space in mobile
applications" (2010). Anti-aliased pixels are not told apart.

--self-test checks the comparison, the PNG reader and writer, and the outputs on images it writes.

Exit status: 0 when every image is the same on both sides, 1 when one differs or only one side
has it, 2 on a usage error or when a side could not be drawn.
"""

import argparse
import base64
import contextlib
import html
import io
import json
import os
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

MAXIMUM_DELTA = 35215.0
FADING_ALPHA = 0.1
CHANGED = b"\xff\x00\x00"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class Unusable(Exception):
    """An input this tool cannot read, or a side it could not draw."""


def read_ppm(data):
    fields = []
    position = 0
    while len(fields) < 4:
        while position < len(data) and data[position : position + 1].isspace():
            position += 1
        start = position
        while position < len(data) and not data[position : position + 1].isspace():
            position += 1
        fields.append(data[start:position])
    if fields[0] != b"P6" or fields[3] != b"255":
        raise Unusable("not an 8-bit binary PPM")
    width, height = int(fields[1]), int(fields[2])
    pixels = data[position + 1 : position + 1 + width * height * 3]
    if len(pixels) != width * height * 3:
        raise Unusable("a PPM shorter than its header says")
    return width, height, pixels


def paeth(left, up, up_left):
    estimate = left + up - up_left
    to_left, to_up, to_up_left = abs(estimate - left), abs(estimate - up), abs(estimate - up_left)
    if to_left <= to_up and to_left <= to_up_left:
        return left
    return up if to_up <= to_up_left else up_left


def read_png(data):
    position = len(PNG_SIGNATURE)
    header = None
    compressed = bytearray()
    while position < len(data):
        length, kind = struct.unpack(">I4s", data[position : position + 8])
        payload = data[position + 8 : position + 8 + length]
        position += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            compressed += payload
        elif kind == b"IEND":
            break
    if header is None:
        raise Unusable("a PNG without IHDR")
    width, height, depth, colour, _, _, interlace = header
    channels = {2: 3, 6: 4}.get(colour)
    if depth != 8 or channels is None or interlace != 0:
        raise Unusable("a PNG that is not 8-bit RGB or RGBA without interlacing")
    raw = zlib.decompress(bytes(compressed))
    stride = width * channels
    previous = bytearray(stride)
    rgb = bytearray(width * height * 3)
    for y in range(height):
        kind = raw[y * (stride + 1)]
        row = bytearray(raw[y * (stride + 1) + 1 : (y + 1) * (stride + 1)])
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            up = previous[x]
            up_left = previous[x - channels] if x >= channels else 0
            if kind == 1:
                row[x] = (row[x] + left) & 0xFF
            elif kind == 2:
                row[x] = (row[x] + up) & 0xFF
            elif kind == 3:
                row[x] = (row[x] + (left + up) // 2) & 0xFF
            elif kind == 4:
                row[x] = (row[x] + paeth(left, up, up_left)) & 0xFF
        for x in range(width):
            rgb[(y * width + x) * 3 : (y * width + x) * 3 + 3] = row[x * channels : x * channels + 3]
        previous = row
    return width, height, bytes(rgb)


def read_image(path):
    data = path.read_bytes()
    try:
        if data.startswith(PNG_SIGNATURE):
            return read_png(data)
        return read_ppm(data)
    except (Unusable, struct.error, zlib.error, ValueError, IndexError) as error:
        raise Unusable(f"{path}: {error}") from None


def png(width, height, rgb):
    rows = b"".join(b"\x00" + rgb[y * width * 3 : (y + 1) * width * 3] for y in range(height))

    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return PNG_SIGNATURE + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


def luma(r, g, b):
    return r * 0.29889531 + g * 0.58662247 + b * 0.11448223


def colour_delta(first, second):
    r1, g1, b1 = first
    r2, g2, b2 = second
    y = luma(r1, g1, b1) - luma(r2, g2, b2)
    i = (r1 - r2) * 0.59597799 - (g1 - g2) * 0.27417610 - (b1 - b2) * 0.32180189
    q = (r1 - r2) * 0.21147017 - (g1 - g2) * 0.52261711 + (b1 - b2) * 0.31114694
    return 0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q


def compare_pixels(before, after, threshold):
    maximum = MAXIMUM_DELTA * threshold * threshold
    visible = bytearray(len(before))
    every = bytearray(len(before))
    visible_count = 0
    any_count = 0
    for offset in range(0, len(before), 3):
        first = before[offset : offset + 3]
        second = after[offset : offset + 3]
        grey = int(255 + (luma(*first) - 255) * FADING_ALPHA)
        faded = bytes((grey, grey, grey))
        visible[offset : offset + 3] = faded
        every[offset : offset + 3] = faded
        if first == second:
            continue
        any_count += 1
        every[offset : offset + 3] = CHANGED
        if colour_delta(tuple(first), tuple(second)) > maximum:
            visible_count += 1
            visible[offset : offset + 3] = CHANGED
    return visible_count, any_count, bytes(visible if visible_count else every)


def percent(count, total):
    return f"{100.0 * count / total:.2f} %"


def images_in(directory):
    found = {}
    if directory.is_dir():
        for path in sorted(directory.iterdir()):
            if path.suffix.lower() in (".png", ".ppm") and path.is_file():
                found.setdefault(path.stem, path)
    return found


def compare_directories(before_directory, after_directory, output, threshold):
    before_images = images_in(before_directory)
    after_images = images_in(after_directory)
    names = sorted(set(before_images) | set(after_images))
    images = output / "images"
    shutil.rmtree(images, ignore_errors=True)
    images.mkdir(parents=True, exist_ok=True)

    results = []
    for name in names:
        entry = {"name": name, "result": "same", "visible": None, "any": None, "files": {}}
        if name not in before_images or name not in after_images:
            side = "before" if name not in before_images else "after"
            width, height, pixels = read_image((after_images if side == "before" else before_images)[name])
            present = "after" if side == "before" else "before"
            (images / f"{name}-{present}.png").write_bytes(png(width, height, pixels))
            entry.update(result=f"missing {side}", files={present: f"{name}-{present}.png"})
            results.append(entry)
            continue
        width, height, before = read_image(before_images[name])
        other_width, other_height, after = read_image(after_images[name])
        if (width, height) != (other_width, other_height):
            entry["result"] = f"{width}x{height} before, {other_width}x{other_height} after"
            results.append(entry)
            continue
        visible_count, any_count, diff = compare_pixels(before, after, threshold)
        total = width * height
        entry.update(visible=visible_count / total, any=any_count / total)
        if any_count:
            entry["result"] = "changed"
            for side, pixels in (("before", before), ("after", after), ("diff", diff)):
                (images / f"{name}-{side}.png").write_bytes(png(width, height, pixels))
                entry["files"][side] = f"{name}-{side}.png"
        results.append(entry)
    return results


def table(results, images_url):
    def cell(entry, side):
        file = entry["files"].get(side)
        if file is None:
            return ""
        if not images_url:
            return file
        return f'<img src="{images_url.rstrip("/")}/{file}" width="200" alt="{html.escape(entry["name"])} {side}">'

    def share(value):
        return "" if value is None else f"{100.0 * value:.2f} %"

    lines = ["| Image | Result | Before | After | Where | Visible | Any |", "|---|---|---|---|---|---:|---:|"]
    for entry in results:
        if entry["result"] == "same":
            continue
        lines.append(
            f"| {entry['name']} | {entry['result']} | {cell(entry, 'before')} | {cell(entry, 'after')} "
            f"| {cell(entry, 'diff')} | {share(entry['visible'])} | {share(entry['any'])} |"
        )
    same = [entry["name"] for entry in results if entry["result"] == "same"]
    if len(lines) == 2:
        lines = []
    if same:
        lines.append("")
        lines.append(f"Same on both sides: {', '.join(same)}.")
    return "\n".join(lines)


PAGE_HEAD = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
:root {{ --ground: #0b0d10; --panel: #12161b; --rule: #263039; --ink: #e6e3dc; --muted: #8d98a3; --accent: #ffaa22; color-scheme: dark; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--ground); color: var(--ink); font: 15px/1.5 system-ui, sans-serif; }}
main {{ max-width: 1000px; margin: 0 auto; padding: 32px 16px 64px; display: flex; flex-direction: column; gap: 32px; }}
h1, h2 {{ font-family: ui-monospace, monospace; font-weight: 500; margin: 0; }}
h1 {{ font-size: 26px; }}
h2 {{ font-size: 17px; }}
.table-wrap {{ overflow-x: auto; }}
table {{ border-collapse: collapse; font-family: ui-monospace, monospace; font-size: 14px; width: 100%; }}
th, td {{ text-align: left; padding: 6px 10px; border-bottom: 1px solid var(--rule); }}
td.number, th.number {{ text-align: right; }}
section {{ display: flex; flex-direction: column; gap: 10px; border-top: 1px solid var(--rule); padding-top: 20px; }}
.modes {{ display: flex; flex-wrap: wrap; }}
.modes button {{ font: 13px ui-monospace, monospace; color: var(--muted); background: none; border: 1px solid var(--rule); padding: 6px 12px; margin-right: -1px; cursor: pointer; }}
.modes button[aria-pressed="true"] {{ color: var(--ground); background: var(--accent); border-color: var(--accent); }}
.curtain {{ position: relative; width: 100%; border: 1px solid var(--rule); background: var(--panel); overflow: hidden; user-select: none; touch-action: none; }}
.curtain img {{ display: block; width: 100%; image-rendering: pixelated; }}
.curtain .left {{ position: absolute; inset: 0; height: 100%; clip-path: inset(0 calc(100% - var(--cut, 50%)) 0 0); }}
.curtain .seam {{ position: absolute; top: 0; bottom: 0; left: var(--cut, 50%); width: 2px; margin-left: -1px; background: var(--accent); pointer-events: none; }}
.curtain .tag {{ position: absolute; bottom: 8px; font: 12px ui-monospace, monospace; padding: 2px 6px; background: rgba(11, 13, 16, 0.85); border: 1px solid var(--rule); pointer-events: none; }}
.curtain .left-tag {{ left: 8px; }}
.curtain .right-tag {{ right: 8px; color: var(--accent); }}
.note {{ color: var(--muted); font-size: 14px; }}
</style>
</head>
<body>
<main>
"""

PAGE_SCRIPT = """<script>
document.querySelectorAll("section[data-image]").forEach(function (section) {
  var curtain = section.querySelector(".curtain");
  var left = section.querySelector(".left");
  if (left === null) return;
  var tag = section.querySelector(".left-tag");
  var dragging = false;
  function cut(event) {
    var box = curtain.getBoundingClientRect();
    var share = Math.min(Math.max((event.clientX - box.left) / box.width, 0), 1);
    curtain.style.setProperty("--cut", Math.round(share * 100) + "%");
  }
  curtain.addEventListener("pointerdown", function (event) { dragging = true; curtain.setPointerCapture(event.pointerId); cut(event); });
  curtain.addEventListener("pointermove", function (event) { if (dragging) cut(event); });
  curtain.addEventListener("pointerup", function () { dragging = false; });
  section.querySelectorAll(".modes button").forEach(function (button) {
    button.addEventListener("click", function () {
      left.src = section.dataset[button.dataset.mode];
      tag.textContent = button.textContent;
      section.querySelectorAll(".modes button").forEach(function (other) { other.setAttribute("aria-pressed", other === button ? "true" : "false"); });
    });
  });
});
</script>
</main>
</body>
</html>
"""


def page(results, images, title, threshold):
    def uri(file):
        return "data:image/png;base64," + base64.b64encode((images / file).read_bytes()).decode()

    body = [PAGE_HEAD.format(title=html.escape(title)), f"<h1>{html.escape(title)}</h1>",
            f'<p class="note">Visible changes pass pixelmatch\'s colour distance at a threshold of {threshold}; '
            "the diff shows them in red, or every change when none is visible. Drag across an image to move the "
            "curtain.</p>",
            '<div class="table-wrap"><table><thead><tr><th>Image</th><th>Result</th><th class="number">Visible</th>'
            '<th class="number">Any</th></tr></thead><tbody>']
    for entry in results:
        visible = "" if entry["visible"] is None else f"{100.0 * entry['visible']:.2f} %"
        every = "" if entry["any"] is None else f"{100.0 * entry['any']:.2f} %"
        body.append(f'<tr><td>{html.escape(entry["name"])}</td><td>{html.escape(entry["result"])}</td>'
                    f'<td class="number">{visible}</td><td class="number">{every}</td></tr>')
    body.append("</tbody></table></div>")
    for entry in results:
        files = entry["files"]
        name = html.escape(entry["name"])
        if "before" in files and "after" in files:
            body.append(
                f'<section data-image="{name}" data-before="{uri(files["before"])}" data-diff="{uri(files["diff"])}">\n'
                f"<h2>{name}</h2>\n"
                '<div class="modes" role="group" aria-label="Left side">'
                '<button type="button" data-mode="before" aria-pressed="true">before</button>'
                '<button type="button" data-mode="diff" aria-pressed="false">diff</button></div>\n'
                f'<div class="curtain"><img class="right" alt="{name} after" src="{uri(files["after"])}">'
                f'<img class="left" alt="{name} on the left side" src="{uri(files["before"])}">'
                '<div class="seam"></div><span class="tag left-tag">before</span><span class="tag right-tag">after</span></div>\n'
                "</section>")
        elif files:
            side, file = next(iter(files.items()))
            body.append(f'<section data-image="{name}">\n<h2>{name}</h2>\n'
                        f'<p class="note">{html.escape(entry["result"].capitalize())}: only the {side} side drew it.</p>\n'
                        f'<div class="curtain"><img alt="{name}" src="{uri(file)}"></div>\n</section>')
    body.append(PAGE_SCRIPT)
    return "\n".join(body)


def write_outputs(results, output, title, threshold, images_url):
    markdown = table(results, images_url)
    (output / "result.md").write_text(markdown + "\n")
    (output / "result.json").write_text(json.dumps({"title": title, "threshold": threshold, "images": results}, indent=2) + "\n")
    (output / "index.html").write_text(page(results, output / "images", title, threshold))
    print(markdown)
    return 0 if all(entry["result"] == "same" for entry in results) else 1


def draw_side(tree, command, directory, side):
    shutil.rmtree(directory, ignore_errors=True)
    directory.mkdir(parents=True)
    environment = dict(os.environ, IMAGES_DIR=str(directory))
    log = directory.parent / f"{side}.log"
    with open(log, "w") as stream:
        status = subprocess.run(command, shell=True, cwd=tree, env=environment, stdout=stream, stderr=subprocess.STDOUT).returncode
    if status != 0:
        raise Unusable(f"the {side} side could not be drawn (status {status}), see {log}")


def draw_and_compare(arguments):
    root = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True).stdout.strip())
    output = pathlib.Path(arguments.draw_into or arguments.out).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if arguments.draw_into:
        sides = [("after", arguments.after, output / "images")]
    else:
        sides = []
        for side, commit, kept in (("before", arguments.before, arguments.before_images),
                                   ("after", arguments.after, arguments.after_images)):
            if kept:
                shutil.rmtree(output / side, ignore_errors=True)
                shutil.copytree(kept, output / side)
            else:
                sides.append((side, commit, output / side))
    with tempfile.TemporaryDirectory() as scratch:
        trees = []
        try:
            for side, commit, directory in sides:
                if commit is None:
                    draw_side(root, arguments.draw, directory, side)
                    continue
                tree = pathlib.Path(scratch) / side
                subprocess.run(["git", "-C", str(root), "worktree", "add", "--detach", "--quiet", str(tree), commit], check=True)
                trees.append(tree)
                draw_side(tree, arguments.draw, directory, side)
        finally:
            for tree in trees:
                subprocess.run(["git", "-C", str(root), "worktree", "remove", "--force", str(tree)], check=False)
    if arguments.draw_into:
        return 0
    results = compare_directories(output / "before", output / "after", output, arguments.threshold)
    return write_outputs(results, output, arguments.title, arguments.threshold, arguments.images_url)


def self_test():
    grey = bytes((128, 128, 128)) * 16
    faint = bytes((136, 136, 132)) + grey[3:]
    coloured = bytes((200, 40, 40)) + grey[3:]
    checks = []

    def check(claim, passed):
        checks.append(passed)
        print(f"  {'PASS' if passed else 'FAIL'}  {claim}")

    width, height, pixels = read_png(png(4, 4, coloured))
    check("a PNG written is read back the same", (width, height, pixels) == (4, 4, coloured))
    rows = b"".join(bytes((kind,)) + bytes(range(kind * 10, kind * 10 + 12)) for kind in range(5))
    filtered = PNG_SIGNATURE + struct.pack(">I", 13) + b"IHDR" + struct.pack(">IIBBBBB", 4, 5, 8, 2, 0, 0, 0) + b"\0\0\0\0"
    filtered += struct.pack(">I", len(zlib.compress(rows))) + b"IDAT" + zlib.compress(rows) + b"\0\0\0\0"
    width, height, pixels = read_png(filtered)
    check("a PNG with every filter type decodes to its size", (width, height, len(pixels)) == (4, 5, 60))

    cases = [
        ("identical images pass", grey, grey, 0, None),
        ("a faint change counts, but not as a visible one", grey, faint, 1, (0.0, 0.0625)),
        ("a change of colour counts as both", grey, coloured, 1, (0.0625, 0.0625)),
        ("an image missing after fails, and is still kept", grey, None, 1, None),
    ]
    for claim, before, after, status, shares in cases:
        with tempfile.TemporaryDirectory() as scratch:
            root = pathlib.Path(scratch)
            (root / "before").mkdir()
            (root / "after").mkdir()
            (root / "before" / "a.ppm").write_bytes(b"P6\n4 4\n255\n" + before)
            if after is not None:
                (root / "after" / "a.png").write_bytes(png(4, 4, after))
            with contextlib.redirect_stdout(io.StringIO()):
                results = compare_directories(root / "before", root / "after", root / "out", 0.1)
                got = write_outputs(results, root / "out", "Test", 0.1, "https://example.invalid/images")
            entry = results[0]
            passed = got == status
            if shares is not None:
                passed = passed and (entry["visible"], entry["any"]) == shares and (root / "out/images/a-diff.png").exists()
            if after is None:
                passed = passed and entry["result"] == "missing after" and (root / "out/images/a-before.png").exists()
            if status == 0:
                passed = passed and "Same on both sides: a." in (root / "out/result.md").read_text()
            else:
                passed = passed and "https://example.invalid/images/a-" in (root / "out/result.md").read_text()
            check(claim, passed)
    failures = checks.count(False)
    print("ALL PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--draw")
    parser.add_argument("--before")
    parser.add_argument("--before-images")
    parser.add_argument("--after-images")
    parser.add_argument("--draw-into")
    parser.add_argument("--after")
    parser.add_argument("--compare", nargs=2, metavar=("BEFORE", "AFTER"))
    parser.add_argument("--out", default="build/compare-images")
    parser.add_argument("--title", default="Images compared")
    parser.add_argument("--threshold", type=float, default=0.1)
    parser.add_argument("--images-url", default="")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    arguments, unknown = parser.parse_known_args()
    if arguments.help:
        print(__doc__)
        return 0
    if unknown or not 0.0 < arguments.threshold <= 1.0:
        print(__doc__, file=sys.stderr)
        return 2
    if arguments.self_test:
        return self_test()
    try:
        if arguments.compare:
            output = pathlib.Path(arguments.out).resolve()
            output.mkdir(parents=True, exist_ok=True)
            results = compare_directories(pathlib.Path(arguments.compare[0]), pathlib.Path(arguments.compare[1]), output, arguments.threshold)
            return write_outputs(results, output, arguments.title, arguments.threshold, arguments.images_url)
        sources = [arguments.before, arguments.before_images, arguments.draw_into]
        if not arguments.draw or sum(source is not None for source in sources) != 1:
            print(__doc__, file=sys.stderr)
            return 2
        if arguments.after and arguments.after_images:
            print(__doc__, file=sys.stderr)
            return 2
        for kept in (arguments.before_images, arguments.after_images):
            if kept and not pathlib.Path(kept).is_dir():
                print(f"compare-images: no directory {kept}", file=sys.stderr)
                return 2
        return draw_and_compare(arguments)
    except (Unusable, subprocess.CalledProcessError) as error:
        print(f"compare-images: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
