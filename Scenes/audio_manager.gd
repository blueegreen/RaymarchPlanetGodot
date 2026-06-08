extends Node

# =============================================================
# FMOD audio manager  (ADDITIVE LAYER)
# =============================================================

@export var data: Node

# --- Bank files -------------------------------------------------
# IMPORTANT: the strings bank must be loaded BEFORE the master bank.
const BANK_STRINGS := "res://FmodBanks/Desktop/Master.strings.bank"
const BANK_MASTER  := "res://FmodBanks/Desktop/Master.bank"

# --- Event path -------------------------------------------------
# Must EXACTLY match the event path you create in FMOD Studio.
const AMBIENCE_EVENT := "event:/ambience/world"

# Keep references so the banks/event are not garbage-collected
# (FMOD banks are RefCounted — losing the reference unloads them).
var _banks: Array = []
var _ambience: FmodEvent = null


func _ready() -> void:
	if not _load_banks():
		push_warning("FMOD: no banks found in res://Banks/ yet. " \
			+ "Audio manager is idle. Build banks in FMOD Studio and " \
			+ "they will load automatically — no code change needed.")
		return
	_start_ambience()


# Returns true only if both bank files exist and loaded.
func _load_banks() -> bool:
	if not FileAccess.file_exists(BANK_STRINGS) \
	or not FileAccess.file_exists(BANK_MASTER):
		return false
	# strings first, then master (load-order rule)
	_banks.append(FmodServer.load_bank(BANK_STRINGS, FmodServer.FMOD_STUDIO_LOAD_BANK_NORMAL))
	_banks.append(FmodServer.load_bank(BANK_MASTER,  FmodServer.FMOD_STUDIO_LOAD_BANK_NORMAL))
	return true


func _start_ambience() -> void:
	_ambience = FmodServer.create_event_instance(AMBIENCE_EVENT)
	if _ambience == null:
		push_warning("FMOD: event '%s' not found in the loaded banks. " \
			% AMBIENCE_EVENT + "Check the event path in FMOD Studio.")
		return
	_ambience.start()


# =============================================================
# MILESTONE 2 — parameter wiring (leave commented until you have
# layers + parameters authored in FMOD Studio). When ready:
#   1. uncomment this _process function
#   2. make sure `data` is wired in the Inspector
# Each line reads a getter from the friend's code and pushes it
# into the matching FMOD parameter. Nothing here touches his code.
# =============================================================
#func _process(_delta: float) -> void:
#	if _ambience == null or data == null:
#		return
#	_ambience.set_parameter_by_name("underwater_depth", data.get_underwater_depth())
#	_ambience.set_parameter_by_name("atmosphere_height", data.get_atmosphere_height())
#	_ambience.set_parameter_by_name("cloud_height",      data.get_cloud_layer_height())
#	_ambience.set_parameter_by_name("time_of_day",       data.get_time_of_day())
#	_ambience.set_parameter_by_name("tide",              data.get_time_of_tide())
#	_ambience.set_parameter_by_name("speed",             data.get_speed_ratio())
#
#	# --- one-shots (fire once on the transition frame) ---
#	# NOTE: set this node's `process_priority` to 1 in the Inspector so it
#	# runs AFTER fetch_data updates these latched values each frame.
#	var splash := data.get_water_splash()
#	if splash == 1:
#		FmodServer.create_event_instance("event:/oneshot/splash_enter").start()
#	elif splash == -1:
#		FmodServer.create_event_instance("event:/oneshot/splash_exit").start()
#	if data.is_started_boost():
#		FmodServer.create_event_instance("event:/oneshot/boost").start()
