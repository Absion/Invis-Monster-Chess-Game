extends Node3D
class_name Context

## Base Context class representing a discrete game state.
##
## Contexts manage their own isolated rules and nodes.
## Services (managers) are instantiated as node children of a Context.
## The lifecycle of a Context involves building services, binding their dependencies,
## and finally calling setup().

## Array to hold all managed services by this context.
var services: Array[Node] = []

func _ready() -> void:
	build_services()
	bind_services()
	setup()

## Instantiates Services and adds them as children to this Context.
## Should be overridden by subclasses.
func build_services() -> void:
	pass

## Injects dependencies into the built Services.
## Should be overridden by subclasses.
func bind_services() -> void:
	pass

## Initializes the Services now that dependencies are resolved.
## Should be overridden by subclasses.
func setup() -> void:
	pass

## Utility method to register and add a service.
func register_service(service: Node) -> void:
	services.append(service)
	add_child(service)
