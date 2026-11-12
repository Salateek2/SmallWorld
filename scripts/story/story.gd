extends Node
## SmallWorld story state (autoload singleton, reachable from any script as `Story`).
## Remembers story flags and quests, decides what characters say, and runs the
## actions at the end of a conversation. The words themselves live in story_text.gd.

signal changed ## a flag or quest changed (the HUD tracker and "!" markers listen)

const Text := preload("res://scripts/story/story_text.gd")

var flags := {} ## flag name -> true
var quests := {} ## quest id -> "active" or "done"
var friendship := {} ## npc -> friendship points (HEART points per heart)
var talked_today := {} ## npc -> true once you've chatted today
var gifted_today := {} ## npc -> true once you've given them something today
var gift_known := {} ## npc -> {item: "love" / "like" / "neutral" / "dislike"} you've found out
var clues: Array = [] ## clue ids for the journal, in the order you found them
var stamps := {} ## flag or quest id -> the day it was set / finished (for "after:" conditions)

const HEART := 100 ## friendship points per heart
const MAX_HEARTS := 10
const TALK_POINTS := 20 ## the first chat each day
const GIFT_POINTS := {"love": 80, "like": 45, "neutral": 20, "dislike": -20}
var player: Node ## set by the player; quests count and take items from them


## Forget everything (New Game).
func reset() -> void:
	flags.clear()
	quests.clear()
	friendship.clear()
	talked_today.clear()
	gifted_today.clear()
	gift_known.clear()
	clues.clear()
	stamps.clear()
	changed.emit()


func get_state() -> Dictionary:
	return {
		"flags": flags.duplicate(), "quests": quests.duplicate(),
		"friendship": friendship.duplicate(), "talked_today": talked_today.duplicate(),
		"gifted_today": gifted_today.duplicate(), "gift_known": gift_known.duplicate(true),
		"clues": clues.duplicate(), "stamps": stamps.duplicate(),
	}


func set_state(data: Dictionary) -> void:
	flags = data.get("flags", {})
	quests = data.get("quests", {})
	friendship = data.get("friendship", {})
	talked_today = data.get("talked_today", {})
	gifted_today = data.get("gifted_today", {})
	gift_known = data.get("gift_known", {})
	clues = data.get("clues", [])
	stamps = data.get("stamps", {})
	changed.emit()


# --- Friendship ----------------------------------------------------------------

## Whole hearts you have with someone (0 to MAX_HEARTS).
func hearts(npc: String) -> int:
	return int(friendship.get(npc, 0)) / HEART


## True for the villagers you can make friends with (the ones with small talk).
func can_befriend(npc: String) -> bool:
	return Text.SMALL_TALK.has(npc)


func add_friendship(npc: String, points: int) -> void:
	var before := hearts(npc)
	friendship[npc] = clampi(int(friendship.get(npc, 0)) + points, 0, HEART * MAX_HEARTS)
	if hearts(npc) > before:
		_notify("%s likes you more!  %d heart%s" % [Text.NPCS[npc]["name"], hearts(npc), "" if hearts(npc) == 1 else "s"])
	changed.emit()


## Called whenever you talk to someone: the first chat of the day makes you a bit closer.
func talk_to(npc: String) -> void:
	if can_befriend(npc) and not talked_today.has(npc):
		talked_today[npc] = true
		add_friendship(npc, TALK_POINTS)


## A new day: everyone is ready to chat and get presents again.
func new_day() -> void:
	talked_today.clear()
	gifted_today.clear()


## How someone feels about a present: "love", "like", "neutral" or "dislike".
func gift_taste(npc: String, item: String) -> String:
	var tastes: Dictionary = Text.GIFTS.get(npc, {})
	for taste in ["love", "like", "dislike"]:
		if tastes.get(taste, []).has(item):
			return taste
	return "neutral"


## Things you could give right now: [[item, how many], ...]
func giftable_items() -> Array:
	var items := []
	if player == null:
		return items
	for item in player.crops:
		if player.crops[item] > 0:
			items.append([item, player.crops[item]])
	if player.wood > 0:
		items.append(["wood", player.wood])
	return items


## Which dialogue a character uses right now (first TALK rule whose conditions all hold).
## With no rule to follow, villagers make small talk that suits the time of day.
func dialogue_for(npc_id: String) -> String:
	for rule in Text.TALK.get(npc_id, []):
		var conditions: Array = rule["if"] if rule.get("if") is Array else [rule.get("if", "")]
		if conditions.all(func(c): return c == "" or check(c)):
			return rule["say"]
	if Text.SMALL_TALK.has(npc_id):
		return "small:%s:%s" % [npc_id, _time_of_day()]
	return ""


