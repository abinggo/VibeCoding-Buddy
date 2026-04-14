#!/usr/bin/env python3
"""Generate pixel art sprite sheets for Vibe Buddy.

Each sprite sheet is 64x16 (4 frames of 16x16).
Output: sprites/{theme}/{state}.png
"""
import struct
import zlib
import os


def make_png(width, height, pixels):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    raw = b''
    for row in pixels:
        raw += b'\x00'
        for r, g, b, a in row:
            raw += struct.pack('BBBB', r, g, b, a)

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(raw))
    iend = chunk(b'IEND', b'')
    return sig + ihdr + idat + iend


def dp(pixels, x, y, color):
    if 0 <= y < len(pixels) and 0 <= x < len(pixels[0]):
        pixels[y][x] = color


def dr(pixels, x, y, w, h, color):
    for dy in range(h):
        for dx in range(w):
            dp(pixels, x + dx, y + dy, color)


T = (0, 0, 0, 0)

# Colors
SKIN = (255, 206, 158, 255)
HAIR = (80, 50, 30, 255)
SHIRT = (60, 100, 200, 255)
PANTS = (60, 60, 100, 255)
SHOE = (50, 40, 30, 255)
EYE = (40, 40, 60, 255)
MOUTH = (200, 80, 80, 255)
DESK = (120, 80, 50, 255)
DESK_TOP = (150, 100, 65, 255)
MONITOR = (50, 50, 70, 255)
SCREEN = (40, 180, 120, 255)
SCREEN2 = (60, 140, 200, 255)
CHAIR = (80, 80, 100, 255)
SWEAT = (100, 180, 255, 255)
STAR = (255, 220, 50, 255)
EXCLAIM = (255, 80, 80, 255)
GREEN_GLOW = (74, 222, 128, 255)
YELLOW_GLOW = (251, 191, 36, 255)
WHITE = (255, 255, 255, 255)
HAND = (245, 196, 148, 255)

CAT_BODY = (255, 160, 60, 255)
CAT_DARK = (200, 120, 40, 255)
CAT_BELLY = (255, 230, 200, 255)
CAT_EYE = (50, 200, 100, 255)
CAT_NOSE = (255, 120, 120, 255)
LAPTOP = (100, 100, 120, 255)
LAPTOP_SCREEN = (80, 200, 150, 255)

ROBOT_BODY = (140, 160, 180, 255)
ROBOT_DARK = (100, 120, 140, 255)
ROBOT_LIGHT = (180, 200, 220, 255)
ROBOT_EYE = (0, 255, 200, 255)
ROBOT_ANTENNA = (255, 100, 100, 255)


def new_frame():
    return [[T] * 16 for _ in range(16)]


# ═══════════════════════════════════════════════
# OFFICE HUMAN THEME
# ═══════════════════════════════════════════════

def draw_desk_and_monitor(f, screen_color):
    """Draw a desk with monitor at left side of frame."""
    # Desk surface
    dr(f, 0, 11, 7, 1, DESK_TOP)
    # Desk legs
    dr(f, 0, 12, 1, 3, DESK)
    dr(f, 6, 12, 1, 3, DESK)
    # Monitor stand
    dp(f, 3, 10, MONITOR)
    # Monitor body
    dr(f, 1, 6, 5, 4, MONITOR)
    # Screen
    dr(f, 2, 7, 3, 2, screen_color)


