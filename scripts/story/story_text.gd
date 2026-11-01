extends RefCounted
## SmallWorld story data: every character, line of dialogue and quest in one place.
## Writing the story = editing this file. (When we add Russian, this is the text to translate.)
##
## TALK: what each character says. Rules are checked top to bottom; the first one whose
##   condition is true is used ("if" can also be a list: all must be true). Conditions:
##     "flag:name"    the story flag is set       "!flag:name"  it's not set
##     "quest:id"     the quest is active          "ready:id"    active and you have what it needs
##     "done:id"      the quest was finished       (no "if")     always
##     "hearts:npc:2" at least 2 hearts with them
## DIALOGUE: lines are [speaker, text]. "do" runs after the last line:
##     "flag:name"    set a story flag
##     "quest:id"     start a quest                "finish:id"   hand in a quest (takes items, gives reward)
##     "friend:npc:30"  30 friendship points (negative takes some away)
##   "choices": [[answer, next dialogue], ...] lets you pick what to say after the last line
##   (next "" = end the conversation).
## FRIENDSHIP: chatting once a day and gifts (one a day) fill hearts with villagers; see GIFTS.
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
##       seat   where they sit in the tavern hall (seat_face: 1 = facing right, -1 = left;
##              sit_lift: how far up their seat is, a stool by default)
##       home_spot  where they stand at home
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
		"work": {"spot": "forest_road", "anim": "AXE"}, "seat": Vector2i(9, 6), "seat_face": -1.0},
	# Lily: shy, helps out at the market
	"lily": {"name": "Lily", "hair": "curlyhair", "hair_color": Color(1.0, 0.7, 0.6), "home": 3,
		"routine": [[6.0, "home"], [9.0, "work"], [17.5, "tavern"], [21.5, "home"]],
		"work": {"spot": "market", "offset": Vector2i(5, -2)}, "seat": Vector2i(1, 10), "sit_lift": -2.0},
	# Rosa keeps the plaza's flowers, and knows everyone's business
	"rosa": {"name": "Rosa", "hair": "longhair", "hair_color": Color(0.45, 0.3, 0.3), "home": 4,
		"routine": [[6.0, "home"], [8.0, "work"], [18.0, "tavern"], [22.0, "home"]],
		"work": {"spot": "plaza", "offset": Vector2i(-5, 2), "anim": "WATERING"}, "seat": Vector2i(3, 12), "sit_lift": -6.0},
}

## A line about each person for the People tab of the inventory.
const ABOUT := {
	"mira": "Runs the tavern on the upper street. Seems to know everyone.",
	"gus": "The blacksmith. Hammers away at his anvil all day. Sells tools.",
	"tom": "Fishes where the road meets the lake. Full of stories.",
	"pip": "Tom's grandson. Fastest runner on the island (he says).",
	"hazel": "Grumpy old farmer. Digs in the meadow from dawn.",
	"bram": "Woodcutter at the edge of the pines. Always cheerful.",
	"lily": "Shy. Helps out at the market and likes pretty things.",
	"rosa": "Waters the plaza's flowers and knows everyone's business.",
}

## Presents: what each villager loves, likes and can't stand (everything else is fine).
## Items: carrot, wheat, potato, cabbage, sunflower, pumpkin, fish, egg, milk, wood.
const GIFTS := {
	"tom": {"love": ["fish"], "like": ["egg", "potato"], "dislike": ["sunflower"]},
	"pip": {"love": ["sunflower", "pumpkin"], "like": ["carrot", "egg"], "dislike": ["cabbage"]},
	"hazel": {"love": ["carrot", "milk"], "like": ["potato", "wheat"], "dislike": ["fish"]},
	"bram": {"love": ["egg"], "like": ["potato", "wheat", "milk"], "dislike": ["wood"]},
	"lily": {"love": ["sunflower"], "like": ["cabbage", "carrot"], "dislike": ["fish"]},
	"rosa": {"love": ["pumpkin", "milk"], "like": ["egg", "wheat"], "dislike": ["wood"]},
}

## What they say when you offer a present (before you pick one)
const GIFT_ASK := {
	"tom": "A present for an old man? Let's see it.",
	"pip": "Ooh! Is it a present? Is it? IS IT?",
	"hazel": "Hmph. What is it?",
	"bram": "For me? You shouldn't have! ...What is it?",
	"lily": "F-for me? Oh... you didn't have to...",
	"rosa": "A gift! Oh, you're a dear. Let me see!",
}

