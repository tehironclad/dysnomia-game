class_name UpdateCheck
extends RefCounted
## "A new version is out": the front door reads the site's download manifest once per
## launch (GET https://enterdysnomia.com/api/download-manifest) and compares its version
## with this build's (application/config/version, written by release.yml; absent in dev
## runs, so no notice and no request there).
##
## Only the manifest's `version` is used. Its file URLs are never followed: the notice's
## Download button opens the constant DOWNLOAD_PAGE (LEARNINGS §22, never act on a URL from
## site/server text). A failed, slow, huge or malformed answer means no notice, quietly.

const DOWNLOAD_PAGE := "https://enterdysnomia.com/download"
const MANIFEST_URL := "https://enterdysnomia.com/api/download-manifest"
const TIMEOUT_S := 8.0
const MAX_BYTES := 64 * 1024  # the manifest is a few hundred bytes
const MAX_PART_DIGITS := 6    # 999999.999999.999999: plenty, and never near an int overflow

## One read per launch, shared by every front door this run: {} until it lands.
static var launch_result := {}
static var _started := false


## "x.y.z" (digits only, no leading zeros, nothing before or after) → [x, y, z];
## anything else → [] (pre-release tags, "v1.2.3", spaces, 4 parts, "01.2.3"…).
static func parse_version(v) -> PackedInt32Array:
	if typeof(v) != TYPE_STRING:
		return PackedInt32Array()
	var parts := String(v).split(".", true)
	if parts.size() != 3:
		return PackedInt32Array()
	var out := PackedInt32Array()
	for p in parts:
		if p.is_empty() or p.length() > MAX_PART_DIGITS:
			return PackedInt32Array()
		for i in p.length():
			var c := p.unicode_at(i)
			if c < 48 or c > 57:
				return PackedInt32Array()
		if p.length() > 1 and p.begins_with("0"):
			return PackedInt32Array()
		out.append(p.to_int())
	return out


static func is_valid(v) -> bool:
	return parse_version(v).size() == 3


## -1, 0, 1 (a < b, equal, a > b). Both must be valid: check is_valid first.
static func compare(a: String, b: String) -> int:
	var x := parse_version(a)
	var y := parse_version(b)
	for i in 3:
		if x[i] != y[i]:
			return -1 if x[i] < y[i] else 1
	return 0


## The manifest's version when the answer is usable ({status:"ok", version:"x.y.z"}), else "".
## "not_configured" / "unavailable" / anything else → "".
static func manifest_version(data) -> String:
	if not (data is Dictionary):
		return ""
	if typeof(data.get("status")) != TYPE_STRING or String(data["status"]) != "ok":
		return ""
	var v = data.get("version")
	return String(v) if is_valid(v) else ""


## Show the notice? Only for a valid build version, a strictly newer remote one, and
## not the version the player said "Later" to.
static func should_notify(current: String, remote: String, dismissed: String = "") -> bool:
	if not is_valid(current) or not is_valid(remote):
		return false
	if remote == dismissed:
		return false
	return compare(remote, current) > 0


## This build's version ("" in dev runs: the release workflow writes it).
static func current_version() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	return v if is_valid(v) else ""


## The once-per-launch read. Returns {"version": "x.y.z"} or {} (failed, not configured,
## dev build, site accelerator off). Later callers get the first answer.
static func check_once(host: Node, enabled: bool = true) -> Dictionary:
	if _started:
		return launch_result
	_started = true
	if not enabled or current_version() == "":
		return launch_result
	var v := await fetch(host)
	if v != "":
		launch_result = {"version": v}
	return launch_result


## GET the manifest (HTTPS, capped, timed out). "" on any failure.
static func fetch(host: Node) -> String:
	if host == null or not host.is_inside_tree():
		return ""
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	http.body_size_limit = MAX_BYTES
	http.max_redirects = 0  # the endpoint answers directly; a redirect is not followed elsewhere
	Rpc.apply_tls(http)
	host.add_child(http)
	if http.request(MANIFEST_URL) != OK:
		http.queue_free()
		return ""
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return ""
	var body: PackedByteArray = r[3]
	if body.size() > MAX_BYTES:
		return ""
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return ""
	return manifest_version(json.data)