def draw_sitting_human(f, hair_color, shirt_color, yo=0):
    """Draw a human sitting on a chair, facing left toward the desk."""
    # Chair
    dr(f, 8, 12, 4, 1, CHAIR)
    dp(f, 8, 13, CHAIR)
    dp(f, 11, 13, CHAIR)
    dp(f, 8, 14, CHAIR)
    dp(f, 11, 14, CHAIR)
    # Chair back
    dr(f, 11, 8, 1, 4, CHAIR)

    # Hair
    dr(f, 8, 3 + yo, 3, 1, hair_color)
    dr(f, 7, 4 + yo, 4, 1, hair_color)

    # Head
    dr(f, 7, 5 + yo, 4, 3, SKIN)

    # Eye (facing left)
    dp(f, 7, 6 + yo, EYE)

    # Body (shirt)
    dr(f, 7, 8 + yo, 4, 3, shirt_color)

    # Pants (sitting)
    dr(f, 7, 11, 4, 1, PANTS)

    # Feet
    dp(f, 7, 12, SHOE)
    dp(f, 8, 12, SHOE)


def make_office_working():
    """Human sitting at desk, typing frantically. Arms alternate, screen flickers."""
    frames = []
    for i in range(4):
        f = new_frame()
        screen_c = SCREEN if i % 2 == 0 else SCREEN2
        draw_desk_and_monitor(f, screen_c)

        yo = -1 if i in [1, 3] else 0  # slight head bob from typing
        draw_sitting_human(f, HAIR, SHIRT, yo)

        # Arms/hands typing on keyboard area (on the desk)
        if i == 0:
            dp(f, 5, 10 + yo, HAND)
            dp(f, 6, 10 + yo, HAND)
        elif i == 1:
            dp(f, 4, 10 + yo, HAND)
            dp(f, 6, 11 + yo, HAND)
        elif i == 2:
            dp(f, 5, 11 + yo, HAND)
            dp(f, 6, 10 + yo, HAND)
        else:
            dp(f, 4, 11 + yo, HAND)
            dp(f, 5, 10 + yo, HAND)

        # Keyboard on desk
        dr(f, 3, 11, 4, 1, (80, 80, 90, 255))

        # Screen text flicker
        if i == 0:
            dp(f, 2, 7, WHITE)
            dp(f, 3, 7, WHITE)
        elif i == 1:
            dp(f, 2, 8, WHITE)
            dp(f, 3, 8, WHITE)
            dp(f, 4, 7, WHITE)
        elif i == 2:
            dp(f, 2, 7, WHITE)
            dp(f, 4, 8, WHITE)
        else:
            dp(f, 3, 7, WHITE)
            dp(f, 2, 8, WHITE)
            dp(f, 4, 8, WHITE)

        # Activity sparkle
        if i % 2 == 0:
            dp(f, 14, 2, GREEN_GLOW)
        else:
            dp(f, 15, 1, GREEN_GLOW)

        frames.append(f)
    return frames


def make_office_idle():
    """Human sitting at desk, leaning back, looking bored / yawning."""
    frames = []
    for i in range(4):
        f = new_frame()
        draw_desk_and_monitor(f, (30, 60, 40, 255))  # dim screen
        draw_sitting_human(f, HAIR, SHIRT)

        # Resting hands
        dp(f, 6, 10, HAND)

        # Eye animation (sleepy)
        if i in [1, 2]:
            # Closed eyes (yawn)
            dp(f, 7, 6, SKIN)  # overwrite eye with skin = closed
            # Open mouth for yawn
            dp(f, 7, 7, (180, 80, 80, 255))

        # Z z z floating
        if i >= 0:
            dp(f, 13, 2, (150, 150, 200, 200))
        if i >= 1:
            dp(f, 14, 1, (130, 130, 180, 180))
        if i >= 2:
            dp(f, 15, 0, (110, 110, 160, 150))

        frames.append(f)
    return frames


