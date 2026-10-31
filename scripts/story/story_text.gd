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

## Characters who walk the island. place = a location from map_generator, offset in tiles from its center.
const NPCS := {
	"mira": {"name": "Mira", "hair": "longhair", "place": "village", "offset": Vector2i(4, -2)},
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
