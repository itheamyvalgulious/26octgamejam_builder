#!/usr/bin/env python3
"""
构造一个我 - Vector SVG Asset Generator
Generates clean, bio-mechanical vector SVGs for all block types, variants, and UI icons.
Easily editable, resolution independent, and version-controllable.
"""

import os
import math

BLOCK_DIR = "assets/textures/blocks"
UI_DIR = "assets/textures/ui"
os.makedirs(BLOCK_DIR, exist_ok=True)
os.makedirs(UI_DIR, exist_ok=True)

def write_svg(filepath, content):
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content.strip() + "\n")
    print(f"Generated: {filepath}")

# -------------------------------------------------------------
# Base SVG template
# -------------------------------------------------------------
def svg_wrap(inner_content, size=128):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}">
{inner_content}
</svg>"""

# -------------------------------------------------------------
# Block Inners (facing East / Right = (1, 0))
# -------------------------------------------------------------

def gen_basic(color_theme):
    # Somatic Cell: Cytoplasm with nucleus, organelles, cytoskeletal microfilaments
    c_bg, c_nuc, c_accent = color_theme
    return svg_wrap(f"""
  <defs>
    <radialGradient id="nucGrad" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="{c_nuc}" stop-opacity="0.9"/>
      <stop offset="100%" stop-color="{c_accent}" stop-opacity="0.3"/>
    </radialGradient>
    <filter id="glow">
      <feGaussianBlur stdDeviation="2" result="coloredBlur"/>
      <feMerge>
        <feMergeNode in="coloredBlur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>
  <!-- Background Cytoplasm -->
  <rect x="8" y="8" width="112" height="112" rx="16" fill="{c_bg}" fill-opacity="0.25" stroke="{c_accent}" stroke-width="1.5" stroke-dasharray="4,4"/>
  <!-- Microfilaments -->
  <path d="M 24 64 Q 64 32 104 64" fill="none" stroke="{c_accent}" stroke-width="2" opacity="0.4"/>
  <path d="M 24 64 Q 64 96 104 64" fill="none" stroke="{c_accent}" stroke-width="2" opacity="0.4"/>
  <path d="M 64 24 Q 96 64 64 104" fill="none" stroke="{c_accent}" stroke-width="2" opacity="0.3"/>
  <path d="M 64 24 Q 32 64 64 104" fill="none" stroke="{c_accent}" stroke-width="2" opacity="0.3"/>
  <!-- Nucleus & Nucleolus -->
  <circle cx="64" cy="64" r="26" fill="url(#nucGrad)" stroke="{c_nuc}" stroke-width="3" filter="url(#glow)"/>
  <circle cx="64" cy="64" r="14" fill="{c_accent}" opacity="0.75"/>
  <circle cx="68" cy="60" r="5" fill="#ffffff" opacity="0.8"/>
  <!-- Forward Sensory Cilium (Oriented Right) -->
  <polygon points="108,64 96,58 98,64 96,70" fill="{c_nuc}"/>
""")

def gen_inhibitor(color_theme):
    # Neuron / Synapse:
    # Front (Right) = Sensory receptor dendrites
    # Center = Neuron soma & nucleus
    # Back (Left) = Axon & synaptic terminal emitting suppression waves
    c_bg, c_soma, c_axon = color_theme
    return svg_wrap(f"""
  <defs>
    <filter id="synapseGlow">
      <feGaussianBlur stdDeviation="3" result="glow"/>
      <feMerge>
        <feMergeNode in="glow"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="16" fill="{c_bg}" fill-opacity="0.2"/>
  <!-- Rear Axon & Inhibitory Terminal (Left side) -->
  <path d="M 52 64 L 20 64" stroke="{c_axon}" stroke-width="5" stroke-linecap="round"/>
  <!-- Myelin Sheaths -->
  <rect x="24" y="58" width="10" height="12" rx="3" fill="{c_axon}" opacity="0.8"/>
  <rect x="38" y="58" width="10" height="12" rx="3" fill="{c_axon}" opacity="0.8"/>
  <!-- Suppression Ring Emitter (Left) -->
  <path d="M 16 48 A 18 18 0 0 0 16 80" fill="none" stroke="{c_axon}" stroke-width="3.5" stroke-linecap="round" opacity="0.85"/>
  <path d="M 10 40 A 26 26 0 0 0 10 88" fill="none" stroke="{c_axon}" stroke-width="2" stroke-linecap="round" stroke-dasharray="3,3" opacity="0.6"/>
  <!-- Soma (Cell Body) -->
  <path d="M 52 50 C 42 60, 42 68, 52 78 C 66 84, 76 78, 80 64 C 76 50, 66 44, 52 50 Z" fill="{c_soma}" filter="url(#synapseGlow)"/>
  <circle cx="62" cy="64" r="8" fill="#ffffff" opacity="0.9"/>
  <!-- Front Sensory Receptor Tentacles (Right side) -->
  <path d="M 80 64 L 108 64" stroke="{c_soma}" stroke-width="3.5" stroke-linecap="round"/>
  <path d="M 76 56 Q 96 46 106 38" fill="none" stroke="{c_soma}" stroke-width="2.5" stroke-linecap="round"/>
  <path d="M 76 72 Q 96 82 106 90" fill="none" stroke="{c_soma}" stroke-width="2.5" stroke-linecap="round"/>
  <circle cx="108" cy="64" r="4.5" fill="{c_axon}"/>
  <circle cx="106" cy="38" r="3.5" fill="{c_axon}"/>
  <circle cx="106" cy="90" r="3.5" fill="{c_axon}"/>
