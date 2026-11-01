extends RefCounted
## SmallWorld story data: every character, line of dialogue and quest in one place.
## Writing the story = editing this file. (When we add Russian, this is the text to translate.)
##
## TALK: what each character says. Rules are checked top to bottom; the first one whose
##   condition is true is used. Conditions:
##     "flag:name"    the story flag is set       "!flag:name"  it's not set
##     "quest:id"     the quest is active          "ready:id"    active and you have what it needs
##     "done:id"      the quest was finished       (no "if")     always
## DIALOGUE: lines are [speaker, text]. "do" runs after the last line:
##     "flag:name"    set a story flag
##     "quest:id"     start a quest                "finish:id"   hand in a quest (takes items, gives reward)
## QUESTS: "item" + "amount" is what to bring, "to" is who to bring it to.
## SMALL_TALK: what villagers say when there's nothing else to talk about, by time of day
##   (morning until 11, day until 5 PM, evening until 10 PM, then night). One line per chat.

## Everyone on the island.
##   home        which house is theirs (0 = yours, 1-4 the upper street from the left,
##               5-6 below the plaza, 7 the tavern, 8 the smithy). Shown when you walk in.
##   Standing still:  place + offset (tiles from a location's center; "tavern" = in its hall)
##   Walking about:   routine = [[hour, stop], ...] with stops "home", "work", "tavern":
##       work   {"spot": lake_road / forest_road / market / plaza / meadow, "offset", "anim"
##              (a Characters/Human folder), "wander": tiles to stroll around in}
##       seat   their stool in the tavern hall      home_spot  where they stand at home
##   hair_color tints the hair
const NPCS := {
	# Mira runs the tavern on the upper street, from behind the bar
	"mira": {"name": "Mira", "hair": "longhair", "home": 6, "place": "tavern", "offset": Vector2i(8, 3), "reach": 56.0},
	# Gus works at the anvil in the smithy yard; E opens his shop
	"gus": {"name": "Gus", "hair": "bowlhair", "home": 8, "place": "village", "offset": Vector2i(-15, 8),
		"animation": "HAMMERING", "frames": Vector2i(14, 22), "turn_to_player": false, "shop": "res://scripts/smithy_shop.gd"},
	# Old Tom fishes at the lake from dawn, and tells stories at the bar at night
	"tom": {"name": "Old Tom", "hair": "shorthair", "hair_color": Color(0.95, 0.95, 1.0), "home": 5,
		"routine": [[6.0, "home"], [6.5, "work"], [19.0, "tavern"], [23.0, "home"]],
		"work": {"spot": "lake_road", "anim": "WAITING"}, "seat": Vector2i(11, 6)},
	# Pip, Tom's grandson, runs around the plaza all day
	"pip": {"name": "Pip", "hair": "spikeyhair", "hair_color": Color(1.0, 0.9, 0.55), "home": 5, "home_spot": Vector2i(-1, -1),
		"routine": [[6.0, "home"], [8.5, "work"], [20.0, "home"]],
		"work": {"spot": "plaza", "wander": 5}},
	# Hazel: grumpy old farmer, digs in the meadow
	"hazel": {"name": "Hazel", "hair": "mophair", "hair_color": Color(0.75, 0.75, 0.8), "home": 1,
		"routine": [[6.0, "home"], [7.0, "work"], [17.0, "tavern"], [21.0, "home"]],
		"work": {"spot": "meadow", "anim": "DIG"}, "seat": Vector2i(7, 6)},
	# Bram the woodcutter, at the edge of the pines
	"bram": {"name": "Bram", "hair": "shorthair", "hair_color": Color(0.55, 0.35, 0.25), "home": 2,
		"routine": [[6.0, "home"], [8.0, "work"], [18.0, "tavern"], [23.5, "home"]],
		"work": {"spot": "forest_road", "anim": "AXE"}, "seat": Vector2i(9, 6)},
	# Lily: shy, helps out at the market
	"lily": {"name": "Lily", "hair": "curlyhair", "hair_color": Color(1.0, 0.7, 0.6), "home": 3,
		"routine": [[6.0, "home"], [9.0, "work"], [17.5, "tavern"], [21.5, "home"]],
		"work": {"spot": "market", "offset": Vector2i(5, -2)}, "seat": Vector2i(1, 10)},
	# Rosa keeps the plaza's flowers, and knows everyone's business
	"rosa": {"name": "Rosa", "hair": "longhair", "hair_color": Color(0.45, 0.3, 0.3), "home": 4,
		"routine": [[6.0, "home"], [8.0, "work"], [18.0, "tavern"], [22.0, "home"]],
		"work": {"spot": "plaza", "offset": Vector2i(-5, 2), "anim": "WATERING"}, "seat": Vector2i(3, 12)},
}

