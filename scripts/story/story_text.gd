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
##     "day:7"        day 7 or later              "evening"     5 PM or later
##     "after:id:1"   at least 1 day since that flag was set / that quest was finished
## DIALOGUE: lines are [speaker, text]. "do" runs after the last line:
##     "flag:name"    set a story flag
##     "quest:id"     start a quest                "finish:id"   hand in a quest (takes items, gives reward)
##     "friend:npc:30"  30 friendship points (negative takes some away)
##     "tool:hoe"     give a tool (axe, hoe, seeds, water, sword, rod)
##     "seeds:carrot:6"  give seeds              "coins:50"    give coins
##     "clue:id"      add a clue to the journal (CLUES)
##     "chapter:1"    the big "chapter complete" banner (CHAPTERS)
##   "choices": [[answer, next dialogue], ...] lets you pick what to say after the last line
##   (next "" = end the conversation).
## FRIENDSHIP: chatting once a day and gifts (one a day) fill hearts with villagers; see GIFTS.
## QUESTS: "item" + "amount" is what to bring, "to" is who to bring it to.
##   Or "friends" (befriend "amount" villagers, 1 heart each), or "hearts_with": npc
##   (reach "amount" hearts with them), or just a "goal" to read (finished by a dialogue).
##
## PACING: the story is meant to take many days. Steps wait for the next day ("after:"),
## for crops to grow, for friendships to grow, and for evenings, so there's always time
## to farm in between. One story step a day is plenty.
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
	# Isla runs the tavern on the upper street, from behind the bar. Charming, sharp,
	# and always angling for presents. Came on "the last ship", and nobody knows when.
	"isla": {"name": "Isla", "hair": "longhair", "home": 6, "place": "tavern", "offset": Vector2i(8, 3), "reach": 56.0},
	# Gus works at the anvil in the smithy yard; E opens his shop
	"gus": {"name": "Gus", "hair": "bowlhair", "home": 8, "place": "village", "offset": Vector2i(-15, 8),
		"animation": "HAMMERING", "frames": Vector2i(14, 22), "turn_to_player": false, "shop": "res://scripts/smithy_shop.gd"},
	# Old Tom fishes at the lake from dawn, and tells stories at the bar at night
	"tom": {"name": "Old Tom", "hair": "shorthair", "hair_color": Color(0.95, 0.95, 1.0), "home": 5,
		"routine": [[6.0, "work"], [19.0, "tavern"], [23.0, "home"]],
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
	"isla": "Runs the tavern on the upper street. Charming, sharp, and very fond of presents.",
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
	"isla": {"love": ["milk", "pumpkin"], "like": ["egg", "sunflower", "fish"], "dislike": ["wood", "wheat"]},
	"tom": {"love": ["fish"], "like": ["egg", "potato"], "dislike": ["sunflower"]},
	"pip": {"love": ["sunflower", "pumpkin"], "like": ["carrot", "egg"], "dislike": ["cabbage"]},
	"hazel": {"love": ["carrot", "milk"], "like": ["potato", "wheat"], "dislike": ["fish"]},
	"bram": {"love": ["egg"], "like": ["potato", "wheat", "milk"], "dislike": ["wood"]},
	"lily": {"love": ["sunflower"], "like": ["cabbage", "carrot"], "dislike": ["fish"]},
	"rosa": {"love": ["pumpkin", "milk"], "like": ["egg", "wheat"], "dislike": ["wood"]},
}

## What they say when you offer a present (before you pick one)
const GIFT_ASK := {
	"isla": "A present? For me? Oh, you shouldn't have. ...Well, go on, hand it over.",
	"tom": "A present for an old man? Let's see it.",
	"pip": "Ooh! Is it a present? Is it? IS IT?",
	"hazel": "Hmph. What is it?",
	"bram": "For me? You shouldn't have! ...What is it?",
	"lily": "F-for me? Oh... you didn't have to...",
	"rosa": "A gift! Oh, you're a dear. Let me see!",
}