## The lines of a dialogue: [[speaker, text], ...]. Small talk is one line, a different
## one each time you chat (and each day).
func lines_for(dialogue_key: String) -> Array:
	var parts := dialogue_key.split(":")
	if parts[0] == "gift": # "gift:lily": what have you got for me?
		var name: String = Text.NPCS[parts[1]]["name"]
		if giftable_items().is_empty():
			return [[name, "Hm? Your pockets look empty to me."]]
		return [[name, Text.GIFT_ASK.get(parts[1], "Oh? Is that for me?")]]
	if parts[0] == "give": # "give:lily:carrot": their reaction
		var taste := gift_taste(parts[1], parts[2])
		var reply: String = Text.GIFT_REPLIES.get(parts[1], {}).get(taste, Text.GIFT_REPLIES["default"][taste])
		var thing := _with_article(parts[2])
		var before := reply.substr(0, reply.find("%s")).strip_edges()
		if before == "" or before.right(1) in [".", "!", "?"]:
			thing = thing.capitalize().split(" ")[0] + thing.substr(thing.find(" ")) # start of a sentence
		return [[Text.NPCS[parts[1]]["name"], reply % thing]]
	if parts[0] != "small":
		return Text.DIALOGUE.get(dialogue_key, {}).get("lines", [])
	var choices: Array = Text.SMALL_TALK[parts[1]].get(parts[2], [])
	if choices.is_empty():
		return []
	var clock := _clock()
	var count: int = _chats.get(parts[1], 0)
	_chats[parts[1]] = count + 1
	var day: int = clock.day if clock else 0
	return [[Text.NPCS[parts[1]]["name"], choices[(count + day) % choices.size()]]]


var _chats := {} # npc -> how many times you've chatted (picks the next line)


## Answers you can pick when a dialogue's lines are done: [[text, next dialogue key, enabled], ...]
## (next "" = end the conversation). Empty = the conversation just ends.
func choices_for(dialogue_key: String) -> Array:
	var parts := dialogue_key.split(":")
	match parts[0]:
		"small":
			var gifted := gifted_today.has(parts[1])
			return [
				["Give a gift" + (" (tomorrow)" if gifted else ""), "gift:" + parts[1], not gifted],
				["Goodbye", "", true],
			]
		"gift":
			var choices := []
			for entry in giftable_items():
				choices.append(["%s  x%d" % [item_name(entry[0]), entry[1]], "give:%s:%s" % [parts[1], entry[0]], true])
			if not choices.is_empty():
				choices.append(["Never mind", "", true])
			return choices
	var choices := []
	for choice in Text.DIALOGUE.get(dialogue_key, {}).get("choices", []):
		choices.append([choice[0], choice[1], true])
	return choices


func item_name(item: String) -> String:
	return item.capitalize()


## "a carrot", "an egg", "some milk".
func _with_article(item: String) -> String:
	if item in ["milk", "wheat", "wood"]:
		return "some " + item
	return ("an " if item[0] in "aeiou" else "a ") + item


func _clock() -> Node:
	if player == null or player.get_parent() == null:
		return null
	return player.get_parent().get_node_or_null("DayNight")


## Today's day number (1 on a new game).
func today() -> int:
	var clock := _clock()
	return clock.day if clock else 1


## "morning", "day", "evening" or "night", from the game clock.
func _time_of_day() -> String:
	var clock := _clock()
	var hour: float = clock.minutes / 60.0 if clock else 12.0
	if hour < 11.0:
		return "morning"
	if hour < 17.0:
		return "day"
	if hour < 22.0:
		return "evening"
	return "night"


## True if talking to this character would start or finish a quest (shows a "!").
func has_news(npc_id: String) -> bool:
	var key := dialogue_for(npc_id)
	for action in Text.DIALOGUE.get(key, {}).get("do", []):
		if action.begins_with("quest:") or action.begins_with("finish:"):
			return true
	return false


func check(condition: String) -> bool:
	if condition.begins_with("!"):
		return not check(condition.substr(1))
	var parts := condition.split(":")
	var what := parts[0]
	var id := parts[1] if parts.size() > 1 else ""
	match what:
		"flag":
			return flags.has(id)
		"quest":
			return quests.get(id) == "active"
		"done":
			return quests.get(id) == "done"
		"ready":
			return quests.get(id) == "active" and quest_progress(id) >= Text.QUESTS[id]["amount"]
		"hearts": # "hearts:lily:2" = at least 2 hearts with Lily
			return hearts(id) >= int(parts[2])
		"day": # "day:7" = it's day 7 or later
			return today() >= int(id)
		"evening": # from 5 PM on
			return _time_of_day() in ["evening", "night"]
		"after": # "after:firewood:1" = at least 1 day since that flag was set / quest finished
			return stamps.has(id) and today() >= int(stamps[id]) + int(parts[2])
	push_warning("Unknown story condition: " + condition)
	return false


