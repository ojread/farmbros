extends Node
class_name Inventory
## Per-player item counts.
##
## The server owns everything: it adds and removes items, and sends each
## player's own list to that player only. Clients just display `local_items`.
## Nothing is saved yet; a player's items are lost when they disconnect.

signal changed

const MAX_STACK := 99

## Client: this player's items (item id -> count).
var local_items := {}

# Server: peer id -> { item id (String) -> count }
var _by_peer := {}


# --- Server ------------------------------------------------------------------

## Returns how many were actually added (less than `amount` if the stack is full).
func add(peer_id: int, item_id: StringName, amount := 1) -> int:
	if not multiplayer.is_server():
		return 0
	var items: Dictionary = _by_peer.get_or_add(peer_id, {})
	var key := String(item_id)
	var have := int(items.get(key, 0))
	var added := mini(amount, MAX_STACK - have)
	if added <= 0:
		return 0
	items[key] = have + added
	_send(peer_id)
	return added


func remove(peer_id: int, item_id: StringName, amount := 1) -> bool:
	if not multiplayer.is_server():
		return false
	var items: Dictionary = _by_peer.get(peer_id, {})
	var key := String(item_id)
	var have := int(items.get(key, 0))
	if have < amount:
		return false
	if have == amount:
		items.erase(key)
	else:
		items[key] = have - amount
	_send(peer_id)
	return true


func count(peer_id: int, item_id: StringName) -> int:
	var items: Dictionary = _by_peer.get(peer_id, {})
	return int(items.get(String(item_id), 0))


func forget(peer_id: int) -> void:
	_by_peer.erase(peer_id)


func _send(peer_id: int) -> void:
	_receive.rpc_id(peer_id, _by_peer.get(peer_id, {}))


# --- Client ------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _receive(items: Dictionary) -> void:
	local_items = items
	changed.emit()


func clear_local() -> void:
	local_items = {}
	changed.emit()
