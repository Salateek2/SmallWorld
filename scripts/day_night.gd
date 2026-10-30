extends Node
## SmallWorld clock: days run from 6:00 AM to 2:00 AM.
## Created at runtime by map_generator (named "DayNight").
## Tints the world for morning, sunset and night with a CanvasModulate
## (the HUD is on its own CanvasLayer, so it stays bright).
## Sleep in your bed to start the next day; stay up until 2 AM and you pass out.

signal new_day(day: int) ## after sleeping or passing out
signal passed_out ## 2 AM: the player collapses and wakes up at home

const DAY_START := 6 * 60 # minutes after midnight
const DAY_END := 26 * 60 # 2 AM the next morning
## Real seconds per game minute: 0.5 = one game hour every 30 seconds (a day is 10 minutes)
const SECONDS_PER_MINUTE := 0.5

# Light colour through the day: hour -> tint (hours past 24 are after midnight)
const LIGHT := [
	[6.0, Color(0.85, 0.8, 0.9)], # early morning, a little blue
	[8.0, Color(1, 1, 1)],
	[17.0, Color(1, 1, 1)],
	[19.0, Color(1.0, 0.82, 0.7)], # sunset
	[20.5, Color(0.6, 0.55, 0.8)], # dusk
	[22.0, Color(0.38, 0.38, 0.62)], # night
	[26.0, Color(0.3, 0.3, 0.55)],
]

var day := 1
var minutes := float(DAY_START)
var paused := false ## stops the clock (shop open, sleeping)

var _tint: CanvasModulate


func _ready() -> void:
	_tint = CanvasModulate.new()
	add_child(_tint)
	_update_tint()


func _process(delta: float) -> void:
	if paused:
		return
	minutes += delta / SECONDS_PER_MINUTE
	if minutes >= DAY_END:
		minutes = DAY_END
		paused = true
		passed_out.emit()
	_update_tint()


## Starts the next morning. Called when sleeping (or after passing out).
func start_new_day() -> void:
	day += 1
	minutes = DAY_START
	paused = false
	_update_tint()
	new_day.emit(day)


## e.g. "Day 3   8:30 PM" (shown in 10-minute steps like most farming games)
func time_text() -> String:
	var total := int(minutes) / 10 * 10
	var hour := (total / 60) % 24
	var suffix := "AM" if hour < 12 else "PM"
	var hour12 := hour % 12
	if hour12 == 0:
		hour12 = 12
	return "Day %d   %d:%02d %s" % [day, hour12, total % 60, suffix]


func _update_tint() -> void:
	var hour := minutes / 60.0
	for i in range(1, LIGHT.size()):
		if hour <= LIGHT[i][0]:
			var a: Array = LIGHT[i - 1]
			var b: Array = LIGHT[i]
			_tint.color = a[1].lerp(b[1], (hour - a[0]) / (b[0] - a[0]))
			return
	_tint.color = LIGHT.back()[1]
