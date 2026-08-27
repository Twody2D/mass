class_name WorldEvent
extends RefCounted
## One thing that can happen to the world, from outside the bots' own heads.
##
## Events are objects rather than branches in a match statement, so adding one
## is a new file and a single line of registration. Nothing in the simulation
## imports them: EventManager is the only door in.

## The name the event is triggered by. Unique across the registry.
func id() -> StringName:
	push_error("WorldEvent: an event did not override id().")
	return &""


## Makes it happen. `params` is optional and event specific; every event must
## work with an empty dictionary, so triggering one is never more than a name.
##
## Returns a one line description for the overlay, or an empty string to say it
## refused the parameters it was given. An event that refuses must say why with
## push_error first: EventManager only knows that nothing happened.
func fire(_events: EventManager, _params: Dictionary) -> String:
	push_error("WorldEvent: an event did not override fire().")
	return ""