""")

def gen_pusher(color_theme):
    # Beetle / Insect Thruster:
    # Facing Right: Armored head pushing forward, shimmering wings/abdomen jet at back
    c_bg, c_chitin, c_jet = color_theme
    return svg_wrap(f"""
  <defs>
    <filter id="jetGlow">
      <feGaussianBlur stdDeviation="2.5" result="glow"/>
      <feMerge>
        <feMergeNode in="glow"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="16" fill="{c_bg}" fill-opacity="0.2"/>
  <!-- Abdomen & Wings (Left) -->
  <path d="M 20 64 Q 35 40 54 48 Q 48 64 54 80 Q 35 88 20 64 Z" fill="{c_jet}" opacity="0.85"/>
  <!-- Wing Veins -->
  <path d="M 46 44 L 28 32 Q 52 26 62 46" fill="none" stroke="{c_jet}" stroke-width="2" opacity="0.6"/>
  <path d="M 46 84 L 28 96 Q 52 102 62 82" fill="none" stroke="{c_jet}" stroke-width="2" opacity="0.6"/>
  <!-- Thorax / Chitin Body -->
  <ellipse cx="64" cy="64" rx="20" ry="16" fill="{c_chitin}"/>
  <!-- Pushing Horn / Mandibles (Right) -->
  <path d="M 78 52 L 108 58 L 96 64 L 108 70 L 78 76 Z" fill="{c_chitin}" filter="url(#jetGlow)"/>
  <!-- Thrust Arrow / Kinetic Chevron -->
  <polygon points="102,64 88,54 94,64 88,74" fill="#ffffff" opacity="0.9"/>
  <!-- Glowing Eye -->
  <circle cx="76" cy="60" r="3" fill="#ffffff"/>
  <circle cx="76" cy="68" r="3" fill="#ffffff"/>
""")

def gen_replicator(color_theme):
    # Mitosis / Cellular Splitter:
    # Left: Receiving organelle (takes from back)
    # Right: Budding daughter cell / twin spindle (spawns in front)
    c_bg, c_cell, c_dna = color_theme
    return svg_wrap(f"""
  <defs>
    <filter id="dnaGlow">
      <feGaussianBlur stdDeviation="2" result="glow"/>
      <feMerge><feMergeNode in="glow"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="16" fill="{c_bg}" fill-opacity="0.2"/>
  <!-- Dividing Cleavage Furrow -->
  <ellipse cx="44" cy="64" rx="20" ry="24" fill="{c_cell}" opacity="0.7"/>
  <ellipse cx="80" cy="64" rx="20" ry="24" fill="{c_cell}" opacity="0.9" filter="url(#dnaGlow)"/>
  <!-- Spindle Fibers connecting poles -->
  <path d="M 44 48 Q 62 56 80 48" stroke="{c_dna}" stroke-width="2.5" fill="none"/>
  <path d="M 44 64 L 80 64" stroke="{c_dna}" stroke-width="3" stroke-dasharray="4,2" fill="none"/>
  <path d="M 44 80 Q 62 72 80 80" stroke="{c_dna}" stroke-width="2.5" fill="none"/>
  <!-- Replicating DNA X-shapes -->
  <g transform="translate(44, 64) scale(0.7)">
    <line x1="-10" y1="-10" x2="10" y2="10" stroke="#ffffff" stroke-width="3.5" stroke-linecap="round"/>
    <line x1="10" y1="-10" x2="-10" y2="10" stroke="#ffffff" stroke-width="3.5" stroke-linecap="round"/>
  </g>
  <g transform="translate(80, 64) scale(0.7)">
    <line x1="-10" y1="-10" x2="10" y2="10" stroke="#ffffff" stroke-width="3.5" stroke-linecap="round"/>
    <line x1="10" y1="-10" x2="-10" y2="10" stroke="#ffffff" stroke-width="3.5" stroke-linecap="round"/>
  </g>
  <!-- Forward Emission Arrow (Right) -->
  <polygon points="110,64 98,56 102,64 98,72" fill="{c_dna}"/>
  <!-- Rear Intake Ring (Left) -->
  <circle cx="20" cy="64" r="8" fill="none" stroke="{c_dna}" stroke-width="3" stroke-dasharray="3,3"/>
