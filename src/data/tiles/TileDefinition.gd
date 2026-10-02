class_name TileDefinition
extends Resource

@export var id: StringName

@export_category("Movement")
@export var walkable: bool = true
@export var movement_cost: float = 1.0

@export_category("Farming")
@export var tillable: bool = false
@export var plantable: bool = false

@export_category("Building")
@export var buildable: bool = false

@export_category("Interaction")
@export var fishable: bool = false
@export var forageable: bool = false