const SMALL_TALK := {
	"tom": {
		"morning": [
			"Up with the sun, like the fish. Well... like the fish used to be.",
			"Shh. You'll scare them. Fish have ears, you know. Somewhere.",
			"Forty years I've fished this lake. Never once seen the bottom.",
		],
		"day": [
			"Caught a fish with gold scales once. Threw it back. It winked at me.",
			"If you want to fish, you need patience. And a rod. Mostly a rod.",
		],
		"evening": [
			"Pull up a stool! Did I ever tell you about the fish that winked?",
			"Mira's cider is the only thing on this island older than me.",
		],
		"night": ["Off to bed with you. The lake will still be there tomorrow."],
	},
	"pip": {
		"morning": [
			"Grandpa Tom snores like a goat! A big goat!",
			"Wanna race? I'm the fastest on the whole island!",
		],
		"day": [
			"I found a shiny stone by the statue! ...No, you can't have it.",
			"Do you think the statue gets lonely at night?",
			"Tag! You're it! ...Hey, you have to chase me!",
		],
		"evening": ["I'm NOT tired. I'm just... resting my eyes."],
		"night": ["Grandpa says if I'm not in bed, the night crabs get me."],
	},
	"hazel": {
		"morning": [
			"Hmph. You're up. Good. Lazy farmers grow lazy carrots.",
			"Don't step on my rows.",
		],
		"day": [
			"This soil remembers everything. Treat it right.",
			"Water in the morning, not at noon. Does nobody teach you young ones anything?",
			"Hmph. Your field isn't... completely terrible.",
		],
		"evening": [
			"One cider. Just one. Don't tell Rosa.",
			"My knees say rain tomorrow. My knees are never wrong.",
		],
		"night": ["Go home. Sleep. Farm. That's the whole secret."],
	},
	"bram": {
		"morning": [
			"Morning! Good day for chopping. Every day is a good day for chopping.",
			"The pines grow back faster here than anywhere I've been. Strange, that.",
		],
		"day": [
			"Mind the chips! They fly further than you'd think.",
			"If you need wood, chop it yourself. Builds character. And arms.",
		],
		"evening": [
			"Nothing beats a warm fire after a day in the woods.",
			"Gus says he'll make me a better axe. He's been saying it for six years.",
		],
		"night": ["Long day. Even the trees are asleep."],
	},
	"lily": {
		"morning": [
			"Oh! H-hello. I didn't see you there.",
			"The merchant lets me arrange the vegetables. I like making them pretty.",
		],
		"day": [
			"The carrots go next to the pumpkins. Orange likes orange.",
			"I... I like your hat. Wait, you don't have a hat. Never mind.",
		],
		"evening": [
			"I don't usually come here, but Rosa insists.",
			"Mira's fire is nice. It sounds like rain.",
		],
		"night": ["G-goodnight!"],
	},
	"rosa": {
		"morning": [
			"Good morning, dear! Have you heard? No? Well, you will.",
			"These flowers won't water themselves. Well, they might. This island is odd.",
		],
		"day": [
			"Hazel pretends to be grumpy, but she leaves carrots on my doorstep.",
			"Bram has chopped half the forest and it's still all there. Curious, isn't it?",
			"Lily is sweet on someone, mark my words.",
		],
		"evening": [
			"The tavern is where you hear things, dear. Sit, sit!",
			"Did you know Mira came here on the last ship? Nobody remembers which year.",
		],
		"night": ["Off to bed! I need my beauty sleep, and so do you."],
	},
}

const TALK := {
	"mira": [
		{"if": "ready:firewood", "say": "mira_firewood_done"},
		{"if": "quest:firewood", "say": "mira_firewood_waiting"},
		{"if": "!flag:met_mira", "say": "mira_hello"},
		{"say": "mira_idle"},
	],
}

const DIALOGUE := {
	"mira_hello": {
		"lines": [
			["Mira", "Oh! A new face. We don't get many of those around here..."],
			["Mira", "I'm Mira. I run things in Willowbrook, more or less."],
			["Mira", "Nights get cold by the water. Could you bring me some firewood?"],
			["Mira", "Six logs should do. The pines up north are full of it."],
		],
		"do": ["flag:met_mira", "quest:firewood"],
	},
	"mira_firewood_waiting": {
		"lines": [
			["Mira", "Still need that firewood. Six logs, from the pines!"],
		],
	},
	"mira_firewood_done": {
		"lines": [
			["Mira", "You actually did it! That'll keep the fire going for days."],
			["Mira", "Here, take some coins. And come back soon, alright?"],
		],
		"do": ["finish:firewood"],
	},
	"mira_idle": {
		"lines": [
			["Mira", "Funny... I can't remember the last time a ship came by."],
		],
	},
}

const QUESTS := {
	"firewood": {
		"title": "Firewood",
		"goal": "Bring Mira 6 wood",
		"item": "wood",
		"amount": 6,
		"to": "mira",
		"reward": {"coins": 40},
	},
}