## How they react, by taste ("%s" = the item). Missing ones use "default".
const GIFT_REPLIES := {
	"default": {
		"love": "Oh, a %s! I love these. Thank you!",
		"like": "A %s, how nice. Thank you.",
		"neutral": "A %s? Thanks.",
		"dislike": "...A %s. Well. Thank you, I suppose.",
	},
	"tom": {
		"love": "A %s! Fresh as morning. You've made an old fisherman very happy.",
		"dislike": "A %s? What would I do with this... smell it?",
	},
	"pip": {
		"love": "WOW! A %s! This is the best day EVER!",
		"dislike": "Eww, a %s! ...Grandpa says I have to say thank you. Thank you.",
	},
	"hazel": {
		"love": "...A %s. A good one, too. Hmph. Thank you.",
		"like": "A %s. Grown right, by the look of it.",
		"dislike": "A %s?! Get that thing away from my garden.",
	},
	"bram": {
		"love": "A %s! That's breakfast sorted. You're a good friend!",
		"dislike": "Ha! A %s! I've got about a thousand of those.",
	},
	"lily": {
		"love": "A %s... it's beautiful. I'll keep it by my window.",
		"dislike": "Oh... a %s. It's, um... very... fishy.",
	},
	"rosa": {
		"love": "A %s! Oh, wait until I tell everyone what you gave me!",
		"dislike": "A %s, dear? How... rustic.",
	},
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
	# Heart events: something personal once you're friends (each happens once)
	"tom": [{"if": ["hearts:tom:2", "!flag:tom_h2"], "say": "tom_h2"}],
	"pip": [{"if": ["hearts:pip:2", "!flag:pip_h2"], "say": "pip_h2"}],
	"hazel": [{"if": ["hearts:hazel:2", "!flag:hazel_h2"], "say": "hazel_h2"}],
	"bram": [{"if": ["hearts:bram:2", "!flag:bram_h2"], "say": "bram_h2"}],
	"lily": [{"if": ["hearts:lily:2", "!flag:lily_h2"], "say": "lily_h2"}],
	"rosa": [{"if": ["hearts:rosa:2", "!flag:rosa_h2"], "say": "rosa_h2"}],
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
	# --- Heart events (2 hearts) ---
	"tom_h2": {
		"lines": [
			["Old Tom", "You know, you remind me of someone. Came here on a boat, just like you."],
			["Old Tom", "Funny thing is... I can't remember the boat ever leaving."],
		],
		"choices": [["Maybe it never left?", "tom_h2_a"], ["Do you want to leave?", "tom_h2_b"]],
		"do": ["flag:tom_h2"],
	},
	"tom_h2_a": {"lines": [["Old Tom", "Ha! Maybe it's at the bottom of the lake, with my patience."]], "do": ["friend:tom:20"]},
	"tom_h2_b": {
		"lines": [["Old Tom", "Leave? ...I've never once thought about it. Isn't that strange? Never once."]],
		"do": ["friend:tom:30", "flag:tom_never_left"],
	},
	"pip_h2": {
		"lines": [
			["Pip", "Wanna know a secret? The statue MOVES at night."],
			["Pip", "I put a pebble by its foot, and in the morning it was on the other side!"],
		],
		"choices": [["I believe you!", "pip_h2_a"], ["Someone moved the pebble.", "pip_h2_b"]],
		"do": ["flag:pip_h2"],
	},
	"pip_h2_a": {"lines": [["Pip", "Really?! You're the best! Don't tell Grandpa, he'll say I'm silly."]], "do": ["friend:pip:30"]},
	"pip_h2_b": {"lines": [["Pip", "Nuh-uh! ...Maybe. But what if nobody did?"]], "do": ["friend:pip:5"]},
	"hazel_h2": {
		"lines": [
			["Hazel", "Hmph. You keep at it. Most don't."],
			["Hazel", "My husband planted the first carrots on this island. Or... I think he did."],
			["Hazel", "Funny. I can't picture his face anymore."],
		],
		"choices": [["That must be hard.", "hazel_h2_a"], ["Maybe write it all down?", "hazel_h2_b"]],
		"do": ["flag:hazel_h2"],
	},
	"hazel_h2_a": {"lines": [["Hazel", "It is. ...Thank you for saying so. Now go water something."]], "do": ["friend:hazel:30"]},
	"hazel_h2_b": {
		"lines": [["Hazel", "Write it down... Not a bad idea, youngster. Not bad at all."]],
		"do": ["friend:hazel:20", "flag:hazel_journal"],
	},
	"bram_h2": {
		"lines": [
			["Bram", "Can I tell you something odd? I cut a notch in every stump I leave."],
			["Bram", "Next morning, the trees are back. Notch and all."],
		],
		"choices": [["That's amazing!", "bram_h2_a"], ["That's... creepy.", "bram_h2_b"]],
		"do": ["flag:bram_h2"],
	},
	"bram_h2_a": {"lines": [["Bram", "Magic or curse, it keeps me in work! Ha!"]], "do": ["friend:bram:20"]},
	"bram_h2_b": {"lines": [["Bram", "Aye. I try not to think about it. Chopping helps."]], "do": ["friend:bram:25"]},
	"lily_h2": {
		"lines": [
			["Lily", "I... I drew a map of the island. But I don't know what's past the edge."],
			["Lily", "Do you?"],
		],
		"choices": [["Let's find out together.", "lily_h2_a"], ["Nothing, probably.", "lily_h2_b"]],
		"do": ["flag:lily_h2"],
	},
	"lily_h2_a": {"lines": [["Lily", "T-together? ...I'd like that. Very much."]], "do": ["friend:lily:40", "flag:lily_together"]},
	"lily_h2_b": {"lines": [["Lily", "Oh. Yes. Probably nothing..."]], "do": ["friend:lily:5"]},
	"rosa_h2": {
		"lines": [
			["Rosa", "Between you and me, dear: nobody here remembers their birthday."],
			["Rosa", "I asked everyone. Not one!"],
		],
		"choices": [["When's yours?", "rosa_h2_a"], ["That's just gossip.", "rosa_h2_b"]],
		"do": ["flag:rosa_h2"],
	},
	"rosa_h2_a": {"lines": [["Rosa", "Mine? It's... oh. Oh my."]], "do": ["friend:rosa:30", "flag:rosa_birthday"]},
	"rosa_h2_b": {"lines": [["Rosa", "Gossip is just the truth wearing a nice hat, dear."]], "do": ["friend:rosa:15"]},
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