def make_office_waiting():
    """Human at desk, turned toward camera, hand raised, bouncing."""
    frames = []
    for i in range(4):
        f = new_frame()
        draw_desk_and_monitor(f, (60, 60, 80, 255))  # standby screen
        yo = -1 if i in [0, 2] else 0
        draw_sitting_human(f, HAIR, SHIRT, yo)

        # Resting hand on desk
        dp(f, 6, 10 + yo, HAND)

        # Raised hand (waving)
        rx = 12 + (i % 2)
        dp(f, rx, 5 + yo, HAND)
        dp(f, rx, 4 + yo, HAND)

        # Exclamation/question mark above head
        if i < 3:
            dp(f, 14, 1 + yo, YELLOW_GLOW)
            dp(f, 14, 2 + yo, YELLOW_GLOW)
            dp(f, 14, 4 + yo, YELLOW_GLOW)

        # Sweat drop
        if i in [1, 2]:
            dp(f, 6, 4 + yo, SWEAT)

        frames.append(f)
    return frames


def make_office_done():
    """Human jumping up from chair, celebrating with stars."""
    frames = []
    for i in range(4):
        f = new_frame()
        draw_desk_and_monitor(f, GREEN_GLOW)  # success screen

        # Chair still there
        dr(f, 8, 12, 4, 1, CHAIR)
        dp(f, 8, 13, CHAIR)
        dp(f, 11, 13, CHAIR)
        dp(f, 8, 14, CHAIR)
        dp(f, 11, 14, CHAIR)
        dr(f, 11, 8, 1, 4, CHAIR)

        yo = -2 if i in [1, 2] else 0  # jump

        # Hair
        dr(f, 8, 3 + yo, 3, 1, HAIR)
        dr(f, 7, 4 + yo, 4, 1, HAIR)
        # Head
        dr(f, 7, 5 + yo, 4, 3, SKIN)
        # Happy eyes
        dp(f, 7, 6 + yo, STAR)
        # Big smile
        dp(f, 7, 7 + yo, (255, 120, 120, 255))
        dp(f, 8, 7 + yo, (255, 120, 120, 255))
        # Body
        dr(f, 7, 8 + yo, 4, 3, SHIRT)
        # Raised arms celebrating
        dp(f, 6, 6 + yo, HAND)
        dp(f, 5, 5 + yo, HAND)
        dp(f, 12, 6 + yo, HAND)
        dp(f, 13, 5 + yo, HAND)
        # Legs
        dr(f, 7, 11 + yo, 2, 1, PANTS)
        dr(f, 9, 11 + yo, 2, 1, PANTS)
        dp(f, 7, 12 + yo, SHOE)
        dp(f, 10, 12 + yo, SHOE)

        # Stars / confetti
        stars = [
            [(1, 1), (14, 3)],
            [(2, 0), (13, 1), (15, 4)],
            [(0, 2), (14, 0), (3, 4)],
            [(1, 3), (15, 2), (13, 0)],
        ]
        for sx, sy in stars[i]:
            dp(f, sx, sy, STAR)

        frames.append(f)
    return frames


# ═══════════════════════════════════════════════
# PIXEL PETS (CAT) THEME
# ═══════════════════════════════════════════════

def draw_cat_base(frame, yo=0):
    # Ears
    dp(frame, 4, 3 + yo, CAT_BODY)
    dp(frame, 11, 3 + yo, CAT_BODY)
    dp(frame, 4, 4 + yo, CAT_BODY)
    dp(frame, 5, 4 + yo, CAT_DARK)
    dp(frame, 10, 4 + yo, CAT_DARK)
    dp(frame, 11, 4 + yo, CAT_BODY)
    # Head
    dr(frame, 4, 5 + yo, 8, 3, CAT_BODY)
    # Eyes
    dp(frame, 5, 6 + yo, CAT_EYE)
    dp(frame, 10, 6 + yo, CAT_EYE)
    # Nose
    dp(frame, 7, 7 + yo, CAT_NOSE)
    dp(frame, 8, 7 + yo, CAT_NOSE)
    # Whiskers
    dp(frame, 3, 7 + yo, CAT_DARK)
    dp(frame, 12, 7 + yo, CAT_DARK)
    # Body
    dr(frame, 5, 8 + yo, 6, 4, CAT_BODY)
    dr(frame, 6, 9 + yo, 4, 2, CAT_BELLY)
    # Legs
    dr(frame, 5, 12 + yo, 2, 2, CAT_BODY)
    dr(frame, 9, 12 + yo, 2, 2, CAT_BODY)


