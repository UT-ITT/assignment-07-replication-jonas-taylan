"""Renders the latency comparison chart for the documentation.

Run from anywhere: python3 figures/make_latency_chart.py
Requires matplotlib. Numbers are the measured averages reported in
documentation.md (Section 2, "Performance compared to the paper").
"""

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import Patch

plt.rcParams["font.family"] = "DejaVu Sans"

# Measured averages (warm, n=8 server; n=7 end-to-end)
phone = 570
network = 333
screenshot = 103
matching = 107  # match + encode
our_total = phone + network + screenshot + matching

paper_field = 878
paper_lab = 90

# Colors: our components in a cool->warm progression, paper bars neutral gray
c_phone = "#63B3ED"
c_network = "#F6AD55"
c_screenshot = "#9AE6B4"
c_matching = "#276749"
c_paper = "#A0AEC0"

fig, ax = plt.subplots(figsize=(9, 5.5))

x_our, x_field, x_lab = 0, 1.1, 2.2
width = 0.7

# Our stacked bar
segments = [
    (phone, c_phone, "Phone capture"),
    (network, c_network, "Network transfer"),
    (screenshot, c_screenshot, "Screenshot"),
    (matching, c_matching, "Matching"),
]
bottom = 0
for value, color, _ in segments:
    ax.bar(x_our, value, width, bottom=bottom, color=color, edgecolor="white", linewidth=1.5)
    if value > 60:
        ax.text(x_our, bottom + value / 2, f"{value} ms", ha="center", va="center",
                color="white" if color == c_matching else "#1A202C", fontsize=10, fontweight="bold")
    bottom += value
ax.text(x_our, our_total + 25, f"{our_total} ms", ha="center", va="bottom", fontsize=11, fontweight="bold")

# Paper field bar
ax.bar(x_field, paper_field, width, color=c_paper, edgecolor="white", linewidth=1.5)
ax.text(x_field, paper_field + 25, f"{paper_field} ms", ha="center", va="bottom", fontsize=11, fontweight="bold")

# Paper lab bar
ax.bar(x_lab, paper_lab, width, color=c_paper, edgecolor="white", linewidth=1.5)
ax.text(x_lab, paper_lab + 25, f"{paper_lab} ms", ha="center", va="bottom", fontsize=11, fontweight="bold")

ax.set_xticks([x_our, x_field, x_lab])
ax.set_xticklabels(["Our app\n(end-to-end)", "Paper\nfield study (n=19)", "Paper\nlab (processing)"], fontsize=10)
ax.set_ylabel("Latency (ms)", fontsize=11)
ax.set_title("End-to-end latency vs. paper benchmarks", fontsize=13, fontweight="bold", pad=15)
ax.set_ylim(0, 1300)

ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)
ax.grid(axis="y", color="#E2E8F0", linewidth=0.8)
ax.set_axisbelow(True)

legend_handles = [Patch(facecolor=c, label=l) for v, c, l in segments]
ax.legend(handles=legend_handles, loc="upper right", frameon=False, fontsize=9, title="Our components")

fig.text(0.5, -0.02,
         "Our matching alone (~107 ms) is on par with the paper's 90 ms lab processing time;\n"
         "the larger end-to-end total is dominated by on-device photo capture and network transfer.",
         ha="center", fontsize=9, color="#4A5568")

plt.tight_layout()
out = Path(__file__).parent / "latency-comparison.png"
plt.savefig(out, dpi=150, bbox_inches="tight", facecolor="white")
print(f"saved {out}")
