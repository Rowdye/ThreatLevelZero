extends Control

@onready var interaction_label: Label = $InteractionLabel

@export var ui_enabled: bool = true

func change_interaction_label(action_name: String, interactable_name: String):
	interaction_label.text = action_name + " " + interactable_name

func show_interaction(show: bool):
	if show:
		interaction_label.visible = true
	else:
		interaction_label.visible = false