## Runs a dialogue's "do" list after the conversation ends (or when you pick an answer).
func run(dialogue_key: String) -> void:
	var key_parts := dialogue_key.split(":")
	if key_parts[0] == "give": # handing over a present
		var npc := key_parts[1]
		var item := key_parts[2]
		var taste := gift_taste(npc, item)
		take_item(item, 1)
		gifted_today[npc] = true
		if not gift_known.has(npc):
			gift_known[npc] = {}
		gift_known[npc][item] = taste
		add_friendship(npc, GIFT_POINTS[taste])
		if player:
			player.refresh_ui()
		return
	for action in Text.DIALOGUE.get(dialogue_key, {}).get("do", []):
		var parts: PackedStringArray = action.split(":")
		match parts[0]:
			"flag":
				flags[parts[1]] = true
				stamps[parts[1]] = today()
			"quest":
				quests[parts[1]] = "active"
				_notify("New quest: " + Text.QUESTS[parts[1]]["title"])
			"finish":
				_finish_quest(parts[1])
			"friend": # "friend:lily:30" = 30 friendship points
				add_friendship(parts[1], int(parts[2]))
			"tool": # "tool:hoe" = hand the player a tool
				if player:
					player.give_tool(player.Tool[parts[1].to_upper()])
					_notify("You got the %s!" % player.TOOL_NAMES[player.Tool[parts[1].to_upper()]].to_lower())
			"seeds": # "seeds:carrot:6"
				if player:
					player.seeds[parts[1]] = player.seeds.get(parts[1], 0) + int(parts[2])
					player.refresh_ui()
			"coins": # "coins:50"
				if player:
					player.coins += int(parts[1])
					player.refresh_ui()
			"clue": # "clue:locket" = a new page in the journal
				if not clues.has(parts[1]):
					clues.append(parts[1])
					_notify("New clue in your journal (J): " + Text.CLUES[parts[1]]["title"])
			"chapter": # "chapter:1" = the chapter is over: a big banner
				if player and player.has_method("show_big_message"):
					player.show_big_message(Text.CHAPTERS[parts[1]])
			_:
				push_warning("Unknown story action: " + action)
	changed.emit()


# --- Quests ------------------------------------------------------------------

## The quest shown in the tracker (the first active one), or "".
func current_quest() -> String:
	for id in quests:
		if quests[id] == "active":
			return id
	return ""


## How far along a quest is (capped at the amount needed): items you have for "item"
## quests, villagers you're friends with (1+ heart) for "friends", hearts for "hearts_with",
## crops planted and watered for "growing".
func quest_progress(id: String) -> int:
	var quest: Dictionary = Text.QUESTS[id]
	var have := 0
	if quest.has("item"):
		have = item_count(quest["item"])
	elif quest.has("friends"):
		for npc in Text.SMALL_TALK:
			if npc != quest.get("not", "") and hearts(npc) >= 1:
				have += 1
	elif quest.has("hearts_with"):
		have = hearts(quest["hearts_with"])
	elif quest.has("growing"): # crops planted and watered
		var farm: Node = player.get_parent().get_node_or_null("Farm") if player else null
		have = farm.count_growing() if farm else 0
	return mini(have, quest.get("amount", 0))


## e.g. "Bring Isla 6 wood (2/6)" (just the goal for quests with nothing to count)
func quest_goal_text(id: String) -> String:
	var quest: Dictionary = Text.QUESTS[id]
	if quest.get("amount", 0) == 0:
		return quest["goal"]
	return "%s (%d/%d)" % [quest["goal"], quest_progress(id), quest["amount"]]


func _finish_quest(id: String) -> void:
	var quest: Dictionary = Text.QUESTS[id]
	stamps[id] = today()
	if quest.has("item") and quests.get(id) == "active":
		take_item(quest["item"], quest["amount"])
	var reward: Dictionary = quest.get("reward", {})
	if player and reward.has("coins"):
		player.coins += reward["coins"]
	quests[id] = "done"
	if player:
		player.refresh_ui()
	var coins: int = reward.get("coins", 0)
	_notify("Quest complete: %s%s" % [quest["title"], "  +%d coins" % coins if coins > 0 else ""])


func _notify(text: String) -> void:
	if player and player.has_method("notify"):
		player.notify(text)


# --- Player's items ----------------------------------------------------------

func item_count(item: String) -> int:
	if player == null:
		return 0
	if item == "wood":
		return player.wood
	return player.crops.get(item, 0)


func take_item(item: String, amount: int) -> void:
	if player == null:
		return
	if item == "wood":
		player.wood -= amount
	else:
		player.crops[item] = player.crops.get(item, 0) - amount
		if player.crops[item] <= 0:
			player.crops.erase(item)