""")

def gen_destroyer(color_theme):
    # Phagocyte / Acidic Bio-Maw:
    # Sharp chitinous fangs / pincers facing Right, ready to dissolve/chew forward block
    c_bg, c_maw, c_acid = color_theme
    return svg_wrap(f"""
  <defs>
    <radialGradient id="acidGrad" cx="40%" cy="50%" r="50%">
      <stop offset="0%" stop-color="{c_acid}"/>
      <stop offset="100%" stop-color="{c_maw}"/>
    </radialGradient>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="16" fill="{c_bg}" fill-opacity="0.2"/>
  <!-- Central Acid Gland -->
  <circle cx="50" cy="64" r="24" fill="url(#acidGrad)"/>
  <circle cx="46" cy="60" r="6" fill="#ffffff" opacity="0.6"/>
  <!-- Giant Pincer Jaws (Upper and Lower) -->
  <path d="M 40 40 Q 80 28 108 54 Q 78 50 54 58 Z" fill="{c_maw}" stroke="#ffffff" stroke-width="1.5"/>
  <path d="M 40 88 Q 80 100 108 74 Q 78 78 54 70 Z" fill="{c_maw}" stroke="#ffffff" stroke-width="1.5"/>
  <!-- Serrated Teeth -->
  <polygon points="68,48 76,56 82,48" fill="#ffffff"/>
  <polygon points="86,51 94,59 100,52" fill="#ffffff"/>
  <polygon points="68,80 76,72 82,80" fill="#ffffff"/>
  <polygon points="86,77 94,69 100,76" fill="#ffffff"/>
  <!-- Forward Acid Droplets -->
  <circle cx="102" cy="64" r="4.5" fill="{c_acid}"/>
  <circle cx="114" cy="64" r="3" fill="{c_acid}"/>
""")

def gen_rotator(color_theme, is_cw=True):
    # Cilia Swirl / Vortex Flagella:
    # Circular bio-rotor with spiral cilia tentacles
    c_bg, c_ring, c_arrow = color_theme
    # Direction arrows
    if is_cw:
        # Clockwise
        vortex_path = """
          <path d="M 64 30 C 84 30, 98 44, 98 64 C 98 76, 90 86, 78 92" fill="none" stroke="{c_arrow}" stroke-width="5" stroke-linecap="round"/>
          <polygon points="78,98 84,86 72,88" fill="{c_arrow}"/>
          <path d="M 64 98 C 44 98, 30 84, 30 64 C 30 52, 38 42, 50 36" fill="none" stroke="{c_arrow}" stroke-width="5" stroke-linecap="round"/>
          <polygon points="50,30 44,42 56,40" fill="{c_arrow}"/>
        """.format(c_arrow=c_arrow)
        badge = "CW"
    else:
        # Counter-Clockwise
        vortex_path = """
          <path d="M 64 30 C 44 30, 30 44, 30 64 C 30 76, 38 86, 50 92" fill="none" stroke="{c_arrow}" stroke-width="5" stroke-linecap="round"/>
          <polygon points="50,98 44,86 56,88" fill="{c_arrow}"/>
          <path d="M 64 98 C 84 98, 98 84, 98 64 C 98 52, 90 42, 78 36" fill="none" stroke="{c_arrow}" stroke-width="5" stroke-linecap="round"/>
          <polygon points="78,30 84,42 72,40" fill="{c_arrow}"/>
        """.format(c_arrow=c_arrow)
        badge = "CCW"

    return svg_wrap(f"""
  <defs>
    <filter id="swirlGlow">
      <feGaussianBlur stdDeviation="2"/>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="16" fill="{c_bg}" fill-opacity="0.2"/>
  <!-- Central Rotor Hub -->
  <circle cx="64" cy="64" r="32" fill="{c_ring}" fill-opacity="0.3" stroke="{c_ring}" stroke-width="3"/>
  <circle cx="64" cy="64" r="14" fill="{c_ring}"/>
  <circle cx="64" cy="64" r="6" fill="#ffffff"/>
  <!-- Swirl Arms -->
  <g filter="url(#swirlGlow)">
    {vortex_path}
  </g>
  <!-- Forward Target Aim (Pointer on Right) -->
  <polygon points="112,64 102,56 102,72" fill="{c_ring}"/>
  <!-- Sub-mode badge -->
  <rect x="14" y="14" width="32" height="16" rx="4" fill="{c_ring}" opacity="0.85"/>
  <text x="30" y="26" font-family="sans-serif" font-size="10" font-weight="bold" fill="#ffffff" text-anchor="middle">{badge}</text>
