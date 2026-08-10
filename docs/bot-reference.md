# MiniDruidMana - bot reference

Version 1.4.3. Interface versions: 120100, 120007, 120005, 50504, 40402,
38002, 38000, 30405, 20506, 11509 (retail plus the classic client lines).
Saved variables: MiniDruidManaDB (account-wide).

## What it does

For druids only: shows a small extra mana bar attached below the default
player frame's power bar while you are in a form whose power is not mana
(cat, bear, moonkin, etc.), so you can watch your mana while shapeshifted.
Useful for stealth drinking, deciding whether you can shift out to heal, and
classic powershifting.

## How it works

- Loads only if the character is a druid (class check at login); on any other
  class the addon registers nothing.
- The bar shows whenever UnitPowerType("player") is not mana and hides when
  your primary power is mana (caster form / Restoration).
- Anchored below the default PlayerFrame mana bar (handles both the classic
  and retail frame layouts, with a generic fallback position on unknown
  layouts). Only the default Blizzard player frame is supported.
- Bar fill is your current mana out of max mana.
- On retail layouts the addon also nudges the container that holds combo
  points down 5 pixels so the bar does not overlap it.
- Updates on power changes, shapeshift form changes, and entering world.

## Settings

Open with a slash command or Options -> AddOns -> MiniDruidMana.

| Setting | Type | Default | Effect |
|---|---|---|---|
| Show text | checkbox | off | Shows mana percentage on the left of the bar and abbreviated mana value on the right. |

## Slash commands

/minidruidmana, /minidm, /mdm - all open the settings panel.

## Troubleshooting

- "No bar appears": the bar only exists for druids, and only shows while your
  current power type is not mana. In caster or Restoration form it hides.
- "I use ElvUI / another unit frame addon": the bar anchors to the default
  Blizzard PlayerFrame; if that frame is hidden or replaced the bar will not
  be visible where expected.
- "I want numbers on the bar": turn on "Show text" in the settings.