def draw_cat_at_laptop(f, yo=0, screen_c=LAPTOP_SCREEN):
    """Cat sitting in front of a small laptop."""
    # Laptop base
    dr(f, 1, 11 + yo, 5, 1, LAPTOP)
    # Laptop screen (angled)
    dr(f, 1, 8 + yo, 5, 3, LAPTOP)
    dr(f, 2, 9 + yo, 3, 1, screen_c)


def make_cat_working():
    frames = []
    for i in range(4):
        f = new_frame()
        yo = 0
        screen_c = LAPTOP_SCREEN if i % 2 == 0 else (100, 220, 180, 255)
        draw_cat_at_laptop(f, yo, screen_c)
        draw_cat_base(f, yo)

        # Paws on laptop (typing)
        if i % 2 == 0:
            dp(f, 4, 10, CAT_BODY)
            dp(f, 3, 11, CAT_BODY)
        else:
            dp(f, 3, 10, CAT_BODY)
            dp(f, 4, 11, CAT_BODY)

        # Tail wag
        tx = 12 + (i % 2)
        dp(f, tx, 9, CAT_BODY)
        dp(f, tx + 1, 8, CAT_BODY)

        # Focus sparkle
        if i == 0: dp(f, 14, 3, GREEN_GLOW)
        if i == 2: dp(f, 13, 2, GREEN_GLOW)

        frames.append(f)
    return frames


def make_cat_idle():
    frames = []
    for i in range(4):
        f = new_frame()
        yo = 1 if i in [1, 2] else 0
        draw_cat_base(f, yo)
        # Curled tail
        dp(f, 12, 10 + yo, CAT_BODY)
        dp(f, 13, 9 + yo, CAT_BODY)
        # Closed eyes (sleeping)
        if i in [1, 2]:
            dp(f, 5, 6 + yo, CAT_DARK)
            dp(f, 10, 6 + yo, CAT_DARK)
        # Zzz
        if i >= 1: dp(f, 13, 3, (150, 150, 200, 200))
        if i >= 2: dp(f, 14, 2, (120, 120, 180, 150))
        if i >= 3: dp(f, 15, 1, (100, 100, 160, 120))
        frames.append(f)
    return frames


def make_cat_waiting():
    frames = []
    for i in range(4):
        f = new_frame()
        yo = -1 if i in [0, 2] else 0
        draw_cat_base(f, yo)
        # Extra perked ears
        dp(f, 4, 2 + yo, CAT_BODY)
        dp(f, 11, 2 + yo, CAT_BODY)
        # Tail up
        dp(f, 12, 8 + yo, CAT_BODY)
        dp(f, 13, 7 + yo, CAT_BODY)
        dp(f, 14, 6 + yo, CAT_BODY)
        # Question mark
        dp(f, 14, 2 + yo, YELLOW_GLOW)
        dp(f, 14, 3 + yo, YELLOW_GLOW)
        dp(f, 14, 5 + yo, YELLOW_GLOW)
        frames.append(f)
    return frames


def make_cat_done():
    frames = []
    for i in range(4):
        f = new_frame()
        yo = -1 if i in [1, 2] else 0
        draw_cat_base(f, yo)
        # Happy wide mouth
        dp(f, 6, 7 + yo, (255, 120, 120, 255))
        dp(f, 7, 7 + yo, (255, 120, 120, 255))
        dp(f, 8, 7 + yo, (255, 120, 120, 255))
        dp(f, 9, 7 + yo, (255, 120, 120, 255))
        # Stars
        stars = [
            [(1, 1), (14, 2)],
            [(2, 0), (13, 1), (0, 3)],
            [(0, 2), (15, 0), (14, 4)],
            [(1, 0), (13, 3)],
        ]
        for sx, sy in stars[i]:
            dp(f, sx, sy, STAR)
        frames.append(f)
    return frames