""")

def gen_hard(color_theme):
    # Heavy Chitinous Armor / Exoskeleton Plate:
    c_bg, c_plate, c_rivet = color_theme
    return svg_wrap(f"""
  <rect x="6" y="6" width="116" height="116" rx="14" fill="{c_plate}" stroke="{c_rivet}" stroke-width="4"/>
  <!-- Heavy layered plates -->
  <polygon points="16,16 64,28 112,16 100,64 112,112 64,100 16,112 28,64" fill="{c_bg}" opacity="0.5"/>
  <polygon points="28,28 64,38 100,28 90,64 100,100 64,90 28,100 38,64" fill="{c_plate}" stroke="{c_rivet}" stroke-width="2"/>
  <!-- Central Chitin Keystone -->
  <polygon points="64,48 80,64 64,80 48,64" fill="{c_rivet}"/>
  <circle cx="64" cy="64" r="5" fill="#ffffff" opacity="0.8"/>
  <!-- Corner Rivets -->
  <circle cx="20" cy="20" r="5" fill="{c_rivet}"/>
  <circle cx="108" cy="20" r="5" fill="{c_rivet}"/>
  <circle cx="20" cy="108" r="5" fill="{c_rivet}"/>
  <circle cx="108" cy="108" r="5" fill="{c_rivet}"/>
""")

def gen_wanderer(color_theme):
    # Roaming Critter / Alien Parasite:
    c_bg, c_body, c_eye = color_theme
    return svg_wrap(f"""
  <defs>
    <filter id="creepGlow"><feGaussianBlur stdDeviation="2"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="16" fill="{c_bg}" fill-opacity="0.15"/>
  <!-- Multi-jointed Crawler Legs -->
  <path d="M 44 76 L 30 102 L 18 100" stroke="{c_body}" stroke-width="4" stroke-linecap="round" fill="none"/>
  <path d="M 64 78 L 64 106 L 56 112" stroke="{c_body}" stroke-width="4" stroke-linecap="round" fill="none"/>
  <path d="M 84 76 L 98 102 L 110 100" stroke="{c_body}" stroke-width="4" stroke-linecap="round" fill="none"/>
  <!-- Slug/Centipede Bio Body (Horizontal blob) -->
  <path d="M 28 64 C 28 44, 46 36, 70 42 C 94 48, 102 56, 104 68 C 104 82, 88 88, 64 86 C 40 84, 28 78, 28 64 Z" fill="{c_body}" filter="url(#creepGlow)"/>
  <!-- Spiked Dorsal Ridge -->
  <polygon points="36,44 42,28 48,42" fill="{c_body}"/>
  <polygon points="56,40 64,22 72,40" fill="{c_body}"/>
  <polygon points="80,44 88,30 94,46" fill="{c_body}"/>
  <!-- Compound Glowing Eye (Right side) -->
  <ellipse cx="88" cy="62" rx="12" ry="10" fill="{c_eye}"/>
  <ellipse cx="91" cy="61" rx="5" ry="4" fill="#ffffff"/>
  <!-- Menacing Antenna -->
  <path d="M 96 52 Q 112 40 120 46" stroke="{c_body}" stroke-width="3" stroke-linecap="round" fill="none"/>
  <circle cx="120" cy="46" r="3" fill="{c_eye}"/>
