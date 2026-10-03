extends Node

# Wire these to your own moderation endpoint for real AI review.
# Empty url = heuristic-only (still enforced, just no LLM call).
@export var ai_review_url := ""
@export var ai_review_key := ""

const NAME_MAX_LEN := 24
const MAX_RULES := 4
const MIN_TIMER_SECONDS := 0.5
const VALID_TRIGGERS := ["touch", "hit", "timer", "break"]
const VALID_ACTIONS := ["apply_force", "deal_damage", "heal", "change_color", "spawn_particle", "destroy_self", "spawn_block"]
const BANNED_WORDS := ["fuck", "shit", "cunt", "rape", "nigger", "retard"]

func review(def: Dictionary) -> Dictionary:
	var heuristic := _heuristic_check(def)
	if not heuristic.approved:
		return heuristic
	if ai_review_url == "":
		return heuristic
	return await _ai_check(def)

func sanitize(def: Dictionary) -> Dictionary:
	return {
		"name": str(def.get("name", "Block")).strip_edges().substr(0, NAME_MAX_LEN),
		"color": def.get("color", Color(0.8, 0.8, 0.8, 1)),
		"rules": def.get("rules", []),
	}

func _heuristic_check(def: Dictionary) -> Dictionary:
	var block_name: String = str(def.get("name", "")).strip_edges()
	if block_name.is_empty() or block_name.length() > NAME_MAX_LEN:
		return {"approved": false, "reason": "Name must be 1-%d characters" % NAME_MAX_LEN}

	var lower := block_name.to_lower()
	for word in BANNED_WORDS:
		if lower.contains(word):
			return {"approved": false, "reason": "Name not allowed"}

	var rules: Array = def.get("rules", [])
	if rules.size() > MAX_RULES:
		return {"approved": false, "reason": "Too many rules (max %d)" % MAX_RULES}

	for rule in rules:
		if not VALID_TRIGGERS.has(rule.get("trigger")):
			return {"approved": false, "reason": "Unknown trigger"}
		if not VALID_ACTIONS.has(rule.get("action")):
			return {"approved": false, "reason": "Unknown action"}
		if rule.get("trigger") == "timer":
			var secs: float = float(rule.get("trigger_args", {}).get("seconds", 2.0))
			if secs < MIN_TIMER_SECONDS:
				return {"approved": false, "reason": "Timer interval too short (min %.1fs)" % MIN_TIMER_SECONDS}

	return {"approved": true, "reason": ""}

func _ai_check(def: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"block": def})
	var headers := ["Content-Type: application/json", "Authorization: Bearer %s" % ai_review_key]
	var err := http.request(ai_review_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"approved": true, "reason": "AI review unavailable, allowed by default"}

	var result: Array = await http.request_completed
	http.queue_free()

	var response_code: int = result[1]
	var body_bytes: PackedByteArray = result[3]
	if response_code != 200:
		return {"approved": true, "reason": "AI review unavailable, allowed by default"}

	var parsed = JSON.parse_string(body_bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"approved": true, "reason": "AI review returned bad data, allowed by default"}
	return {"approved": bool(parsed.get("approved", true)), "reason": str(parsed.get("reason", ""))}