## How they react, by taste ("%s" = the item with "a" / "an" / "some", e.g. "an egg").
## Missing ones use "default".
const GIFT_REPLIES := {
	"isla": {
		"love": "%s! Oh, you DO know the way to my heart. And to my wallet.",
		"like": "%s! Lovely. Not the BEST present, but lovely.",
		"neutral": "%s. I'll find a use for it. ...Probably sell it.",
		"dislike": "%s? Darling, I run a tavern, not a junk shop.",
	},
	"default": {
		"love": "Oh, %s! I love these. Thank you!",
		"like": "%s, how nice. Thank you.",
		"neutral": "%s? Thanks.",
		"dislike": "...%s. Well. Thank you, I suppose.",
	},
	"tom": {
		"love": "%s! Fresh as morning. You've made an old fisherman very happy.",
		"dislike": "%s? What would I do with this... smell it?",
	},
	"pip": {
		"love": "WOW! %s! This is the best day EVER!",
		"dislike": "Eww, %s! ...Grandpa says I have to say thank you. Thank you.",
	},
	"hazel": {
		"love": "...%s. A good one, too. Hmph. Thank you.",
		"like": "%s. Grown right, by the look of it.",
		"dislike": "%s?! Get that thing away from my garden.",
	},
	"bram": {
		"love": "%s! That's breakfast sorted. You're a good friend!",
		"dislike": "Ha! %s! I've got about a thousand of those.",
	},
	"lily": {
		"love": "%s... it's beautiful. I'll keep it by my window.",
		"dislike": "Oh... %s. It's, um... very... fishy.",
	},
	"rosa": {
		"love": "%s! Oh, wait until I tell everyone what you gave me!",
		"dislike": "%s, dear? How... rustic.",
	},
}

const SMALL_TALK := {
	"isla": {
		"morning": [
			"Morning, sunshine! The tavern opens at five. Bring coins. Or presents. Presents are nice.",
			"Did you know a pumpkin is worth more than a smile? I checked.",
			"Funny... I can't remember the last time a ship came by.",
		],
		"day": [
			"Friendship is lovely. Friendship with presents is lovelier.",
			"If you find anything shiny, it's mine. Finders keepers is a tavern rule.",
			"Didn't bring me anything today? I'll pretend I didn't notice. ...I noticed.",
		],
		"evening": [
			"What'll it be? Cider's on the house. The house being you. Five coins.",
			"Everyone here tips me in gossip. You could tip me in milk.",
			"Sit, stay a while! Lonely customers buy more cider. Science.",
		],
		"night": [
			"Closing time! Unless you brought a present. Then it's opening time.",
			"Off you go, darling. Dream of me. And of paying your tab.",
		],
	},
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
			"Isla's cider is the only thing on this island older than me.",
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
			"Isla's fire is nice. It sounds like rain.",
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
			"Did you know Isla came here on the last ship? Nobody remembers which year.",
		],
		"night": ["Off to bed! I need my beauty sleep, and so do you."],
	},
}

const TALK := {
	# Heart events: something personal once you're friends (each happens once)
	"tom": [
		{"if": "quest:wake", "say": "tom_hello"},
		{"if": ["hearts:tom:2", "!flag:tom_h2"], "say": "tom_h2"},
	],
	"pip": [{"if": ["hearts:pip:2", "!flag:pip_h2"], "say": "pip_h2"}],
	"hazel": [
		{"if": "quest:see_hazel", "say": "hazel_seeds"},
		{"if": ["hearts:hazel:2", "!flag:hazel_h2"], "say": "hazel_h2"},
	],
	"bram": [{"if": ["hearts:bram:2", "!flag:bram_h2"], "say": "bram_h2"}],
	"lily": [{"if": ["hearts:lily:2", "!flag:lily_h2"], "say": "lily_h2"}],
	"rosa": [
		{"if": ["quest:neighbours", "evening", "!flag:rosa_ship"], "say": "rosa_ship"},
		{"if": ["hearts:rosa:2", "!flag:rosa_h2"], "say": "rosa_h2"},
	],
	# Chapter 1 runs through Isla: each step she gives you the next one
	"isla": [
		{"if": "quest:find_isla", "say": "isla_hello"},
		{"if": "!flag:met_isla", "say": "isla_hello"},
		{"if": "ready:firewood", "say": "isla_firewood_done"},
		{"if": "quest:firewood", "say": "isla_firewood_waiting"},
		{"if": ["quest:patience", "after:firewood:1"], "say": "isla_roots"},
		{"if": "quest:patience", "say": "isla_too_soon"},
		{"if": "quest:see_hazel", "say": "isla_go_hazel"},
		{"if": "ready:first_harvest", "say": "isla_harvest_done"},
		{"if": "quest:first_harvest", "say": "isla_harvest_waiting"},
		{"if": "ready:neighbours", "say": "isla_neighbours_done"},
		{"if": ["hearts:isla:2", "!flag:isla_h2"], "say": "isla_h2"},
		{"if": ["ready:isla_trust", "evening"], "say": "isla_locket"},
		{"if": "ready:isla_trust", "say": "isla_tonight"},
	],
}