""")

def gen_treasure(color_theme):
    # High-Energy Nutrient Plasmid / Golden Core:
    c_bg, c_gold, c_sparkle = color_theme
    return svg_wrap(f"""
  <defs>
    <radialGradient id="goldGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="{c_sparkle}"/>
      <stop offset="60%" stop-color="{c_gold}"/>
      <stop offset="100%" stop-color="{c_gold}" stop-opacity="0.1"/>
    </radialGradient>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="16" fill="{c_bg}" fill-opacity="0.15"/>
  <!-- Outer Energy Pulsing Ring -->
  <circle cx="64" cy="64" r="44" fill="none" stroke="{c_gold}" stroke-width="2.5" stroke-dasharray="6,4"/>
  <!-- Golden Core -->
  <circle cx="64" cy="64" r="32" fill="url(#goldGlow)"/>
  <!-- Brilliant Facets -->
  <polygon points="64,36 84,54 84,74 64,92 44,74 44,54" fill="{c_sparkle}" opacity="0.75" stroke="#ffffff" stroke-width="2"/>
  <polygon points="64,44 76,58 76,70 64,84 52,70 52,58" fill="#ffffff" opacity="0.9"/>
  <!-- Sparkles -->
  <polygon points="64,20 67,30 77,33 67,36 64,46 61,36 51,33 61,30" fill="#ffffff"/>
  <polygon points="98,54 100,60 106,62 100,64 98,70 96,64 90,62 96,60" fill="#ffffff"/>
""")

def gen_pollution(color_theme):
    # Pathogen / Necrotic Spore Hive:
    c_bg, c_virus, c_spore = color_theme
    return svg_wrap(f"""
  <defs>
    <radialGradient id="polluteGrad" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="{c_spore}"/>
      <stop offset="70%" stop-color="{c_virus}"/>
      <stop offset="100%" stop-color="#050505"/>
    </radialGradient>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="16" fill="{c_bg}" fill-opacity="0.3"/>
  <!-- Spore Radiating Spikes -->
  <g stroke="{c_virus}" stroke-width="3.5" stroke-linecap="round">
    <line x1="64" y1="20" x2="64" y2="40"/>
    <line x1="64" y1="108" x2="64" y2="88"/>
    <line x1="20" y1="64" x2="40" y2="64"/>
    <line x1="108" y1="64" x2="88" y2="64"/>
    <line x1="32" y1="32" x2="48" y2="48"/>
    <line x1="96" y1="32" x2="80" y2="48"/>
    <line x1="32" y1="96" x2="48" y2="80"/>
    <line x1="96" y1="96" x2="80" y2="80"/>
  </g>
  <circle cx="64" cy="20" r="4.5" fill="{c_spore}"/>
  <circle cx="64" cy="108" r="4.5" fill="{c_spore}"/>
  <circle cx="20" cy="64" r="4.5" fill="{c_spore}"/>
  <circle cx="108" cy="64" r="4.5" fill="{c_spore}"/>
  <!-- Pulsing Bio-Tumor -->
  <circle cx="64" cy="64" r="30" fill="url(#polluteGrad)"/>
  <!-- Toxic pustules -->
  <circle cx="54" cy="56" r="8" fill="{c_spore}" opacity="0.8"/>
  <circle cx="74" cy="58" r="6" fill="{c_spore}" opacity="0.8"/>
  <circle cx="60" cy="74" r="9" fill="{c_spore}" opacity="0.8"/>
  <circle cx="56" cy="54" r="2.5" fill="#ffffff" opacity="0.9"/>
  <!-- Hazard Mark -->
  <path d="M 64 50 L 74 70 L 54 70 Z" fill="#000000" opacity="0.5"/>
