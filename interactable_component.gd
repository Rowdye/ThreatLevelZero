class_name InteractableComponent
extends Node3D

@export var interactable_action: String = "Use"
@export var interactable_name: String = "undefined"

const OUTLINE = preload("res://materials/interactable_outline.tres")
var players_hovering = {}

signal interacted()

func interact_with():
	interacted.emit()

func hover_cursor(player: CharacterBody3D):
	players_hovering[player] = Engine.get_process_frames()

func get_player_hovered_by_cam() -> CharacterBody3D:
	for player in players_hovering.keys():
		var camera = get_viewport().get_camera_3d() if get_viewport() else null
		if camera in player.find_children("*", "Camera3D"):
			return player
	return null

func _process(delta: float) -> void:
	for player in players_hovering.keys():
		if Engine.get_process_frames() - players_hovering[player] > 1:
			players_hovering.erase(player)
	
	if get_player_hovered_by_cam():
		var model: GeometryInstance3D = get_child(0)
		model.material_overlay = OUTLINE
		
		UiManager.show_interaction(true)
		UiManager.change_interaction_label(interactable_action, interactable_name)
	else:
		var model: GeometryInstance3D = get_child(0)
		model.material_overlay = null
		
		UiManager.show_interaction(false)
		UiManager.change_interaction_label("", "")
