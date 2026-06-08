extends Node

# FMOD audio manager (additive layer - only READS from fetch_data, never edits his code)

# Drag the fetch_data node onto this slot in the Inspector (needed in Milestone 2).
@export var data: Node

const BANK_STRINGS := "res://FmodBanks/Desktop/Master.strings.bank"
const BANK_MASTER := "res://FmodBanks/Desktop/Master.bank"
const AMBIENCE_EVENT := "event:/ambience/world"

var _banks: Array = []
var _ambience = null


func _ready() -> void:
	if not _load_banks():
		print("FMOD: banks not found yet - audio manager idle.")
		return
	_start_ambience()


func _load_banks() -> bool:
	if not FileAccess.file_exists(BANK_STRINGS):
		return false
	if not FileAccess.file_exists(BANK_MASTER):
		return false
	# strings bank first, then master (load-order rule)
	_banks.append(FmodServer.load_bank(BANK_STRINGS, FmodServer.FMOD_STUDIO_LOAD_BANK_NORMAL))
	_banks.append(FmodServer.load_bank(BANK_MASTER, FmodServer.FMOD_STUDIO_LOAD_BANK_NORMAL))
	return true


func _start_ambience() -> void:
	_ambience = FmodServer.create_event_instance(AMBIENCE_EVENT)
	if _ambience == null:
		print("FMOD: event not found - author event:/ambience/world in FMOD Studio.")
		return
	_ambience.start()
