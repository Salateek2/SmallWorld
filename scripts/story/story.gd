extends Node
## SmallWorld story state (autoload singleton, reachable from any script as `Story`).
## Remembers story flags and quests, decides what characters say, and runs the
## actions at the end of a conversation. The words themselves live in story_text.gd.

signal changed ## a flag or quest changed (the HUD tracker and "!" markers listen)

const Text := preload("res://scripts/story/story_text.gd")

var flags := {} ## flag name -> true
var quests := {} ## quest id -> "active" or "done"
var player: Node ## set by the player; quests count and take items from them


## Which dialogue a character uses right now (first TALK rule whose condition holds).
func dialogue_for(npc_id: String) -> String:
	for rule in Text.TALK.get(npc_id, []):
		if not rule.has("if") or check(rule["if"]):
			return rule["say"]
	return ""


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
	var id := parts[1]
	match what:
		"flag":
			return flags.has(id)
		"quest":
			return quests.get(id) == "active"
		"done":
			return quests.get(id) == "done"
		"ready":
			return quests.get(id) == "active" and quest_progress(id) >= Text.QUESTS[id]["amount"]
	push_warning("Unknown story condition: " + condition)
	return false


## Runs a dialogue's "do" list after the conversation ends.
func run(dialogue_key: String) -> void:
	for action in Text.DIALOGUE.get(dialogue_key, {}).get("do", []):
		var parts: PackedStringArray = action.split(":")
		match parts[0]:
			"flag":
				flags[parts[1]] = true
			"quest":
				quests[parts[1]] = "active"
				_notify("New quest: " + Text.QUESTS[parts[1]]["title"])
			"finish":
				_finish_quest(parts[1])
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


## How many of the needed items the player has (capped at the amount needed).
func quest_progress(id: String) -> int:
	var quest: Dictionary = Text.QUESTS[id]
	return mini(item_count(quest["item"]), quest["amount"])


## e.g. "Bring Mira 6 wood (2/6)"
func quest_goal_text(id: String) -> String:
	var quest: Dictionary = Text.QUESTS[id]
	return "%s (%d/%d)" % [quest["goal"], quest_progress(id), quest["amount"]]


func _finish_quest(id: String) -> void:
	var quest: Dictionary = Text.QUESTS[id]
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