# ═══════════════════════════════════════════════
# PIXEL ROBOTS THEME
# ═══════════════════════════════════════════════

def draw_robot_base(frame, yo=0):
    # Antenna
    dp(frame, 7, 2 + yo, ROBOT_ANTENNA)
    dp(frame, 8, 2 + yo, ROBOT_ANTENNA)
    dp(frame, 7, 3 + yo, ROBOT_DARK)
    dp(frame, 8, 3 + yo, ROBOT_DARK)
    # Head
    dr(frame, 4, 4 + yo, 8, 3, ROBOT_BODY)
    dr(frame, 5, 4 + yo, 6, 1, ROBOT_LIGHT)
    # Eyes
    dp(frame, 5, 5 + yo, ROBOT_EYE)
    dp(frame, 6, 5 + yo, ROBOT_EYE)
    dp(frame, 9, 5 + yo, ROBOT_EYE)
    dp(frame, 10, 5 + yo, ROBOT_EYE)
    # Mouth
    dp(frame, 6, 6 + yo, ROBOT_DARK)
    dp(frame, 7, 6 + yo, ROBOT_LIGHT)
    dp(frame, 8, 6 + yo, ROBOT_DARK)
    dp(frame, 9, 6 + yo, ROBOT_LIGHT)
    # Body
    dr(frame, 4, 7 + yo, 8, 4, ROBOT_BODY)
    dr(frame, 5, 8 + yo, 6, 2, ROBOT_DARK)
    # Chest light
    dp(frame, 7, 8 + yo, GREEN_GLOW)
    dp(frame, 8, 8 + yo, GREEN_GLOW)
    # Arms
    dr(frame, 3, 7 + yo, 1, 3, ROBOT_DARK)
    dr(frame, 12, 7 + yo, 1, 3, ROBOT_DARK)
    # Legs
    dr(frame, 5, 11 + yo, 2, 2, ROBOT_DARK)
    dr(frame, 9, 11 + yo, 2, 2, ROBOT_DARK)
    # Feet
    dr(frame, 4, 13 + yo, 3, 1, ROBOT_BODY)
    dr(frame, 9, 13 + yo, 3, 1, ROBOT_BODY)


def make_robot_working():
    frames = []
    for i in range(4):
        f = new_frame()
        draw_robot_base(f)
        # Spinning antenna
        ax = 6 + i
        dp(f, ax, 1, ROBOT_ANTENNA)
        # Arm pistons (typing)
        if i % 2 == 0:
            dp(f, 2, 9, ROBOT_DARK)
            dp(f, 13, 9, ROBOT_DARK)
        else:
            dp(f, 2, 8, ROBOT_DARK)
            dp(f, 13, 8, ROBOT_DARK)
        # Chest light blink
        if i % 2 == 0:
            dp(f, 7, 8, GREEN_GLOW)
            dp(f, 8, 8, GREEN_GLOW)
        else:
            dp(f, 7, 8, ROBOT_EYE)
            dp(f, 8, 8, ROBOT_EYE)
        # Data sparks
        if i == 0: dp(f, 14, 3, GREEN_GLOW)
        if i == 1: dp(f, 1, 2, GREEN_GLOW)
        if i == 2: dp(f, 15, 4, GREEN_GLOW)
        if i == 3: dp(f, 0, 3, GREEN_GLOW)
        frames.append(f)
    return frames


def make_robot_idle():
    frames = []
    for i in range(4):
        f = new_frame()
        draw_robot_base(f)
        dim_eye = (0, 150, 120, 255)
        dp(f, 5, 5, dim_eye)
        dp(f, 6, 5, dim_eye)
        dp(f, 9, 5, dim_eye)
        dp(f, 10, 5, dim_eye)
        if i in [0, 1]:
            dp(f, 7, 8, (50, 100, 50, 255))
        # Zzz
        if i >= 1: dp(f, 13, 2, (150, 150, 200, 200))
        if i >= 2: dp(f, 14, 1, (120, 120, 180, 150))
        frames.append(f)
    return frames