""")

# -------------------------------------------------------------
# Color Themes (3 variants per type for skin customization)
# -------------------------------------------------------------

THEMES = {
    "basic": [
        ("#0f2a2e", "#20b2aa", "#48d1cc"), # Cyan / Teal
        ("#1a2b1f", "#3cb371", "#7fffd4"), # Emerald / Mint
        ("#1f1f2e", "#6495ed", "#87ceeb"), # Slate / Sky
    ],
    "inhibitor": [
        ("#2b103a", "#9b30ff", "#ba55d3"), # Purple Synapse
        ("#121b3b", "#436eee", "#00bfff"), # Electric Blue Synapse
        ("#3a0d24", "#e066ff", "#ff69b4"), # Neon Magenta Synapse
    ],
    "pusher": [
        ("#3a2507", "#ff8c00", "#ffd700"), # Amber Beetle
        ("#3a1307", "#ff4500", "#ff7f50"), # Fire Beetle
        ("#263a07", "#9acd32", "#adff2f"), # Bio-Lime Beetle
    ],
    "replicator": [
        ("#073a1d", "#00ff7f", "#32cd32"), # Green Mitosis
        ("#07333a", "#00ced1", "#7fffd4"), # Cyan Mitosis
        ("#2d3a07", "#b8860b", "#ffff00"), # Yellow Spindle
    ],
    "destroyer": [
        ("#3a0a0a", "#dc143c", "#ff3030"), # Crimson Maw
        ("#3a0026", "#c71585", "#ff1493"), # Deep Violet Maw
        ("#3a1800", "#cd3700", "#ff4500"), # Burning Maw
    ],
    "rotator": [
        ("#08223a", "#1e90ff", "#00ffff"), # Azure Vortex
        ("#1a083a", "#7b68ee", "#b0c4de"), # Violet Swirl
        ("#083a30", "#20b2aa", "#00fa9a"), # Aquamarine Swirl
    ],
    "hard": [
        ("#1a1c20", "#4f5866", "#8b94a0"), # Granite Chitin
        ("#201c18", "#5a5046", "#9c8e80"), # Bone Chitin
        ("#141e1c", "#3e524e", "#708c84"), # Obsidian Chitin
    ],
    "wanderer": [
        ("#3a082b", "#d02090", "#ff1493"), # Parasite Pink
        ("#2b083a", "#8a2be2", "#da70d6"), # Void Crawler
        ("#3a2808", "#cd853f", "#ffa500"), # Rust Stalker
    ],
    "treasure": [
        ("#3a3000", "#ffd700", "#ffffff"), # Golden Plasmid
        ("#00303a", "#00ffff", "#ffffff"), # Cyan Diamond
        ("#3a0030", "#ff69b4", "#ffffff"), # Rose Crystal
    ],
    "pollution": [
        ("#2e0808", "#8b0000", "#ff4500"), # Necrotic Red
        ("#1a1a00", "#556b2f", "#7cfc00"), # Toxic Slime
        ("#1c082e", "#4b0082", "#9400d3"), # Void Blight
    ],
}

# Generate all blocks and variants
for btype, variants in THEMES.items():
    for idx, theme in enumerate(variants):
        if btype == "basic":
            write_svg(f"{BLOCK_DIR}/basic_{idx}.svg", gen_basic(theme))
        elif btype == "inhibitor":
            write_svg(f"{BLOCK_DIR}/inhibitor_{idx}.svg", gen_inhibitor(theme))
        elif btype == "pusher":
            write_svg(f"{BLOCK_DIR}/pusher_{idx}.svg", gen_pusher(theme))
        elif btype == "replicator":
            write_svg(f"{BLOCK_DIR}/replicator_{idx}.svg", gen_replicator(theme))
        elif btype == "destroyer":
            write_svg(f"{BLOCK_DIR}/destroyer_{idx}.svg", gen_destroyer(theme))
        elif btype == "rotator":
            write_svg(f"{BLOCK_DIR}/rotator_cw_{idx}.svg", gen_rotator(theme, is_cw=True))
            write_svg(f"{BLOCK_DIR}/rotator_ccw_{idx}.svg", gen_rotator(theme, is_cw=False))
        elif btype == "hard":
            write_svg(f"{BLOCK_DIR}/hard_{idx}.svg", gen_hard(theme))
        elif btype == "wanderer":
            write_svg(f"{BLOCK_DIR}/wanderer_{idx}.svg", gen_wanderer(theme))
        elif btype == "treasure":
            write_svg(f"{BLOCK_DIR}/treasure_{idx}.svg", gen_treasure(theme))
        elif btype == "pollution":
            write_svg(f"{BLOCK_DIR}/pollution_{idx}.svg", gen_pollution(theme))

# -------------------------------------------------------------
# Borders & UI Assets
# -------------------------------------------------------------

# Standalone Border (Default cell wall)
border_default = svg_wrap("""
  <rect x="2" y="2" width="124" height="124" rx="16" fill="none" stroke="#3a4b5c" stroke-width="4"/>
  <rect x="5" y="5" width="118" height="118" rx="14" fill="none" stroke="#1f2833" stroke-width="2"/>
