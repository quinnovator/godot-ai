extends Node3D

@export var speed: float = 3.0
var physics_ticks: int = 0


func _physics_process(delta: float) -> void:
	physics_ticks += 1
	position.x += Input.get_axis("ui_left", "ui_right") * speed * delta
