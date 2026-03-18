class_name WeaponManager
extends Node3D

@export var current_weapon: WeaponResource

@export var player: CharacterBody3D
@export var bullet_raycast: RayCast3D 

@export var viewmodel_container: Node3D
@export var worldmodel_container: Node3D

var current_weapon_viewmodel: Node3D
var current_weapon_worldmodel: Node3D

func update_weapon_model()-> void:
	if current_weapon != null:
		if viewmodel_container and current_weapon.viewmodel:
			current_weapon_viewmodel = current_weapon.viewmodel.instantiate()
			viewmodel_container.add_child(current_weapon_viewmodel)
			
			current_weapon_viewmodel.position = current_weapon.vm_position
			current_weapon_viewmodel.rotation = current_weapon.vm_rotation
			current_weapon_viewmodel.scale = current_weapon.vm_scale
		if worldmodel_container and current_weapon.worldmodel:
			current_weapon_worldmodel = current_weapon.worldmodel.instantiate()
			worldmodel_container.add_child(current_weapon_worldmodel)
			
			current_weapon_worldmodel.position = current_weapon.wm_position
			current_weapon_worldmodel.rotation = current_weapon.wm_rotation
			current_weapon_worldmodel.scale = current_weapon.wm_scale

func _ready() -> void:
	update_weapon_model()
