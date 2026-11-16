"""Copy or crop the deck's screenshots from raw captures into a folder.

SRC is the capture tool's output folder (one sub-folder per scenario: s0, s1, ...). DST gets the
named PNGs that docs/adoption/screenshots holds. Needs Pillow; run it in a throwaway container:

    docker run --rm -v <captures>:/src:ro -v <this folder>/crop.py:/w/crop.py:ro -v <out>:/dst \\
      python:3.14.10-slim sh -c "pip install -q pillow && python -I /w/crop.py /src /dst"
"""
import os
import sys
from PIL import Image

SRC, DST = sys.argv[1], sys.argv[2]
# name: (source path under SRC, crop box or None)
SHOTS = {
    "01-overview-top": ("s2/overview/_full.png", (150, 205, 1590, 578)),
    "02-needs-attention-test-block": ("s2/overview/viz_attention.png", (0, 0, 1424, 240)),
    "03-unregistered": ("s0/manage-expected-list/viz_unreg.png", None),
    "04-thresholds": ("s0/manage-mute--thresholds/viz_thresholds.png", None),
    "05-needs-attention-cribl-down": ("s5/overview/viz_attention.png", None),
    "06-restarts": ("s0/overview/viz_restarts.png", (0, 0, 1424, 280)),
    "07-tamper": ("s0/overview/viz_tamper.png", None),
    "08-host-detail-items": ("s2/host-wd2l-logsrv/viz_children.png", None),
    "09-mute-preview": ("s1/manage-mute--thresholds/viz_ov_preview.png", None),
    "10-mute-result": ("s1/manage-mute--thresholds-applied/viz_ov_result.png", None),
    "11-admin-log": ("s1/manage-admin-log/viz_log.png", None),
    "12-soh-top": ("s0/soh/_full.png", (150, 145, 1600, 605)),
    "13-hosts-muted": ("s1/overview/viz_k_host_muted.png", None),
    "14-test-block-command": ("s2-form/manage-test-blocks-admin/viz_bk_command.png", None),
    "15-recovered": ("s5/overview/viz_recovered.png", None),
}
os.makedirs(DST, exist_ok=True)
for name, (rel, box) in SHOTS.items():
    path = os.path.join(SRC, rel)
    if not os.path.exists(path):
        print("missing", rel)
        continue
    img = Image.open(path)
    if box:
        img = img.crop(box)
    img.save(os.path.join(DST, name + ".png"), optimize=True)
    print(name, img.size)