""")
write_svg(f"{BLOCK_DIR}/border_default.svg", border_default)

# Inhibited Overlay (Electric neural disruption mesh)
inhibited_overlay = svg_wrap("""
  <rect x="4" y="4" width="120" height="120" rx="14" fill="#1e0038" fill-opacity="0.6"/>
  <path d="M 12 12 L 116 116 M 116 12 L 12 116" stroke="#bf55ec" stroke-width="3" stroke-dasharray="6,4"/>
  <circle cx="64" cy="64" r="28" fill="none" stroke="#ff0055" stroke-width="3" stroke-dasharray="4,4"/>
  <line x1="40" y1="64" x2="88" y2="64" stroke="#ff0055" stroke-width="4"/>
""")
write_svg(f"{BLOCK_DIR}/inhibited_overlay.svg", inhibited_overlay)

# UI Icons: Play, Pause, Step, Reset, Save, Load, Clear, Group, RotateCW, RotateCCW, Flip
def gen_ui_icon(name, inner_svg):
    return svg_wrap(f"""
      <rect x="4" y="4" width="120" height="120" rx="20" fill="#1b222d" stroke="#2d3a4d" stroke-width="3"/>
      {inner_svg}
    """)

write_svg(f"{UI_DIR}/play.svg", gen_ui_icon("play", '<polygon points="46,34 94,64 46,94" fill="#00ffaa"/>'))
write_svg(f"{UI_DIR}/pause.svg", gen_ui_icon("pause", '<rect x="40" y="34" width="16" height="60" rx="4" fill="#ffcc00"/><rect x="72" y="34" width="16" height="60" rx="4" fill="#ffcc00"/>'))
write_svg(f"{UI_DIR}/step.svg", gen_ui_icon("step", '<polygon points="40,36 76,64 40,92" fill="#00d4ff"/><rect x="80" y="36" width="10" height="56" rx="3" fill="#00d4ff"/>'))
write_svg(f"{UI_DIR}/reset.svg", gen_ui_icon("reset", '<path d="M 64 32 A 32 32 0 1 1 36 46" fill="none" stroke="#ff5555" stroke-width="8" stroke-linecap="round"/><polygon points="36,24 36,54 62,40" fill="#ff5555"/>'))
write_svg(f"{UI_DIR}/save.svg", gen_ui_icon("save", '<path d="M 34 30 L 86 30 L 98 42 L 98 98 L 34 98 Z" fill="#2d3a4d" stroke="#5da0ff" stroke-width="5"/><rect x="46" y="30" width="36" height="26" fill="#1b222d"/><rect x="44" y="68" width="40" height="30" fill="#5da0ff"/>'))
write_svg(f"{UI_DIR}/load.svg", gen_ui_icon("load", '<path d="M 28 42 L 52 42 L 62 52 L 100 52 L 100 96 L 28 96 Z" fill="#2d3a4d" stroke="#00ffaa" stroke-width="5"/><polygon points="64,60 64,84 52,72 76,72" fill="#00ffaa"/>'))
write_svg(f"{UI_DIR}/clear.svg", gen_ui_icon("clear", '<line x1="38" y1="38" x2="90" y2="90" stroke="#ff4444" stroke-width="8" stroke-linecap="round"/><line x1="90" y1="38" x2="38" y2="90" stroke="#ff4444" stroke-width="8" stroke-linecap="round"/>'))
write_svg(f"{UI_DIR}/group.svg", gen_ui_icon("group", '<rect x="28" y="28" width="72" height="72" rx="12" fill="none" stroke="#ffaa00" stroke-width="6" stroke-dasharray="8,6"/><circle cx="48" cy="48" r="8" fill="#ffaa00"/><circle cx="80" cy="48" r="8" fill="#ffaa00"/><circle cx="48" cy="80" r="8" fill="#ffaa00"/><circle cx="80" cy="80" r="8" fill="#ffaa00"/>'))

print("All SVG assets successfully generated!")