def make_robot_waiting():
    frames = []
    for i in range(4):
        f = new_frame()
        yo = -1 if i in [0, 2] else 0
        draw_robot_base(f, yo)
        # Flashing antenna
        if i % 2 == 0:
            dp(f, 7, 1 + yo, YELLOW_GLOW)
            dp(f, 8, 1 + yo, YELLOW_GLOW)
        # Warning eyes
        dp(f, 5, 5 + yo, YELLOW_GLOW)
        dp(f, 6, 5 + yo, YELLOW_GLOW)
        dp(f, 9, 5 + yo, YELLOW_GLOW)
        dp(f, 10, 5 + yo, YELLOW_GLOW)
        # Exclamation
        dp(f, 14, 2 + yo, YELLOW_GLOW)
        dp(f, 14, 3 + yo, YELLOW_GLOW)
        dp(f, 14, 5 + yo, YELLOW_GLOW)
        frames.append(f)
    return frames


def make_robot_done():
    frames = []
    for i in range(4):
        f = new_frame()
        yo = -1 if i in [1, 2] else 0
        draw_robot_base(f, yo)
        dp(f, 5, 5 + yo, (0, 255, 100, 255))
        dp(f, 10, 5 + yo, (0, 255, 100, 255))
        # Victory sparks
        stars = [
            [(1, 1), (14, 2)],
            [(2, 0), (13, 1), (0, 3)],
            [(0, 2), (15, 0), (14, 4)],
            [(1, 3), (14, 0), (13, 4)],
        ]
        for sx, sy in stars[i]:
            dp(f, sx, sy, STAR)
        frames.append(f)
    return frames


# ═══════════════════════════════════════════════
# SPRITE SHEET GENERATION
# ═══════════════════════════════════════════════

def frames_to_sheet(frames):
    sheet = [[T] * 64 for _ in range(16)]
    for fi, frame in enumerate(frames):
        for y in range(16):
            for x in range(16):
                sheet[y][fi * 16 + x] = frame[y][x]
    return sheet


def save_sprite(base_dir, theme, state_name, frames):
    path = os.path.join(base_dir, theme, state_name + '.png')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet = frames_to_sheet(frames)
    png_data = make_png(64, 16, sheet)
    with open(path, 'wb') as f:
        f.write(png_data)
    print(f'  {theme}/{state_name}.png ({len(png_data)} bytes)')


def main():
    base = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        'Sources', 'VibeBuddy', 'Resources', 'web', 'sprites')

    print('Generating office-human sprites...')
    save_sprite(base, 'office-human', 'working', make_office_working())
    save_sprite(base, 'office-human', 'idle', make_office_idle())
    save_sprite(base, 'office-human', 'waiting', make_office_waiting())
    save_sprite(base, 'office-human', 'done', make_office_done())

    print('Generating pixel-pets sprites...')
    save_sprite(base, 'pixel-pets', 'working', make_cat_working())
    save_sprite(base, 'pixel-pets', 'idle', make_cat_idle())
    save_sprite(base, 'pixel-pets', 'waiting', make_cat_waiting())
    save_sprite(base, 'pixel-pets', 'done', make_cat_done())

    print('Generating pixel-robots sprites...')
    save_sprite(base, 'pixel-robots', 'working', make_robot_working())
    save_sprite(base, 'pixel-robots', 'idle', make_robot_idle())
    save_sprite(base, 'pixel-robots', 'waiting', make_robot_waiting())
    save_sprite(base, 'pixel-robots', 'done', make_robot_done())

    print('Done!')


if __name__ == '__main__':
    main()