const DIALOGUE := {
	# --- Intro and chapter 1: "A New Home" ---
	"intro": {"lines": [], "do": ["clue:locket", "quest:wake"]},
	"tom_hello": {
		"lines": [
			["Old Tom", "Easy now, easy. You were lying in the reeds like a lost boot."],
			["Old Tom", "Well I'll be... a new face. Haven't seen one of those since... huh. Since I can't remember."],
			["Old Tom", "That's a pretty locket you're holding. Never seen that mark before. Or have I...?"],
			["Old Tom", "Here, take my spare rod. A body needs to eat."],
			["Old Tom", "Now go see Isla at the tavern, up on the upper street. She'll sort you out. For a price."],
		],
		"do": ["finish:wake", "flag:met_tom", "tool:rod", "quest:find_isla"],
	},
	"isla_hello": {
		"lines": [
			["Isla", "Oh! A new face. And new faces come with new pockets..."],
			["Isla", "I'm Isla. I run the tavern. And, between you and me, most of Willowbrook."],
			["Isla", "Washed up by the lake, hm? Well, you can't sleep in my tavern for free, darling."],
			["Isla", "There's an empty farmhouse west of the village. Nobody's lived there for years. It's yours. Rent-free... for now."],
			["Isla", "Start by bringing me some firewood. Six logs, from the pines up north. There's coin in it for you."],
		],
		"do": ["finish:find_isla", "flag:met_isla", "quest:firewood"],
	},
	"isla_firewood_waiting": {
		"lines": [
			["Isla", "No firewood yet? A girl could freeze, darling. Six logs, from the pines!"],
		],
	},
	"isla_firewood_done": {
		"lines": [
			["Isla", "My hero! Well... my firewood hero. That'll keep the fire going for days."],
			["Isla", "Here's your pay. Don't spend it all in one tavern. ...Actually, do. Mine."],
			["Isla", "Come back tomorrow. I might have more work for you. I usually do."],
		],
		"do": ["finish:firewood", "quest:patience"],
	},
	"isla_too_soon": {"lines": [["Isla", "Tomorrow, darling. Patience is a virtue. So is paying rent."]]},
	"isla_roots": {
		"lines": [
			["Isla", "There you are! Now. A farmhouse without a farm is just a house."],
			["Isla", "Go see Hazel. She digs in the meadow past your farm every day. Knows dirt better than anyone."],
			["Isla", "Grow me something nice and I'll buy it. At a fair price. Fair for me."],
		],
		"do": ["finish:patience", "quest:see_hazel"],
	},
	"isla_go_hazel": {"lines": [["Isla", "Hazel's in the meadow, darling. Follow the road past your farm."]]},
	"hazel_seeds": {
		"lines": [
			["Hazel", "Hmph. Isla sent you, didn't she. Everyone wants something."],
			["Hazel", "Fine. Take my old hoe and watering can. I've got better ones."],
			["Hazel", "And these seeds. Found a whole sack of them on my doorstep, years ago."],
			["Hazel", "Never figured out who left it. They grow like nothing else on this island."],
			["Hazel", "Dig, plant, water every day. Three nights and you'll have carrots. Don't drown them."],
		],
		"do": ["finish:see_hazel", "tool:hoe", "tool:water", "tool:seeds", "seeds:carrot:6", "clue:seeds", "quest:first_harvest"],
	},
	"isla_harvest_waiting": {
		"lines": [["Isla", "Carrots, darling. Three of them. I'm not getting any younger. ...Or older, come to think of it."]],
	},
	"isla_harvest_done": {
		"lines": [
			["Isla", "Ooh, look at these! Crunchy. Orange. Profitable."],
			["Isla", "Here's your pay. Don't look at me like that, it's a VERY fair price."],
			["Isla", "A word of advice: people here are friendly, but they don't open up to strangers."],
			["Isla", "Chat with them every day. Bring little presents. You'll see."],
		],
		"do": ["finish:first_harvest", "quest:neighbours"],
	},
	"isla_neighbours_done": {
		"lines": [
			["Isla", "Look at you, the most popular face in Willowbrook! Well. Second most."],
			["Isla", "Everyone's talking about you. Rosa especially. Rosa always especially."],
			["Isla", "...You know, you could come by the tavern more often. For the cider. Obviously."],
		],
		"do": ["finish:neighbours", "quest:isla_trust"],
	},
	"isla_tonight": {"lines": [["Isla", "Come by the tavern tonight, darling. I'll save you a seat."]]},
	"isla_locket": {
		"lines": [
			["Isla", "There you are. Sit, sit. First cider's on the house. The second one is five coins."],
			["Isla", "...Wait. What's that around your neck?"],
			["Isla", "That mark. Where did you get that?"],
		],
		"choices": [["I woke up holding it.", "isla_locket_a"], ["Why? Do you know it?", "isla_locket_b"]],
		"do": ["finish:isla_trust"],
	},
	"isla_locket_a": {
		"lines": [
			["Isla", "You woke up... holding it."],
			["Isla", "...Never mind. It's nothing. It's late. And that cider is ten coins, by the way."],
		],
		"do": ["clue:isla_locket", "flag:ch1_done", "chapter:1"],
	},
	"isla_locket_b": {
		"lines": [
			["Isla", "Me? No! No. Of course not. Never seen it before in my life."],
			["Isla", "...Drink your cider. It's ten coins now. Inflation."],
		],
		"do": ["clue:isla_locket", "flag:ch1_done", "chapter:1"],
	},
	"rosa_ship": {
		"lines": [
			["Rosa", "Psst, dear. Come here. You've been spending time with Isla, haven't you?"],
			["Rosa", "Did you know she came here on the last ship? Nobody remembers which year. Not even her."],
			["Rosa", "And nobody remembers that ship ever leaving, either. Isn't that funny?"],
		],
		"do": ["flag:rosa_ship", "clue:last_ship", "friend:rosa:10"],
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
	"isla_h2": {
		"lines": [
			["Isla", "You keep coming back here, you know."],
			["Isla", "Is it the cider... or is it me?"],
		],
		"choices": [["It's definitely you.", "isla_h2_a"], ["It's the cider.", "isla_h2_b"]],
		"do": ["flag:isla_h2"],
	},
	"isla_h2_a": {
		"lines": [["Isla", "Ha! Smooth. That'll be five coins. ...I'm joking. Mostly."]],
		"do": ["friend:isla:30", "flag:isla_flirt"],
	},
	"isla_h2_b": {"lines": [["Isla", "Honest! I like that. Still five coins, though."]], "do": ["friend:isla:15"]},
}

const QUESTS := {
	# Chapter 1: "A New Home"
	"wake": {"title": "Washed Ashore", "goal": "Talk to the old fisherman by the lake"},
	"find_isla": {"title": "A Roof Overhead", "goal": "Find Isla at the tavern on the upper street"},
	"firewood": {
		"title": "Firewood",
		"goal": "Bring Isla 6 wood",
		"item": "wood",
		"amount": 6,
		"to": "isla",
		"reward": {"coins": 40},
	},
	"patience": {"title": "Patience", "goal": "Visit Isla again tomorrow"},
	"see_hazel": {"title": "Roots", "goal": "Ask Hazel about farming (in the meadow)"},
	"first_harvest": {
		"title": "First Harvest",
		"goal": "Grow 3 carrots for Isla",
		"item": "carrot",
		"amount": 3,
		"to": "isla",
		"reward": {"coins": 60},
	},
	"neighbours": {
		"title": "New Neighbours",
		"goal": "Make friends with 4 villagers",
		"friends": true,
		"not": "isla",
		"amount": 4,
	},
	"isla_trust": {
		"title": "The Tavern Keeper",
		"goal": "Hearts with Isla",
		"hearts_with": "isla",
		"amount": 3,
	},
}

## Clues for the journal (the "Clues" tab of the inventory).
const CLUES := {
	"locket": {"title": "The Locket", "text": "You woke up by the lake holding it. It has a strange mark that glows faintly in the dark."},
	"seeds": {"title": "Hazel's Seeds", "text": "Someone left a sack of seeds on Hazel's doorstep years ago. Nobody knows who. They grow like nothing else on the island."},
	"last_ship": {"title": "The Last Ship", "text": "Rosa says Isla came on the last ship to reach the island. Nobody remembers when. Or the ship ever leaving."},
	"isla_locket": {"title": "Isla Knows Something", "text": "Isla went pale when she saw your locket. She says she's never seen the mark before. She's lying."},
}

## The big banner at the end of each chapter.
const CHAPTERS := {
	"1": "Chapter 1 complete\nThe Locket\n\nTo be continued...",
}

## The intro on New Game: lines of white text on black, one after another.
const INTRO := [
	"A storm.",
	"A boat, tossed like a leaf.",
	"A light, somewhere in the fog...",
	"...and then nothing at all.",
]
